//
//  VVDatabase.m
//  VVSequelize
//
//  Created by Valo on 2019/3/19.
//

#import "VVDatabase.h"
#import "VVDBStatement.h"
#import "NSObject+VVOrm.h"

#ifdef SQLITE_HAS_CODEC
#import "sqlite3.h"
#else
#import <sqlite3.h>
#endif

NSString *const VVDBPathInMemory = @":memory:";
NSString *const VVDBPathTemporary = @"";
NSString *const VVDBErrorDomain = @"com.valo.sequelize";

int VVDBEssentialFlags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;

// MARK: - sqlite callbacks
static int vvdb_busy_callback(void *pCtx, int times)
{
    VVDatabase *vvdb = (__bridge VVDatabase *)pCtx;
    return !vvdb.busyHandler ? 0 : vvdb.busyHandler(times);
}

static int vvdb_trace_callback(unsigned mask, void *pCtx, void *p, void *x)
{
    VVDatabase *vvdb = (__bridge VVDatabase *)pCtx;
    return !vvdb.traceHook ? 0 : vvdb.traceHook(mask, p, x);
}

static void vvdb_update_hook(void *pCtx, int op, char const *db, char const *table, int64_t rowid)
{
    VVDatabase *vvdb = (__bridge VVDatabase *)pCtx;
    [vvdb.cache removeAllObjects];
    !vvdb.updateHook ? : vvdb.updateHook(op, db, table, rowid);
}

static int vvdb_commit_hook(void *pCtx)
{
    VVDatabase *vvdb = (__bridge VVDatabase *)pCtx;
    [vvdb.cache removeAllObjects];
    return !vvdb.commitHook ? 0 : vvdb.commitHook();
}

static void vvdb_rollback_hook(void *pCtx)
{
    VVDatabase *vvdb = (__bridge VVDatabase *)pCtx;
    !vvdb.rollbackHook ? : vvdb.rollbackHook();
}

// MARK: -
@interface VVDatabase ()
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSCache *stmtCache;
@property (nonatomic, assign) sqlite3 *db;
@end

@implementation VVDatabase

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        self.path = path;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

+ (instancetype)databaseWithPath:(nullable NSString *)path
{
    return [VVDatabase databaseWithPath:path flags:0 encrypt:nil];
}

+ (instancetype)databaseWithPath:(nullable NSString *)path flags:(BOOL)flags
{
    return [VVDatabase databaseWithPath:path flags:flags encrypt:nil];
}

+ (instancetype)databaseWithPath:(nullable NSString *)path flags:(int)flags encrypt:(nullable NSString *)key
{
    VVDatabase *vvdb = [[VVDatabase alloc] initWithPath:path];
    vvdb.path = path;
    vvdb.flags = flags;
    vvdb.encryptKey = key;
    [vvdb open];
    return vvdb;
}

//MARK: - open and close
- (BOOL)open
{
    int rc = sqlite3_open_v2(self.path.UTF8String, &_db, self.flags, NULL);
    BOOL ret = [self check:rc];
    NSAssert1(ret, @"failed to open sqlite3: %@", self.path);
#ifdef SQLITE_HAS_CODEC
    if (self.encryptKey.length > 0) {
        [self key:self.encryptKey db:nil];
    }
#endif
    // default options
    [self setOptions:@[@"PRAGMA synchronous='NORMAL'",
                       @"PRAGMA journal_mode=wal"]];
    // hook
    sqlite3_update_hook(_db, vvdb_update_hook, (__bridge void *)self);
    sqlite3_commit_hook(_db, vvdb_commit_hook, (__bridge void *)self);
    return ret;
}

- (BOOL)close
{
    BOOL ret = [self check:sqlite3_close_v2(_db)];
    if (ret) {
        _db = NULL;
    }
    return ret;
}

- (void)setOptions:(NSArray<NSString *> *)options
{
    for (NSString *sql in options) {
        [self query:sql];
    }
}

//MARK: - lazy loading
- (sqlite3 *)db
{
    if (!_db) {
        [self open];
    }
    return _db;
}

- (NSCache *)cache
{
    static NSMutableDictionary *_caches;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _caches = [NSMutableDictionary dictionaryWithCapacity:0];
    });
    @synchronized (_caches) {
        NSCache *cache = _caches[self.path];
        if (!cache) {
            cache = [[NSCache alloc] init];
            cache.countLimit = 1000;
            cache.totalCostLimit = 1024 * 1024;
            _caches[self.path] = cache;
        }
        return cache;
    }
}

- (NSCache *)stmtCache
{
    if (!_stmtCache) {
        _stmtCache = [[NSCache alloc] init];
        _stmtCache.countLimit = 1000;
        _stmtCache.totalCostLimit = 1024 * 1024;
    }
    return _stmtCache;
}

- (int)flags
{
    if ((_flags & VVDBEssentialFlags) != VVDBEssentialFlags) {
        _flags |= VVDBEssentialFlags;
    }
    return _flags;
}

- (NSString *)path
{
    if (!_path) {
        _path = VVDBPathTemporary;
    }
    return _path;
}

// MARK: - getter
- (BOOL)isOpen
{
    return _db != NULL;
}

- (BOOL)readonly
{
    return sqlite3_db_readonly(self.db, nil) == 1;
}

- (int)changes
{
    return (int)sqlite3_changes(self.db);
}

- (int)totalChanges
{
    return (int)sqlite3_total_changes(self.db);
}

- (int64_t)lastInsertRowid
{
    return sqlite3_last_insert_rowid(self.db);
}

// MARK: - Execute
- (BOOL)excute:(NSString *)sql
{
    int rc = sqlite3_exec(self.db, sql.UTF8String, nil, nil, nil);
    return [self check:rc];
}

// MARK: - Prepare
- (VVDBStatement *)prepare:(NSString *)sql
{
    return [VVDBStatement statementWithDatabase:self sql:sql];
}

- (VVDBStatement *)prepare:(NSString *)sql bind:(NSArray *)values
{
    VVDBStatement *statement = [VVDBStatement statementWithDatabase:self sql:sql];
    return [statement bind:values];
}

- (VVDBStatement *)prepare:(NSString *)sql bindKeyValues:(NSDictionary<NSString *, id> *)keyValues
{
    VVDBStatement *statement = [VVDBStatement statementWithDatabase:self sql:sql];
    return [statement bindKeyValues:keyValues];
}

// MARK: - Run
- (NSArray *)query:(NSString *)sql
{
    return [[self prepare:sql] query];
}

- (BOOL)isExist:(NSString *)table
{
    NSString *sql = [NSString stringWithFormat:@"SELECT count(*) as 'count' FROM sqlite_master WHERE type ='table' and tbl_name = \"%@\"", table];
    return [[self scalar:sql bind:nil] boolValue];
}

- (BOOL)run:(NSString *)sql
{
    return [[self prepare:sql] run];
}

- (BOOL)run:(NSString *)sql bind:(NSArray *)values
{
    return [[self prepare:sql bind:values] run];
}

- (BOOL)run:(NSString *)sql bindKeyValues:(NSDictionary<NSString *, id> *)keyValues
{
    return [[self prepare:sql bindKeyValues:keyValues] run];
}

// MARK: - Scalar
- (id)scalar:(NSString *)sql bind:(nullable NSArray *)values
{
    VVDBStatement *statement = [VVDBStatement statementWithDatabase:self sql:sql];
    return [statement scalar:values];
}

- (id)scalar:(NSString *)sql bindKeyValues:(nullable NSDictionary<NSString *, id> *)keyValues
{
    VVDBStatement *statement = [VVDBStatement statementWithDatabase:self sql:sql];
    return [statement scalarKeyValues:keyValues];
}

// MARK: - Transactions
- (BOOL)begin:(VVDBTransaction)mode
{
    NSString *sql = nil;
    switch (mode) {
        case VVDBTransactionImmediate:
            sql = @"BEGIN IMMEDIATE TRANSACTION";
            break;
        case VVDBTransactionExclusive:
            sql = @"BEGIN EXCLUSIVE TRANSACTION";
            break;
        default:
            sql = @"BEGIN DEFERRED TRANSACTION";
            break;
    }
    return [self excute:sql];
}

- (BOOL)commit
{
    return [self excute:@"COMMIT TRANSACTION"];
}

- (BOOL)rollback
{
    return [self excute:@"ROLLBACK TRANSACTION"];
}

- (BOOL)savepoint:(NSString *)name block:(BOOL (^)(void))block
{
    NSString *savepoint = [NSString stringWithFormat:@"SAVEPOINT %@", [name quota:@"\""]];
    NSString *commit = [NSString stringWithFormat:@"RELEASE %@", savepoint];
    NSString *rollback = [NSString stringWithFormat:@"ROLLBACK TO %@", savepoint];
    return [self transaction:savepoint commit:commit rollback:rollback block:block];
}

- (BOOL)transaction:(VVDBTransaction)mode block:(BOOL (^)(void))block
{
    NSString *begin = nil;
    switch (mode) {
        case VVDBTransactionImmediate:
            begin = @"BEGIN IMMEDIATE TRANSACTION";
            break;
        case VVDBTransactionExclusive:
            begin = @"BEGIN EXCLUSIVE TRANSACTION";
            break;
        default:
            begin = @"BEGIN DEFERRED TRANSACTION";
            break;
    }
    NSString *commit = @"COMMIT TRANSACTION";
    NSString *rollback = @"ROLLBACK TRANSACTION";
    return [self transaction:begin commit:commit rollback:rollback block:block];
}

- (BOOL)transaction:(NSString *)begin
             commit:(NSString *)commit
           rollback:(NSString *)rollback
              block:(BOOL (^)(void))block
{
    if (!block) {
        return YES;
    }
    BOOL ret = [self excute:begin];
    if (!ret) {
        return NO;
    }
    ret = block();
    if (ret) {
        [self excute:commit];
    } else {
        [self excute:rollback];
    }
    return ret;
}

- (void)interrupt
{
    sqlite3_interrupt(self.db);
}

// MARK: - dbrs
- (void)setTimeout:(NSTimeInterval)timeout
{
    _timeout = timeout;
    sqlite3_busy_timeout(self.db, (int32_t)(timeout * 1000));
}

- (void)setbusyHandler:(VVDBBusyHandler)busyHandler
{
    _busyHandler = busyHandler;
    if (!busyHandler) {
        sqlite3_busy_handler(self.db, NULL, NULL);
    } else {
        sqlite3_busy_handler(self.db, vvdb_busy_callback, (__bridge void *)self);
    }
}

- (void)setTraceHook:(VVDBTraceHook)traceHook
{
    _traceHook = traceHook;
    if (!traceHook) {
        sqlite3_trace_v2(self.db, 0, NULL, NULL);
    } else {
        sqlite3_trace_v2(self.db, SQLITE_TRACE_STMT, vvdb_trace_callback, (__bridge void *)self);
    }
}

/* sqlite3_update_hook has been set when `-open`
 - (void)setUpdateHook:(VVDBUpdateHook)updateHook{
 _updateHook = updateHook;
 if (!updateHook) {
 sqlite3_update_hook(self.db, NULL, NULL);
 }
 else{
 sqlite3_update_hook(self.db, vvdb_update_hook, (__bridge void *)self);
 }
 }
 */

/* sqlite3_commit_hook has been set when `-open`
 - (void)setCommitHook:(VVDBCommitHook)commitHook{
 _commitHook = commitHook;
 if (!commitHook) {
 sqlite3_commit_hook(self.db, NULL, NULL);
 }
 else{
 sqlite3_commit_hook(self.db, vvdb_commit_hook, (__bridge void *)self);
 }
 }
 */

- (void)setRollbackHook:(VVDBRollbackHook)rollbackHook
{
    _rollbackHook = rollbackHook;
    if (!rollbackHook) {
        sqlite3_rollback_hook(self.db, NULL, NULL);
    } else {
        sqlite3_rollback_hook(self.db, vvdb_rollback_hook, (__bridge void *)self);
    }
}

// MARK: - Error Handling
- (BOOL)check:(int)resultCode
{
    switch (resultCode) {
        case SQLITE_OK:
        case SQLITE_ROW:
        case SQLITE_DONE:
            return YES;
            
        default:
            return NO;
    }
}

- (int)lastErrorCode
{
    return sqlite3_errcode(self.db);
}

- (NSError *)lastError
{
    int code = sqlite3_errcode(self.db);
    const char *errmsg = sqlite3_errstr(code);
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
    userInfo[NSLocalizedFailureReasonErrorKey] = [NSString stringWithUTF8String:errmsg];
    NSError *error = [NSError errorWithDomain:VVDBErrorDomain code:code userInfo:userInfo];
    return error;
}

// MARK: - cipher
#ifdef SQLITE_HAS_CODEC
- (NSString *)cipherVersion
{
    if (!_cipherVersion) {
        _cipherVersion = [self scalar:@"PRAGMA cipher_version" bind:nil];
    }
    return _cipherVersion;
}

- (BOOL)key:(NSString *)key db:(NSString *)db
{
    const char *dbname = db ? db.UTF8String : "main";
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    int rc = sqlite3_key_v2(self.db, dbname, data.bytes, (int)data.length);
    return [self check:rc];
}

- (BOOL)rekey:(NSString *)key db:(NSString *)db
{
    const char *dbname = db ? db.UTF8String : "main";
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    int rc = sqlite3_rekey_v2(self.db, dbname, data.bytes, (int)data.length);
    return [self check:rc];
}

- (BOOL)cipherKeyCheck
{
    id ret = [self scalar:@"SELECT count(*) FROM sqlite_master;" bind:nil];
    return ret != nil;
}

#endif

@end

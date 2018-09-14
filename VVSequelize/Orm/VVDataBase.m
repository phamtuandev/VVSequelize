//
//  VVDataBase.m
//  VVSequelize
//
//  Created by Jinbo Li on 2018/6/6.
//

#import "VVDataBase.h"
#import "VVSequelize.h"

#if __has_include(<VVSequelize/VVSequelize.h>)
#import <fmdb/FMDB.h>
#else
#import "FMDB.h"
#endif

@interface VVDataBase ()
@property (nonatomic, strong) FMDatabase *fmdb;
@property (nonatomic, strong) FMDatabaseQueue *fmdbQueue;
@end

@implementation VVDataBase

//MARK: - 创建数据库
/**
 创建数据库单例
 
 @return 数据库单例对象
 */
+ (instancetype)defalutDb{
    static VVDataBase *_vvdb;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _vvdb = [[self alloc] initWithDBName:nil];
    });
    return _vvdb;
}

- (instancetype)initWithDBName:(NSString *)dbName{
    return [self initWithDBName:dbName dirPath:nil encryptKey:nil];
}

- (instancetype)initWithDBName:(NSString *)dbName
                       dirPath:(NSString *)dirPath
                    encryptKey:(NSString *)encryptKey{
    if (dbName.length == 0) {
        dbName = @"vvsequlize.sqlite";
    }
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    if(dirPath && dirPath.length > 0){
        BOOL isDir = NO;
        BOOL exist = [[NSFileManager defaultManager] fileExistsAtPath:dirPath isDirectory:&isDir];
        BOOL valid = exist && isDir;
        if(!valid){
            valid = [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
        if(valid){
            path = dirPath;
        }
    }
    NSString *dbPath =  [path stringByAppendingPathComponent:dbName];
    NSString *homePath = NSHomeDirectory();
    NSRange range = [dbPath rangeOfString:homePath];
    NSString *relativePath = range.location == NSNotFound ?
        dbPath : [dbPath substringFromIndex:range.location + range.length];
#if DEBUG
    NSLog(@"Open or create the database: %@", dbPath);
#endif
    FMDatabaseQueue *fmdbQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
    if (fmdbQueue) {
        self = [self init];
        if (self) {
            _fmdbQueue = fmdbQueue;
            _fmdb = [fmdbQueue valueForKey:@"_db"];
            _dbName = dbName;
            _dbDir  = dirPath;
            _dbPath = dbPath;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            if([self respondsToSelector:@selector(setUserDefaultsKey:)] &&
               [self respondsToSelector:@selector(setEncryptKey:)]){
                NSString *key = [NSString stringWithFormat:@"VVDBEncryptKey%@",relativePath];
                [self performSelector:@selector(setUserDefaultsKey:) withObject:key];
                [self performSelector:@selector(setEncryptKey:) withObject:encryptKey];
            }
#pragma clang diagnostic pop
            // 执行一些设置
            [self executeQuery:@"PRAGMA synchronous='NORMAL'"];
            [self executeQuery:@"PRAGMA journal_mode=wal"];
            return self;
        }
    }
    NSAssert1(NO, @"Open or create the database (%@) failure!",dbPath);
    return nil;
}

//MARK: - 原始SQL语句
- (NSArray *)executeQuery:(NSString *)sql{
    FMResultSet *set = [self.fmdb executeQuery:sql];
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:0];
    while ([set next]) {
        [array addObject:set.resultDictionary];
    }
    if(VVSequelize.trace) VVSequelize.trace(sql, nil, array);
    return array;
}

- (BOOL)executeUpdate:(NSString *)sql{
    BOOL ret = [self.fmdb executeUpdate:sql];
    if(VVSequelize.trace) VVSequelize.trace(sql, nil, @(ret));
    return ret;
}

- (BOOL)executeUpdate:(NSString *)sql
               values:(nonnull NSArray *)values{
    BOOL ret = [self.fmdb executeUpdate:sql withArgumentsInArray:values];
    if(VVSequelize.trace) VVSequelize.trace(sql, values, @(ret));
    return ret;
}

- (BOOL)isTableExist:(NSString *)tableName{
    NSString *sql = [NSString stringWithFormat:@"SELECT count(*) as 'count' FROM sqlite_master WHERE type ='table' and tbl_name = \"%@\"",tableName];
    NSArray *array = [self executeQuery:sql];
    for (NSDictionary *dic in array) {
        NSInteger count = [dic[@"count"] integerValue];
        return count > 0;
    }
    return NO;
}

//MARK: - 线程安全操作
- (id)inQueue:(id (^)(void))block{
    __block id ret = nil;
    [self.fmdbQueue inDatabase:^(FMDatabase *db) {
        ret = block();
    }];
    return ret;
}

- (id)inTransaction:(id (^)(BOOL * rollback))block{
    __block id ret = nil;
    [self.fmdbQueue inTransaction:^(FMDatabase * db, BOOL * rollback) {
        ret = block(rollback);
    }];
    return ret;
}

//MARK: - 其他操作
- (BOOL)close{
    return [self.fmdb close];
}

- (BOOL)open{
    BOOL ret = [self.fmdb open];
    if(ret){
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if([self respondsToSelector:@selector(encryptKey)] &&
           [self respondsToSelector:@selector(setEncryptKey:)] &&
           [self.fmdb respondsToSelector:@selector(setKey:)]){
            NSString *key = [self performSelector:@selector(encryptKey)];
            if(key.length > 0) [self.fmdb setKey:key];
        }
#pragma clang diagnostic pop
    }
    return ret;
}

@end
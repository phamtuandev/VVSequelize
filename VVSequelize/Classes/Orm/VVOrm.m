//
//  VVOrm.m
//  VVSequelize
//
//  Created by Valo on 2018/6/6.
//

#import "VVOrm.h"
#import "NSObject+VVOrm.h"

@implementation VVOrm

//MARK: - Public
+ (nullable instancetype)ormWithConfig:(VVOrmConfig *)config
{
    return [self ormWithConfig:config tableName:nil dataBase:nil];
}

+ (nullable instancetype)ormWithConfig:(VVOrmConfig *)config
                             tableName:(nullable NSString *)tableName
                              dataBase:(nullable VVDatabase *)vvdb
{
    VVOrm *orm = [[VVOrm alloc] initWithConfig:config tableName:tableName dataBase:vvdb];
    VVOrmInspection comparison = [orm inspectExistingTable];
    [orm setupTableWith:comparison];
    return orm;
}

- (nullable instancetype)initWithConfig:(VVOrmConfig *)config
                              tableName:(nullable NSString *)tableName
                               dataBase:(nullable VVDatabase *)vvdb
{
    BOOL valid = config && config.cls && config.columns.count > 0;
    NSAssert(valid, @"Invalid orm config.");
    if (!valid) return nil;
    self = [super init];
    if (self) {
        NSString *tblName = tableName.length > 0 ? tableName : NSStringFromClass(config.cls);
        VVDatabase *db = vvdb ? vvdb : [VVDatabase databaseWithPath:nil];
        _config = config;
        _tableName = tblName;
        _vvdb = db;
    }
    return self;
}

- (nullable NSDictionary *)uniqueConditionForObject:(id)object
{
    if (_config.primaries.count > 0) {
        NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithCapacity:0];
        for (NSString *key in _config.primaries) {
            id val = [object valueForKey:key];
            dic[key] = val;
        }
        if (dic.count == _config.primaries.count) {
            return dic;
        }
    }
    for (NSString *key in _config.uniques) {
        id val = [object valueForKey:key];
        if (val) return @{ key: val };
    }
    return nil;
}

- (VVOrmInspection)inspectExistingTable
{
    VVOrmInspection inspection = 0x0;
    VVOrmConfig *tableConfig = [VVOrmConfig configFromTable:_tableName database:_vvdb];
    // 检查数据表是否存在
    BOOL ret = [_vvdb isExist:_tableName];
    if (!ret) return inspection;
    inspection |= VVOrmTableExist;
    // 检查数据表和索引是否需要变更
    ret = [_config isEqualToConfig:tableConfig];
    if (!ret) inspection |= VVOrmTableChanged;
    ret = [_config isInedexesEqual:tableConfig];
    if (!ret) inspection |= VVOrmIndexChanged;
    return inspection;
}

- (void)setupTableWith:(VVOrmInspection)inspection
{
    // 若表存在,检查是否需要进行变更.如需变更,则将原数据表进行更名.
    NSString *tempTableName = [NSString stringWithFormat:@"%@_%@", _tableName, @((NSUInteger)[[NSDate date] timeIntervalSince1970])];
    BOOL exist = inspection & VVOrmTableExist;
    BOOL changed = inspection & VVOrmTableChanged;
    BOOL indexChanged = inspection & VVOrmIndexChanged;
    // 字段发生变更,对原数据表进行更名
    if (exist && changed) {
        [self renameToTempTable:tempTableName];
    }
    // 若表不存在或字段发生变更,需要创建新表
    if (!exist || changed) {
        [self createTable];
    }
    // 如果字段发生变更,将原数据表的数据插入新表
    if (exist && changed && !_config.fts) {
        //MARK: FTS表请手动迁移数据
        [self migrationDataFormTempTable:tempTableName];
    }
    // 若索引发生变化,则重建索引
    if (!_config.fts && indexChanged) {
        [self rebuildIndex];
    }
}

//MARK: - Private
- (void)createTable
{
    NSString *sql = nil;
    // 创建FTS表
    if (_config.fts) {
        sql = [_config createFtsSQLWith:_tableName];
    }
    // 创建普通表
    else {
        sql = [_config createSQLWith:_tableName];
    }
    // 执行建表SQL
    BOOL ret = [_vvdb transaction:VVDBTransactionImmediate block:^BOOL {
        return [self.vvdb excute:sql];
    }];
    if (ret) {
    }         // no warning
    NSAssert1(ret, @"Failure to create a table: %@", _tableName);
}

- (void)renameToTempTable:(NSString *)tempTableName
{
    NSString *sql = [NSString stringWithFormat:@"ALTER TABLE \"%@\" RENAME TO \"%@\"", _tableName, tempTableName];
    BOOL ret = [_vvdb transaction:VVDBTransactionImmediate block:^BOOL {
        return [self.vvdb excute:sql];
    }];
    if (ret) {
    }         // no warning
    NSAssert1(ret, @"Failure to create a temporary table: %@", tempTableName);
}

- (void)migrationDataFormTempTable:(NSString *)tempTableName
{
    NSString *allFields = [_config.columns sqlJoin];
    if (allFields.length == 0) {
        return;
    }
    BOOL ret = [_vvdb transaction:VVDBTransactionImmediate block:^BOOL {
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO \"%@\" (%@) SELECT %@ FROM \"%@\"", self.tableName, allFields, allFields, tempTableName];
        return [self.vvdb excute:sql];
    }];
    
    if (ret) {
        NSString *sql = [NSString stringWithFormat:@"DROP TABLE \"%@\"", tempTableName];
        [self.vvdb excute:sql];
    }
    
    if (!ret) {
#if DEBUG
        NSLog(@"Warning: copying data from old table (%@) to new table (%@) failed!", tempTableName, self.tableName);
#endif
    }
}

- (void)rebuildIndex
{
    // FTS表无需创建索引
    if (_config.fts) return;
    NSString *indexesSQL = [NSString stringWithFormat:@"SELECT name FROM sqlite_master WHERE type ='index' and tbl_name = \"%@\"", _tableName];
    NSArray *array = [_vvdb query:indexesSQL];
    NSMutableString *dropIdxSQL = [NSMutableString stringWithCapacity:0];
    for (NSDictionary *dic  in array) {
        NSString *idxName = dic[@"name"];
        if ([idxName hasPrefix:@"sqlite_autoindex_"]) continue;
        [dropIdxSQL appendFormat:@"DROP INDEX IF EXISTS \"%@\";", idxName];
    }
    
    // 建立新索引
    NSString *indexName = [NSString stringWithFormat:@"vvdb_index_%@", _tableName];
    NSString *indexSQL = [_config.indexes sqlJoin];
    NSString *createIdxSQL = nil;
    if (indexSQL.length > 0) {
        createIdxSQL = [NSString stringWithFormat:@"CREATE INDEX \"%@\" on \"%@\" (%@);", indexName, _tableName, indexSQL];
    }
    BOOL ret = [_vvdb transaction:VVDBTransactionImmediate block:^BOOL {
        BOOL r = YES;
        if (dropIdxSQL.length > 0) { r = [self.vvdb excute:dropIdxSQL]; }
        if (r && createIdxSQL.length > 0) { r = [self.vvdb excute:createIdxSQL]; }
        return r;
    }];
    
    if (!ret) {
#if DEBUG
        NSLog(@"Warning: Failed create index for table (%@)!", self.tableName);
#endif
    }
}

@end

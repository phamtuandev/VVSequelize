//
//  VVOrmModel.h
//  VVSequelize
//
//  Created by Jinbo Li on 2018/6/6.
//

#import <Foundation/Foundation.h>
#import "VVFMDB.h"

typedef NS_OPTIONS(NSUInteger, VVOrmOption) {
    VVOrmPrimaryKey = 1 << 0,
    VVOrmUnique = 1 << 1,
    VVOrmNonnull = 1 << 2,
    VVOrmAutoIncrement = 1 << 3,
};

#define VVRangeAll NSMakeRange(0, 0)

#pragma mark - 定义ORM

@interface VVOrmModel : NSObject

/**
 定义ORM模型.使用默认数据库,默认表名,自动主键.
 
 @param cls 模型(Class)
 @return ORM模型
 */
- (instancetype)initWithClass:(Class)cls;


/**
 定义ORM模型.使用自动主键,无额外选项.
 
 @param cls 模型(Class)
 @param tableName 表名,nil表示使用cls类名
 @param vvfmdb 数据库,nil表示使用默认数据库
 @return ORM模型
 */
- (instancetype)initWithClass:(Class)cls
                    tableName:(nullable NSString *)tableName
                     dataBase:(nullable VVFMDB *)vvfmdb;

/**
 定义ORM模型.可自动新增字段,##不会修改或删除原有字段##.
 
 @param cls 模型(Class)
 @param fields 自定义各个字段的配置,格式@{@"field1":@(VVOrmOption),@"field2":@(VVOrmOption),...}}
 @param excludes 不存入数据表的字段名
 @param tableName 表名,nil表示使用cls类名
 @param vvfmdb 数据库,nil表示使用默认数据库
 @return ORM模型
 */
- (instancetype)initWithClass:(Class)cls
                 fieldOptions:(nullable NSDictionary *)fieldOptions
                     excludes:(nullable NSArray *)excludes
                    tableName:(nullable NSString *)tableName
                     dataBase:(nullable VVFMDB *)vvfmdb;

/**
 删除表
 
 @return 是否删除成功
 */
- (BOOL)dropTable;

/**
 检查数据表是否存在
 
 @return 是否存在
 */
- (BOOL)isTableExist;

/**
 为数据表添加不存在的字段
 
 @param dicOrClass 字典或模型(Class),只添加不存在的字段
 @param options 其他选项:{unique:[field],nonnull:[field],exclude:[field]...}
 @return 是否添加成功
 */
- (BOOL)alterWithDicOrClass:(id)dicOrClass
                    options:(NSDictionary *)options;
@end

#pragma mark - CURD(C)创建
@interface VVOrmModel (Create)

-(BOOL)insertOne:(id)object;

-(BOOL)insertMulti:(NSArray *)objects;

@end

#pragma mark - CURD(U)更新
@interface VVOrmModel (Update)

/**
 根据条件更新数据

 @param condition 查询条件,格式详见VVSqlGenerator
 @param values 要设置的数据,格式为{"field1":data1,"field2":data2,...}
 @return 是否更新成功
 */
- (BOOL)update:(NSDictionary *)condition
        values:(NSDictionary *)values;

/**
 更新一条数据,更新不成功不会插入新数据.

 @param object 要更新的数据
 @return 是否更新成功
 */
- (BOOL)updateOne:(id)object;

/**
 更新一条数据,更新失败会插入新数据.

 @param object 要更新的数据
 @return 是否更新或插入成功
 */
- (BOOL)upsertOne:(id)object;

/**
 更新多条数据,更新不成功不会插入新数据.
 
 @param objects 要更新的数据
 @return 是否更新成功
 */
- (BOOL)updateMulti:(NSArray *)objects;

/**
 更新多条数据,更新失败会插入新数据.
 
 @param objects 要更新的数据
 @return 是否更新或插入成功
 */
- (BOOL)upsertMulti:(NSArray *)objects;

/**
 将某个字段的值增加某个数值

 @param condition 查询条件,格式详见VVSqlGenerator
 @param field 要更新的指端
 @param value 要增加的值,可为负数
 @return 是否增加成功
 */
- (BOOL)increase:(nullable NSDictionary *)condition
           field:(NSString *)field
           value:(NSInteger)value;

@end

#pragma mark - CURD(R)读取
@interface VVOrmModel (Retrieve)

/**
 查询一条数据

 @param condition 查询条件,格式详见VVSqlGenerator
 @return 找到的数据
 */
- (nullable id)findOne:(nullable NSDictionary *)condition;


/**
 根据条件查询所有数据

 @param condition 查询条件,格式详见VVSqlGenerator
 @return 查询结果
 */
- (NSArray *)findAll:(nullable NSDictionary *)condition;


/**
 根据条件查询数据

 @param condition 查询条件,格式详见VVSqlGenerator
 @param orderBy 排序方式
 @param range 数据范围,用于翻页,range.length为0时,查询所有数据
 @return 查询结果
 */
- (NSArray *)findAll:(nullable NSDictionary *)condition
             orderBy:(nullable NSDictionary *)orderBy
               range:(NSRange)range;


/**
 根据条件统计数据条数

 @param condition 查询条件,格式详见VVSqlGenerator
 @return 数据条数
 */
- (NSInteger)count:(NSDictionary *)condition;


/**
 检查数据库中是否保存有某个数据

 @param object 数据对象
 @return 是否存在
 */
- (BOOL)isExist:(id)object;

/**
 根据条件查询数据和数据数量.数量只根据查询条件获取,不受range限制.

 @param condition 查询条件,格式详见VVSqlGenerator
 @param orderBy 排序方式
 @param range 数据范围,用于翻页,range.length为0时,查询所有数据
 @return 数据和数据数量,格式为{"count":100,list:[object]}
 */
- (NSDictionary *)findAndCount:(NSDictionary *)condition
                       orderBy:(NSDictionary *)orderBy
                         range:(NSRange)range;

/**
 获取某个字段的最大值

 @param field 字段名
 @return 最大值.因Text也可以计算最大值,故返回值为id类型
 */
- (id)max:(NSString *)field;

/**
 获取某个字段的最小值
 
 @param field 字段名
 @return 最小值.因Text也可以计算最小值,故返回值为id类型
 */
- (id)min:(NSString *)field;

/**
 获取某个字段的求和
 
 @param field 字段名
 @return 求和
 */
- (id)sum:(NSString *)field;

@end

#pragma mark - CURD(D)删除
@interface VVOrmModel (Delete)

/**
 删除表

 @return 是否删除成功
 */
- (BOOL)drop;

/**
 删除一条数据

 @param object 要删除的数据
 @return 是否删除成功
 */
- (BOOL)deleteOne:(id)object;

/**
 删除多条数据

 @param objects 要删除的数据
 @return 是否删除成功
 */
- (BOOL)deleteMulti:(NSArray *)objects;


/**
 根据条件删除数据

 @param condition 查询条件,格式详见VVSqlGenerator
 @return 是否删除成功
 */
- (BOOL)delete:(NSDictionary *)condition;

@end


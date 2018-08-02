//
//  VVDataBase.h
//  VVSequelize
//
//  Created by Jinbo Li on 2018/6/6.
//

#import <Foundation/Foundation.h>

@interface VVDataBase : NSObject
@property (nonatomic, strong) NSString *encryptKey;         ///< 加密Key,可设置
@property (nonatomic, strong, readonly) NSString *dbPath;   ///< 数据库文件全路径
@property (nonatomic, strong, readonly) NSString *dbName;   ///< 数据库文件名
@property (nonatomic, strong, readonly) NSString *dbDir;    ///< 数据库文件所在目录名

//MARK: - 创建数据库
/**
 创建数据库单例
 
 @return 数据库单例对象
 */
+ (instancetype)defalutDb;

/**
 初始化数据库
 
 @param dbName 数据库文件名,如:abc.sqlite, abc.db
 @return 数据库对象
 */
- (instancetype)initWithDBName:(nullable NSString *)dbName;

/**
 初始化数据库
 
 @param dbName 数据库文件名,如:abc.sqlite, abc.db
 @param dirPath 数据库存储路径,若为nil,则路径默认为NSDocumentDirectory
 @param encryptKey 数据库密码,使用SQLCipher加密的密码.若为nil,则不加密.
 @return 数据库对象
 */
- (instancetype)initWithDBName:(nullable NSString *)dbName
                       dirPath:(nullable NSString *)dirPath
                    encryptKey:(nullable NSString *)encryptKey;

//MARK: - 原始SQL语句

/**
 执行SQL查询语句
 
 @param sql sql语句
 @return 查询结果,json数组
 */
- (NSArray *)executeQuery:(nonnull NSString *)sql;

/**
 执行SQL查询语句

 @param sql sql语句
 @param blobFields BLOB类型的字段,查询结果中应转换成NSData类型
 @return 查询结果,json数组
 */
- (NSArray *)executeQuery:(nonnull NSString *)sql
               blobFields:(nullable NSArray<NSString *> *)blobFields;


/**
 执行SQL更新语句

 @param sql sql语句
 @return 是否更新成功
 */
- (BOOL)executeUpdate:(nonnull NSString *)sql;

/**
 执行SQL更新语句
 
 @param sql sql语句
 @param values 对应sql语句中`?`的值
 @return 是否更新成功
 @note 主要针对插入数据时,可能有NSData类型的值,所以插入语句中的values对为(?,?,?,..)格式,由FMDB处理
 */
- (BOOL)executeUpdate:(NSString *)sql
               values:(nonnull NSArray *)values;

/**
 检查数据表是否存在

 @param tableName 表名
 @return 是否存在
 */
- (BOOL)isTableExist:(NSString *)tableName;

//MARK: - 线程安全操作
/**
 线程安全操作
 
 @param block 数据库操作
 @note FMDBQueue是serial的dispatch_queue_t, 实际是同步执行,所以直接返回结果. 若要处理大量数据,可以将inQueue放入异步线程
 @warning `ormModelWithClass`已使用Queue,不能放入block.
 */
- (id)inQueue:(nonnull id (^)(void))block;

/**
 事务操作
 
 @param block 数据库事务操作
 @note FMDBQueue是serial的dispatch_queue_t, 实际是同步执行,所以直接返回结果. 若要处理大量数据,可以将inTransaction放入异步线程
 @warning `ormModelWithClass`已使用Queue,不能放入block.
 */
- (id)inTransaction:(nonnull id (^)(BOOL * rollback))block;

//MARK: - 其他操作
/**
 关闭数据库
 */
- (BOOL)close;

/**
 打开数据库,每次init时已经open,当调用close后若进行db操作需重新open
 */
- (BOOL)open;

@end



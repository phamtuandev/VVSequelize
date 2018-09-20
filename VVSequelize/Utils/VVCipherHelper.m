//
//  VVCipherHelper.m
//  VVSequelize
//
//  Created by Jinbo Li on 2018/6/19.
//

#import "VVCipherHelper.h"
#import <sqlite3.h>

@implementation VVCipherHelper

+ (BOOL)encryptDatabase:(NSString *)path
             encryptKey:(NSString *)encryptKey{
    NSString *sourcePath = path;
    NSString *targetPath = [NSString stringWithFormat:@"%@.tmp.sqlite", path];
    if([self encryptDatabase:sourcePath targetPath:targetPath encryptKey:encryptKey]) {
        NSFileManager *fm = [[NSFileManager alloc] init];
        [fm removeItemAtPath:sourcePath error:nil];
        [fm moveItemAtPath:targetPath toPath:sourcePath error:nil];
        return YES;
    } else {
        return NO;
    }
}

+ (BOOL)decryptDatabase:(NSString *)path
             encryptKey:(NSString *)encryptKey{
    NSString *sourcePath = path;
    NSString *targetPath = [NSString stringWithFormat:@"%@.tmp.sqlite", path];
    if([self decryptDatabase:sourcePath targetPath:targetPath encryptKey:encryptKey]) {
        NSFileManager *fm = [[NSFileManager alloc] init];
        [fm removeItemAtPath:sourcePath error:nil];
        [fm moveItemAtPath:targetPath toPath:sourcePath error:nil];
        return YES;
    } else {
        return NO;
    }
}

+ (BOOL)encryptDatabase:(NSString *)sourcePath
             targetPath:(NSString *)targetPath
             encryptKey:(NSString *)encryptKey{
    if(encryptKey.length == 0){
        return NO;
    }
    const char* sqlQ = [[NSString stringWithFormat:@"ATTACH DATABASE '%@' AS encrypted KEY '%@';", targetPath, encryptKey] UTF8String];
    sqlite3 *decrypted_DB;
    if (sqlite3_open([sourcePath UTF8String], &decrypted_DB) == SQLITE_OK) {
        // Attach empty encrypted database to decrypted database
        sqlite3_exec(decrypted_DB, sqlQ, NULL, NULL, NULL);
        // export database
        sqlite3_exec(decrypted_DB, "SELECT sqlcipher_export('encrypted');", NULL, NULL, NULL);
        // Detach encrypted database
        sqlite3_exec(decrypted_DB, "DETACH DATABASE encrypted;", NULL, NULL, NULL);
        sqlite3_close(decrypted_DB);
        return YES;
    }
    else {
        sqlite3_close(decrypted_DB);
        NSAssert1(NO, @"Failed to open database with message '%s'.", sqlite3_errmsg(decrypted_DB));
        return NO;
    }
}

+ (BOOL)decryptDatabase:(NSString *)sourcePath
             targetPath:(NSString *)targetPath
             encryptKey:(NSString *)encryptKey{
    if(encryptKey.length == 0){
        return NO;
    }
    const char* sqlQ = [[NSString stringWithFormat:@"ATTACH DATABASE '%@' AS plaintext KEY '';", targetPath] UTF8String];
    sqlite3 *encrypted_DB;
    if (sqlite3_open([sourcePath UTF8String], &encrypted_DB) == SQLITE_OK) {
        sqlite3_exec(encrypted_DB, [[NSString stringWithFormat:@"PRAGMA key = '%@';", encryptKey] UTF8String], NULL, NULL, NULL);
        // Attach empty decrypted database to encrypted database
        sqlite3_exec(encrypted_DB, sqlQ, NULL, NULL, NULL);
        // export database
        sqlite3_exec(encrypted_DB, "SELECT sqlcipher_export('plaintext');", NULL, NULL, NULL);
        // Detach decrypted database
        sqlite3_exec(encrypted_DB, "DETACH DATABASE plaintext;", NULL, NULL, NULL);
        sqlite3_close(encrypted_DB);
        return YES;
    }
    else {
        sqlite3_close(encrypted_DB);
        NSAssert1(NO, @"Failed to open database with message '%s'.", sqlite3_errmsg(encrypted_DB));
        return NO;
    }
}

+ (BOOL)changeKeyForDatabase:(NSString *)dbPath
                   originKey:(NSString *)originKey
                      newKey:(NSString *)newKey{
    if ((originKey.length == 0 && newKey.length == 0) ||
        [originKey isEqualToString:newKey]) {
        /// 无需更换加密Key时,直接返回NO.也无需进行加密Key之后的相关操作.
        return NO;
    }
    else if(originKey.length == 0){
        return [self encryptDatabase:dbPath encryptKey:newKey];
    }
    else if(newKey.length == 0){
        return [self decryptDatabase:dbPath encryptKey:originKey];
    }
    sqlite3 *encrypted_DB;
    if (sqlite3_open([dbPath UTF8String], &encrypted_DB) == SQLITE_OK) {
        sqlite3_exec(encrypted_DB, [[NSString stringWithFormat:@"PRAGMA key = '%@';", originKey] UTF8String], NULL, NULL, NULL);
        sqlite3_exec(encrypted_DB, [[NSString stringWithFormat:@"PRAGMA rekey = '%@';", newKey] UTF8String], NULL, NULL, NULL);
        sqlite3_close(encrypted_DB);
        return YES;
    }
    else {
        sqlite3_close(encrypted_DB);
        NSAssert1(NO, @"Failed to open database with message '%s'.", sqlite3_errmsg(encrypted_DB));
        return NO;
    }
}

@end

//
//  VVSqlGenerator.m
//  VVSequelize
//
//  Created by Jinbo Li on 2018/6/13.
//

#import "VVSqlGenerator.h"

@interface NSString (VVCountString)
- (NSInteger)vv_countOccurencesOfString:(NSString*)searchString;
@end

@implementation NSString (VVCountString)
- (NSInteger)vv_countOccurencesOfString:(NSString*)searchString {
    NSInteger strCount = [self length] - [[self stringByReplacingOccurrencesOfString:searchString withString:@""] length];
    return strCount / [searchString length];
}
@end

@implementation VVSqlGenerator

//MARK: - Where语句

+ (NSString *)where:(id)condition{
    if([condition isKindOfClass:[NSString class]] && [condition length] > 0){
        return [NSString stringWithFormat:@" WHERE %@",condition];
    }
    else if([condition isKindOfClass:[NSDictionary class]]){
        NSString *where = [self key:nil _and:condition];
        return where.length > 0 ? [NSString stringWithFormat:@" WHERE %@", where] : @"";
    }
    return @"";
}

+ (NSString *)key:(NSString *)key _operation:(NSString *)op value:(id)val{
    NSMutableString *string = [NSMutableString stringWithCapacity:0];
    if([op isEqualToString:kVsOpAnd]){
        [string appendString:[self key:key _and:val]];
    }
    else if([op isEqualToString:kVsOpOr]) {
        [string appendString:[self key:nil _or:val]];
    }
    else if([op isEqualToString:kVsOpGt]) {
        [string appendString:[self key:key _gt:val]];
    }
    else if([op isEqualToString:kVsOpGte]) {
        [string appendString:[self key:key _gte:val]];
    }
    else if([op isEqualToString:kVsOpLt]) {
        [string appendString:[self key:key _lt:val]];
    }
    else if([op isEqualToString:kVsOpLte]) {
        [string appendString:[self key:key _lte:val]];
    }
    else if([op isEqualToString:kVsOpNe]) {
        [string appendString:[self key:key _ne:val]];
    }
    else if([op isEqualToString:kVsOpNot]) {
        [string appendString:[self key:key _not:val]];
    }
    else if([op isEqualToString:kVsOpBetween]) {
        [string appendString:[self key:key _between:val]];
    }
    else if([op isEqualToString:kVsOpNotBetween]) {
        [string appendString:[self key:key _notBetween:val]];
    }
    else if([op isEqualToString:kVsOpIn]) {
        [string appendString:[self key:key _in:val]];
    }
    else if([op isEqualToString:kVsOpNotIn]) {
        [string appendString:[self key:key _notIn:val]];
    }
    else if([op isEqualToString:kVsOpLike]) {
        [string appendString:[self key:key _like:val]];
    }
    else if([op isEqualToString:kVsOpNotLike]) {
        [string appendString:[self key:key _notLike:val]];
    }
    else if([op isEqualToString:kVsOpGlob]) {
        [string appendString:[self key:key _glob:val]];
    }
    else if([op isEqualToString:kVsOpNotGlob]) {
        [string appendString:[self key:key _notGlob:val]];
    }
    else{
        [string appendString:[self key:key _eq:val]];
    }
    return string;
}

+ (NSString *)key:(NSString *)key _and:(NSDictionary *)dic{
    if(![dic isKindOfClass:[NSDictionary class]]) return @"";
    NSMutableString *string = [NSMutableString stringWithCapacity:0];
    [dic enumerateKeysAndObjectsUsingBlock:^(NSString *subkey, id val, BOOL *stop) {
        if(([subkey hasPrefix:@"$"] && key.length > 0) || [subkey isEqualToString:kVsOpOr]) {
            [string appendFormat:@"%@ AND ", [self key:key _operation:subkey value:val]];
        }
        else{
            [string appendFormat:@"%@ AND ", [self key:subkey _eq:val]];
        }
    }];
    if([string hasSuffix:@" AND "]){
        [string deleteCharactersInRange:NSMakeRange(string.length - 5, 5)];
    }
    NSInteger countAnd = [string vv_countOccurencesOfString:@"AND"];
    NSInteger countOr = [string vv_countOccurencesOfString:@"OR"];
    NSInteger countBrackets = [string vv_countOccurencesOfString:@")"];
    if(countAnd + countOr <= countBrackets) return string;
    return [NSString stringWithFormat:@"(%@)", string];
}

+ (NSString *)key:(NSString *)key _or:(NSArray *)array{
    if(![array isKindOfClass:[NSArray class]]) return @"";
    NSMutableString *string = [NSMutableString stringWithCapacity:0];
    [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [string appendFormat:@"%@ OR ",[self key:key _and:obj]];
    }];
    if([string hasSuffix:@" OR "]){
        [string deleteCharactersInRange:NSMakeRange(string.length - 4, 4)];
    }
    NSInteger countAnd = [string vv_countOccurencesOfString:@"AND"];
    NSInteger countOr = [string vv_countOccurencesOfString:@"OR"];
    NSInteger countBrackets = [string vv_countOccurencesOfString:@")"];
    if(countAnd + countOr <= countBrackets) return string;
    return [NSString stringWithFormat:@"(%@)", string];
}

+ (NSString *)key:(NSString *)key _eq:(id)val{
    if([val isKindOfClass:[NSDictionary class]]){
        return [self key:key _and:val];
    }
    return [NSString stringWithFormat:@"\"%@\" = \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _gt:(id)val{
    return [NSString stringWithFormat:@"\"%@\" > \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _gte:(id)val{
    return [NSString stringWithFormat:@"\"%@\" >= \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _lt:(id)val{
    return [NSString stringWithFormat:@"\"%@\" < \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _lte:(id)val{
    return [NSString stringWithFormat:@"\"%@\" <= \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _ne:(id)val{
    return [NSString stringWithFormat:@"\"%@\" != \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _not:(id)val{
    return [NSString stringWithFormat:@"\"%@\" IS NOT \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _between:(NSArray *)array{
    if(![array isKindOfClass:[NSArray class]] || array.count != 2) return @"";
    return [NSString stringWithFormat:@"\"%@\" BETWEEN \"%@\" AND \"%@\"", key, array[0], array[1]];
}

+ (NSString *)key:(NSString *)key _notBetween:(NSArray *)array{
    if(![array isKindOfClass:[NSArray class]] || array.count != 2) return @"";
    return [NSString stringWithFormat:@"\"%@\" NOT BETWEEN \"%@\" AND \"%@\"", key, array[0], array[1]];
}

+ (NSString *)key:(NSString *)key _in:(id)arrayOrSet{
    if(!([arrayOrSet isKindOfClass:[NSArray class]] || [arrayOrSet isKindOfClass:[NSSet class]])) return @"";
    NSMutableString *inString = [NSMutableString stringWithCapacity:0];
    for (id val in arrayOrSet) {
        [inString appendFormat:@"\"%@\",",val];
    }
    if (inString.length >= 1){
        [inString deleteCharactersInRange:NSMakeRange(inString.length - 1, 1)];
    }
    return [NSString stringWithFormat:@"\"%@\" IN (%@)", key, inString];
}

+ (NSString *)key:(NSString *)key _notIn:(id)arrayOrSet{
    if(!([arrayOrSet isKindOfClass:[NSArray class]] || [arrayOrSet isKindOfClass:[NSSet class]])) return @"";
    NSMutableString *inString = [NSMutableString stringWithCapacity:0];
    for (id val in arrayOrSet) {
        [inString appendFormat:@"\"%@\",",val];
    }
    if (inString.length >= 1){
        [inString deleteCharactersInRange:NSMakeRange(inString.length - 1, 1)];
    }
    return [NSString stringWithFormat:@"\"%@\" NOT IN (%@)", key, inString];
}

+ (NSString *)key:(NSString *)key _like:(id)val{
    return [NSString stringWithFormat:@"\"%@\" LIKE \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _notLike:(id)val{
    return [NSString stringWithFormat:@"\"%@\" NOT LIKE \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _glob:(id)val{
    return [NSString stringWithFormat:@"\"%@\" GLOB \"%@\"", key, val];
}

+ (NSString *)key:(NSString *)key _notGlob:(id)val{
    return [NSString stringWithFormat:@"\"%@\" NOT GLOB \"%@\"", key, val];
}

//MARK: - Order语句
+ (NSString *)orderBy:(id)orderBy{
    if([orderBy isKindOfClass:[NSString class]] && [orderBy length] > 0){
        return [NSString stringWithFormat:@" ORDER BY %@",orderBy];
    }
    else if([orderBy isKindOfClass:[NSArray class]]){
        NSMutableString *orderString = [NSMutableString stringWithCapacity:0];
        for (NSDictionary *dic in orderBy) {
            if(dic.count == 1){
                NSString *key = dic.allKeys.firstObject;
                NSString *order = dic[key];
                if ([order.uppercaseString isEqualToString:kVsOrderAsc] ||
                    [order.uppercaseString isEqualToString:kVsOrderDesc]) {
                    [orderString appendFormat:@"\"%@\" %@,", key, order];
                }
            }
        }
        if(orderString.length > 1){
            [orderString deleteCharactersInRange:NSMakeRange(orderString.length - 1, 1)];
            return [NSString stringWithFormat:@" ORDER BY %@",orderString];
        }
    }
    return @"";
}

//MARK: - Limit语句
+ (NSString *)limit:(NSRange)range{
    return range.length == 0 ? @"" : [NSString stringWithFormat:@" LIMIT %@,%@",@(range.location),@(range.length)];
}

@end

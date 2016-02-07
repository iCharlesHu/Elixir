//
//  ELXObject.m
//  Elixir
//
//  Created by Yizhe Hu on 1/16/16.
//  Copyright © 2016 Yizhe Hu. All rights reserved.
//

#import "sqlite3.h"
#import "ELXObject.h"

@import ObjectiveC.runtime;

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

typedef NS_ENUM(NSUInteger, ELXObjectType) {
    ELXObjectTypeUnknown,
    ELXObjectTypeChar,
    ELXObjectTypeBOOL,
    ELXObjectTypeInt,
    ELXObjectTypeShort,
    ELXObjectTypeLong,
    ELXObjectTypeLongLong,
    ELXObjectTypeUnsignedChar,
    ELXObjectTypeUnsignedInt,
    ELXObjectTypeUnsignedShort,
    ELXObjectTypeUnsignedLong,
    ELXObjectTypeUnsignedLongLong,
    ELXObjectTypeFloat,
    ELXObjectTypeDouble,
    ELXObjectTypeCString,
    ELXObjectTypeObject,
    ELXObjectTypeClass,
    ELXObjectTypeSelector,
    ELXObjectTypeArray,
    ELXObjectTypeStruct,
    ELXObjectTypeUnion,
    ELXObjectTypePtr,
    ELXObjectTypeString,
    ELXObjectTypeDateTime,
};

#if TARGET_OS_IPHONE
static NSString * const __nonnull ELXDefaultDatabaseFolder = @"/base/";
#else
static NSString * const __nonnull ELXDefaultDatabaseFolder = @"/com.iCharlesHu.Elixir/base/";
#endif

static NSString * const __nonnull ELXDefaultDatabaseFile = @"elixir.db";

static NSString * const __nonnull kELXObjectPropertyTypeKey = @"ELXObjectPropertyTypeKey";
static NSString * const __nonnull kELXObjectPropertyCustomSetterKey = @"ELXObjectPropertyCustomSetterKey";
static NSString * const __nonnull kELXObjectPropertyCustomGetterKey = @"ELXObjectPropertyCustomGetterKey";
static NSString * const __nonnull kELXObjectPropertyDynamicKey = @"ELXObjectPropertyDynamicKey";
static NSString * const __nonnull kELXObjectPropertyClassKey = @"ELXObjectPropertyClassKey";
static NSString * const __nonnull kELXObjectSerializationKey = @"ELXObjectSerializationKey";
static NSString * const __nonnull kELXObjectUnsupportedKey = @"ELXObjectUnsupportedKey";

/**
 * Error messages - Property related
 */
static NSString * const __nonnull ELXInvalidPropertyException = @"ELXInvalidPropertyException";
static NSString * const __nonnull ERR_INVALID_GETTER = @"Elixir[ERROR]: object must respond to custome property getter";
static NSString * const __nonnull ERR_INVALID_SETTER = @"Elixir[ERROR]: object must respond to custome property setter";
/**
 * Error messages - Database related
 */
static NSString * const __nonnull ELXFailedSQLiteOperationException = @"ELXFailedSQLiteOperationException";
static NSString * const __nonnull ERR_FAILED_OPEN_DB = @"Elixir[ERROR]: failed to open database file";
static NSString * const __nonnull ERR_FAILED_CREATE_DB = @"Elixir[ERROR]: failed to create database file with error code: %d";
static NSString * const __nonnull ERR_FAILED_PREP_STMT = @"Elixir[ERROR]: failed to prepare SQL statement with error code: %d";
static NSString * const __nonnull ERR_FAILED_INIT_TABLE = @"Elixir[ERROR]: failed to initialize table for class %@";
static NSString * const __nonnull ERR_FAILED_UPDATE_SCHEMA = @"Elixir[ERROR]: failed to update class schema with error %s";
/**
 * Error messages - Insert/Delete
 */
static NSString * const __nonnull ELXFailedOperationException = @"ELXFailedOperationException";
static NSString * const __nonnull ERR_FAILED_INSERT_OBJ = @"Elixir[ERROR]: failed to insert object %@";
static NSString * const __nonnull ERR_FAILED_DELETE_OBJ = @"Elixir[ERROR]: failed to delete object %@";
/**
 * Error messages - Predicate related
 */
static NSString * const __nonnull ELXIllegalPredicateException = @"ELXIllegalPredicateException";
static NSString * const __nonnull ERR_ILL_PREDICATE_TYPE = @"Elixir[ERROR]: illegal predicate type";
static NSString * const __nonnull ERR_UNSUPPORTED_PREDICATE_OPERATOR = @"Elixir[ERROR]: unsupported predicate operator type";
static NSString * const __nonnull ERR_UNSUPPORTED_PREDICATE_MODIFIER = @"Elixir[ERROR]: comparison predicate modifier (ANY, ALL) is not currently supported.";
static NSString * const __nonnull ERR_ILL_COMPARISON_PREDICATE = @"Elixir[ERROR]: invalid predicate, comparison predicate must compair keypath expressions with constant values or other keypath expressions.";
static NSString * const __nonnull ERR_ILL_IN_OPERATOR = @"Elixir[ERROR]: invalid predicate, IN operator must be applied on an array of expressions";
static NSString * const __nonnull ERR_ILL_BETWEEN_OPERATOR = @"Elixir[ERROR]: Invalid predicate, BETWEEN operator must be applied on an array of TWO expressions";
/**
 * Warning messages - Unsupported types
 */
static NSString * const __nonnull WARNING_NOT_NSCODING = @"Elixir[WARNING]: property %@ doesn't conform NSCoding(NSSecureCoding) protocol, skipping...";
static NSString * const __nonnull WARNING_UNSUPPORTED_TYPE = @"Elixir[WARNING]: property %@ has unsupported type, skipping...";

static NSDictionary<NSString *, NSNumber *> * __nonnull ELXObjectPropertyTypeMap;
static NSDictionary<NSNumber *, NSString *> * __nonnull ELXObjectPropertySQLTypeMap;
static NSMutableArray<NSString *> * __nonnull ELXObjectPropertyNameTable;

#pragma mark - ELXQueryBinding
@interface ELXQueryBinding : NSObject
@property (nonatomic, strong) id value;
@property (nonatomic, strong) NSNumber *type;
@end

@implementation ELXQueryBinding
+ (ELXQueryBinding *)bindingWithValue:(id)value type:(NSNumber *)type
{
    ELXQueryBinding *binding = [self new];
    binding.value = value;
    binding.type = type;
    return binding;
}
@end

#pragma mark - ELXObject
@interface ELXObject ()
@property (nonatomic) ELXObjectArchiveOption archiveOption;
@property (nonatomic) NSUInteger elxuid;
@end

@implementation ELXObject
{
    BOOL _inMemoryOnly;
}

static sqlite3 *_database;
static NSMutableArray<ELXObject *> *_mdatabase;
static NSMutableArray<ELXQueryBinding *>  *_globalQueryBindings;
static BOOL _classTableExists = NO;
static BOOL _schemaUpdated = NO;
static NSUInteger _mdatabaseNextID;

#pragma mark - Query Objects
/**
 * Get all objects (both on-disk and in-memory) of this class.
 * If no objects found, an empty array will be returned.
 *
 * @return NSArray<ELXObject *> *: an array of all objects in database
 */
+ (nonnull NSArray<ELXObject *> *)allObjects
{
    [self commonInit];
    NSMutableArray *results = [self queryObject:nil];
    [results addObjectsFromArray:_mdatabase];
    return results;
}

/**
 * Get objects matching the given predicate from both on-disk and in-memory database.
 * Here predicateFormat should be in NSPredicate Predicate Format String Syntax.
 * This method will try to construct a NSPredicate according to predicateFormat then perform the query.
 *
 * @param predicateFormat: the NSPredicate Predicate Format String to construct predicate
 * @return NSArray<ELXObject *> *: an array of objects matching the given predicate
 */
+ (nonnull NSArray<ELXObject *> *)objectsWhere:(NSString *)predicateFormat, ...
{
    va_list args;
    va_start(args, predicateFormat);
    NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateFormat arguments:args];
    va_end(args);
    return [self objectsWithPredicate:predicate];
}

/**
 * Get objects matching the given predicate from both on-disk and in-memory database.
 *
 * @param predicate: the NSPredicate to query
 * @return NSArray<ELXObject *> *: an array of objects matching the given predicate
 */
+ (nonnull NSArray<ELXObject *> *)objectsWithPredicate:(NSPredicate *)predicate
{
    [self commonInit];
    NSMutableArray *results = [self queryObject:predicate];
    [results addObjectsFromArray:[_mdatabase filteredArrayUsingPredicate:predicate]];
    
    return results;
}

#pragma mark - Archive Object
/**
 * Object will be written to on-disk or in-memory database when invoked.
 * This method is automatically invoked at -(void)delloc with ELXObjectArchiveOptionOnObjectDelloc option.
 */
- (void)archiveObject
{
    [self.class commonInit];
    
    if (_inMemoryOnly) {
        // assign next ID
        self.elxuid = _mdatabaseNextID;
        _mdatabaseNextID--;
        [_mdatabase addObject:self];
        return;
    }
    
    // new object have elxuid initialized as NSUIntegerMax
    BOOL updateOnly = (self.elxuid != NSUIntegerMax);
    
    NSMutableString *query1 = [NSMutableString stringWithFormat:@"INSERT INTO '%@' (", NSStringFromClass([self class])];
    NSMutableString *query2 = [NSMutableString stringWithFormat:@") VALUES ("];
    NSMutableString *updateQuery = [NSMutableString stringWithFormat:@"UPDATE %@ SET ", NSStringFromClass([self class])];
    
    // get list of properties and add them to query
    unsigned int pcount;
    objc_property_t *properties = class_copyPropertyList([self class], &pcount);
    unsigned int rcount;
    objc_property_t *rproperties = class_copyPropertyList([ELXObject class], &rcount);
    // special case: directly using ELXObject itself
    if ([self isMemberOfClass:[ELXObject class]]) {
        rcount = 0;
    }
    unsigned int tcount = rcount + pcount;
    for (unsigned int i = 0; i < tcount; i++) {
        objc_property_t property = (i < pcount) ? properties[i] : rproperties[i - pcount];
        NSString *name = [NSString stringWithUTF8String:property_getName(property)];
        NSDictionary *attr = [self.class parsePropertyAttribute:[NSString stringWithUTF8String:property_getAttributes(property)]];
        ELXObjectType type = [(NSNumber *)[attr objectForKey:kELXObjectPropertyTypeKey] unsignedIntegerValue];
        NSString *gettername = (NSString *)[attr objectForKey:kELXObjectPropertyCustomGetterKey];
        BOOL useCustomeGetter = (gettername != nil);
        SEL getter = (gettername == nil) ? NSSelectorFromString(name) : NSSelectorFromString(gettername);
        
        // special cases
        if ([name isEqualToString:NSStringFromSelector(@selector(elxuid))]) {
            // we ask SQLite to autoincrement this value instead of explicitly setting it
            continue;
        }
        
        // get values according to type
        if (type == ELXObjectTypeUnsignedChar) {
            // unsigned char is stored as c string
            unsigned char val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                unsigned char (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] unsignedCharValue];
            }
            
            NSString *value = [NSString stringWithFormat:@"%c", val];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeShort || type == ELXObjectTypeInt) {
            int val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                int (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] intValue];
            }
            
            NSNumber *value = [NSNumber numberWithInt:val];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeLong || type == ELXObjectTypeLongLong) {
            long long val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                long long (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] longLongValue];
            }
            
            NSNumber *value = [NSNumber numberWithLongLong:val];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeChar) {
            char val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                char (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] charValue];
            }
            
            NSString *value = [NSString stringWithFormat:@"%c", val];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeBOOL) {
            // under 64bit iOS environment, BOOL will be encoded as c bool type
            // in this case, use interger 1 and 0 as table value
            BOOL val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                BOOL (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] boolValue];
            }
            
            NSNumber *value = (val) ? [NSNumber numberWithInt:1] : [NSNumber numberWithInt:0];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeUnsignedShort || type == ELXObjectTypeUnsignedInt) {
            unsigned int val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                unsigned int (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] unsignedIntValue];
            }
            
            NSNumber *value = [NSNumber numberWithUnsignedInt:val];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeUnsignedLong || type == ELXObjectTypeUnsignedLongLong) {
            unsigned long long val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                unsigned long long (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] unsignedLongLongValue];
            }
            
            NSNumber *value = [NSNumber numberWithUnsignedLongLong:val];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeFloat || type == ELXObjectTypeDouble) {
            double val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                double (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] doubleValue];
            }
            
            NSNumber *value = [NSNumber numberWithDouble:val];
            [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeCString) {
            // for c strings we can only use getter since this type
            // isn't key value coding compliant
            const char *val = NULL;
            NSString *value = nil;
            
            if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
            IMP imp = [self methodForSelector:getter];
            const char *(*func)(id, SEL) = (void *)imp;
            val = func(self, getter);
            
            if (val) value = [NSString stringWithUTF8String:val];
            
            if (value) {
                value = (value == nil) ? [NSString stringWithUTF8String:val] : value;
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            } else {
                // NULL C string
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNull null] type:@(type)]];
            }
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeObject) {
            // objects are seralized to blob
            id val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                id (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [self valueForKey:name];
            }
            
            if (val) {
                // objects properties must conform NSCoding protocol to be seralized
                Protocol *nscoding = objc_getProtocol(@"NSCoding".UTF8String);
                Class cls = [val class];
                BOOL conformsProtocol = class_conformsToProtocol(cls, nscoding);
                // here have to recursively check super classes
                while (!conformsProtocol && ![NSStringFromClass(cls) isEqualToString:@"NSObject"]) {
                    cls = class_getSuperclass(cls);
                    conformsProtocol = class_conformsToProtocol(cls, nscoding);
                }
                
                if (!conformsProtocol) {
                    NSLog(WARNING_NOT_NSCODING, name);
                    continue;
                }
                NSMutableData *value = [NSMutableData data];
                NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:value];
                [archiver encodeObject:val forKey:kELXObjectSerializationKey];
                [archiver finishEncoding];
                
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            } else {
                // nil object
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNull null] type:@(type)]];
            }
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeClass) {
            Class val = NULL;
            NSValue *value;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                Class (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [self valueForKey:name];
            }
            
            if (!val && value) [value getValue:&val];
            NSString *valname = NSStringFromClass(val);
            
            if (valname) {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:NSStringFromClass(val) type:@(type)]];
            } else {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNull null] type:@(type)]];
            }
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeSelector) {
            // selector type is NOT key value coding compliant
            // use getter only
            SEL val = NULL;
            NSValue *value;
            
            if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
            IMP imp = [self methodForSelector:getter];
            SEL (*func)(id, SEL) = (void *)imp;
            val = func(self, getter);
            
            value = (val != NULL) ? [NSValue valueWithBytes:&val objCType:@encode(SEL)] : value;
            
            if (value) {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            } else {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNull null] type:@(type)]];
            }
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeArray) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        } else if (type == ELXObjectTypeStruct) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        } else if (type == ELXObjectTypeUnion) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        } else if (type == ELXObjectTypePtr) {
            // pointer type is not key value coding compliant
            // use getter only
            void *val = NULL;
            NSValue *value;
            
            if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
            IMP imp = [self methodForSelector:getter];
            void *(*func)(id, SEL) = (void *)imp;
            val = func(self, getter);
            
            value = (val != NULL) ? [NSValue valueWithBytes:&val objCType:@encode(void *)] : value;
            
            if (value) {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            } else {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNull null] type:@(type)]];
            }
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else if (type == ELXObjectTypeString) {
            NSString *value = nil;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                NSString *(*func)(id, SEL) = (void *)imp;
                value = func(self, getter);
            } else {
                value = (NSString *)[self valueForKey:name];
            }
            
            if (value) {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            } else {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNull null] type:@(type)]];
            }
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
            
        } else if (type == ELXObjectTypeDateTime) {
            NSDate *val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                NSDate *(*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = (NSDate *)[self valueForKey:name];
            }
            
            if (val) {
                NSNumber *value = [NSNumber numberWithDouble:[val timeIntervalSinceReferenceDate]];
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:value type:@(type)]];
            } else {
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNull null] type:@(type)]];
            }
            
            // append query
            [query1 appendFormat:@"\"%@\"", name];
            [query2 appendString:@"?"];
            [updateQuery appendFormat:@"%@ = ?", name];
            // append comma
            if (i < tcount - 2) {
                [query1 appendString:@", "];
                [query2 appendString:@", "];
                [updateQuery appendString:@", "];
            }
        } else {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        }
    }
    [query2 appendString:@")"];
    free(properties);
    free(rproperties);
    // complete the query
    NSString *query;
    if (updateOnly) {
        query = [NSString stringWithFormat:@"%@ WHERE %@ = ?", updateQuery, NSStringFromSelector(@selector(elxuid))];
        [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSNumber numberWithUnsignedInteger:self.elxuid] type:@(ELXObjectTypeUnsignedLong)]];
    } else {
        query = [NSString stringWithFormat:@"%@%@", query1, query2];
    }
    
    if (![self.class openDatabase]) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_OPEN_DB];
    }
    
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_database, query.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_PREP_STMT, rc];
    }
    // bind data
    [self.class bindStatment:&stmt withBindings:_globalQueryBindings];
    
    // execute the statement
    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        [NSException raise:ELXFailedOperationException format:ERR_FAILED_INSERT_OBJ, self];
    }
    
    // retrieve elxid
    if (!updateOnly)
        self.elxuid = (NSUInteger)sqlite3_last_insert_rowid(_database);
    
    sqlite3_finalize(stmt);
    [self.class closeDatabase];
}

#pragma mark - Delete Object
/**
 * Remove the object from on-disk or in-memory database
 * NOTE: if an object is saved both on-disk and in-memory, only the version it's currently in will be deleted.
 */
- (void)deleteObject
{
    if (_inMemoryOnly) {
        [_mdatabase removeObject:self];
        return;
    }
    
    if (self.elxuid == NSUIntegerMax) {
        // the object hasn't been archived yet
        return;
    }
    
    NSString *query = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = ?", NSStringFromClass([self class]), NSStringFromSelector(@selector(elxuid))];
    // bind self id
    if (![self.class openDatabase]) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_OPEN_DB];
    }
    sqlite3_stmt *stmt = nil;
    int rc = sqlite3_prepare_v2(_database, query.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_PREP_STMT, rc];
    }
    
    sqlite3_bind_int64(stmt, 1, self.elxuid);
    // execute the statement
    rc = sqlite3_step(stmt);
    
    if (rc != SQLITE_DONE) {
        [NSException raise:ELXFailedOperationException format:ERR_FAILED_DELETE_OBJ, self];
    }
    // clean up
    sqlite3_finalize(stmt);
    [self.class closeDatabase];
}

#pragma mark - In Memory Only Behavior
/**
 * If set to YES, the current object will be in-memory-only.
 * This means all the changes will only be buffered in memory, but you can still query the object.
 * NOTE: if you set a object to be in-memory-only after archiving it, the further changes will
 * be cached in memory only.
 *
 * @param inMemoryOnly: whether this object should be in-memory-only
 */
- (void)setInMemoryOnly:(BOOL)inMemoryOnly
{
    _inMemoryOnly = inMemoryOnly;
}

#pragma mark - Configuration
/**
 * Override this method to change the path to the on-disk database file.
 * WARNING: Do NOT change this path after you have already saved items to database
 * because the data base will NOT be relocated
 *
 * @return NSSting *: the string path to the on-disk database file
 */
#if TARGET_OS_IPHONE
+ (nonnull NSString *)databasePath
{
    NSString *basePath = (NSString *)[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [basePath stringByAppendingString:ELXDefaultDatabaseFolder];
}
#else
+ (nonnull NSString *)databasePath
{
    NSString *basePath = (NSString *)[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [basePath stringByAppendingString:ELXDefaultDatabaseFolder];
}
#endif

/**
 * Append the name of the database file to the end of the database path.
 *
 * @return NSString *: the entire path to the database file, including the file name
 */
+ (nonnull NSString *)databaseFile
{
    return [[self databasePath] stringByAppendingString:ELXDefaultDatabaseFile];
}

/**
 * Set the archive option to the current object. See ELXObjectArchiveOption ENUM for the options.
 * The default value is ELXObjectArchiveOptionManual.
 *
 * @param ELXObjectArchiveOption: the new archive option to be set
 */
- (void)setArchiveOption:(ELXObjectArchiveOption)archiveOption
{
    _archiveOption = archiveOption;
}

#pragma mark - Private Utils
/**
 * Common initialize code for the class
 */
+ (void)commonInit
{
    [self createDatabaseFile];
    
    if (!_mdatabase) {
        _mdatabase = [NSMutableArray new];
    }
    
    if (!_globalQueryBindings) {
        _globalQueryBindings = [NSMutableArray new];
    }
    
    _mdatabaseNextID = NSUIntegerMax - 1;
    
    if (!ELXObjectPropertyNameTable) {
        ELXObjectPropertyNameTable = [NSMutableArray new];
    }
    
    if (!ELXObjectPropertyTypeMap) {
        ELXObjectPropertyTypeMap = @{@"c": @(ELXObjectTypeChar), @"i": @(ELXObjectTypeInt), @"s": @(ELXObjectTypeShort),
                                     @"l": @(ELXObjectTypeLong), @"q": @(ELXObjectTypeLongLong), @"C": @(ELXObjectTypeUnsignedChar),
                                     @"I": @(ELXObjectTypeUnsignedInt), @"S": @(ELXObjectTypeUnsignedShort), @"L": @(ELXObjectTypeUnsignedLong),
                                     @"Q": @(ELXObjectTypeUnsignedLongLong), @"f": @(ELXObjectTypeFloat), @"d": @(ELXObjectTypeDouble),
                                     @"*": @(ELXObjectTypeCString), @"@": @(ELXObjectTypeObject), @"#": @(ELXObjectTypeClass),
                                     @":": @(ELXObjectTypeSelector), @"[": @(ELXObjectTypeArray), @"{": @(ELXObjectTypeStruct),
                                     @"(": @(ELXObjectTypeUnion), @"^": @(ELXObjectTypePtr), @"NSString": @(ELXObjectTypeString),
                                     @"NSDate": @(ELXObjectTypeDateTime), @"?": @(ELXObjectTypeUnknown), @"B": @(ELXObjectTypeBOOL)};
    }
    
    if (!ELXObjectPropertySQLTypeMap) {
        ELXObjectPropertySQLTypeMap = @{@(ELXObjectTypeChar): @"TEXT", @(ELXObjectTypeInt): @"INTEGER", @(ELXObjectTypeShort): @"INTEGER",
                                        @(ELXObjectTypeLong): @"INTEGER", @(ELXObjectTypeLongLong): @"INTEGER", @(ELXObjectTypeUnsignedChar): @"TEXT",
                                        @(ELXObjectTypeUnsignedInt): @"INTEGER", @(ELXObjectTypeUnsignedShort): @"INTEGER", @(ELXObjectTypeUnsignedLong): @"INTEGER",
                                        @(ELXObjectTypeUnsignedLongLong): @"INTEGER", @(ELXObjectTypeFloat): @"REAL", @(ELXObjectTypeDouble): @"REAL",
                                        @(ELXObjectTypeCString): @"TEXT", @(ELXObjectTypeObject): @"BLOB", @(ELXObjectTypeClass): @"TEXT",
                                        @(ELXObjectTypeSelector): @"BLOB", @(ELXObjectTypeArray): kELXObjectUnsupportedKey, @(ELXObjectTypeStruct): kELXObjectUnsupportedKey,
                                        @(ELXObjectTypeUnion): kELXObjectUnsupportedKey, @(ELXObjectTypePtr): @"BLOB", @(ELXObjectTypeString): @"TEXT",
                                        @(ELXObjectTypeDateTime): @"REAL", @(ELXObjectTypeUnknown): kELXObjectUnsupportedKey, @(ELXObjectTypeBOOL): @"INTEGER"};
    }
    
    if (!_classTableExists) {
        _classTableExists = [self tableExists];
        if (!_classTableExists) [self createTable];
        _classTableExists = YES;
    }
    
    if (!_schemaUpdated) {
        [self updateSchema];
        _schemaUpdated = YES;
    }
}

/**
 * Query object according to the predicate
 *
 * @param predicate: predicate to query. Pass in nil predicate to query all objects
 * @return NSMutableArray<ELXObject *> *: an array of queryed objects
 */
+ (nonnull NSMutableArray<ELXObject *> *)queryObject:(nullable NSPredicate *)predicate
{
    NSMutableArray<ELXObject *> *results = [NSMutableArray new];
    // prepare the query
    NSMutableString *query = [NSMutableString stringWithString:@"SELECT *"];
    // determine types and names
    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *propertydata = [NSMutableDictionary new];
    
    unsigned int pcount;
    objc_property_t *properties = class_copyPropertyList([self class], &pcount);
    unsigned int rcount;
    objc_property_t *rproperties = class_copyPropertyList([ELXObject class], &rcount);
    // special case: directly using ELXObject itself
    if ([NSStringFromClass(self) isEqualToString:NSStringFromClass([ELXObject class])]) {
        rcount = 0;
    }
    unsigned int tcount = rcount + pcount;
    for (unsigned int i = 0; i < tcount; i++) {
        objc_property_t property = (i < pcount) ? properties[i] : rproperties[i - pcount];
        NSString *name = [NSString stringWithUTF8String:property_getName(property)];
        NSString *attr = [NSString stringWithUTF8String:property_getAttributes(property)];
        [propertydata setObject:[self parsePropertyAttribute:attr] forKey:name];
    }
    // cleanup
    free(properties);
    free(rproperties);
    // finish the query
    [query appendString:[NSString stringWithFormat:@" FROM %@", NSStringFromClass([self class])]];
    // append where clause if there is one
    if (predicate) {
        NSString *condition = [self parsePredicate:predicate];
        if (condition.length)
            [query appendFormat:@" WHERE %@", condition];
    }
    
    if (![self openDatabase]) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_OPEN_DB];
    }
    
    sqlite3_stmt *stmt = nil;
    int rc = sqlite3_prepare_v2(_database, query.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_PREP_STMT, rc];
    }
    // bind data if any
    if (_globalQueryBindings.count != 0) {
        [self bindStatment:&stmt withBindings:_globalQueryBindings];
    }
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        id obj = [self new];
        // get number of columns and loop through
        int colcount = sqlite3_column_count(stmt);
        for (int i = 0; i < colcount; i++) {
            NSString *colname = [NSString stringWithUTF8String:sqlite3_column_name(stmt, i)];
            NSDictionary<NSString *, id> *attribute = [propertydata objectForKey:colname];
            ELXObjectType type = [(NSNumber *)[attribute objectForKey:kELXObjectPropertyTypeKey] unsignedIntegerValue];
            NSString *settername = (NSString *)[attribute objectForKey:kELXObjectPropertyCustomSetterKey];
            BOOL useCustomSetter = (settername != nil);
            if (!settername) {
                // use the default setter
                settername = [NSString stringWithFormat:@"set%@:", [self capitalizeFirstLetterString:colname]];
            }
            SEL setter = NSSelectorFromString(settername);
            
            // set property values according to type
            if (type == ELXObjectTypeUnsignedChar) {
                // unsigned char is stored as c string
                const unsigned char *ret = sqlite3_column_text(stmt, i);
                if (ret == NULL) continue;
                unsigned char val = ret[0];
                
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, unsigned char) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    // else directly use key-value coding
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeBOOL) {
                // under 64bit iOS environment, BOOL will actually be encoded as C bool.
                // in this case, use integer 1 and 0 instead
                int ret = sqlite3_column_int(stmt, i);
                BOOL val = (ret == 1) ? YES : NO;
                
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, BOOL) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    // else directly use key-value coding
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeShort || type == ELXObjectTypeInt) {
                // assume automatic down-size casting
                int val = sqlite3_column_int(stmt, i);
                
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, int) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeLong || type == ELXObjectTypeLongLong) {
                long long val = sqlite3_column_int64(stmt, i);
                
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, long long) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeChar) {
                // unsigned char is stored as c string
                const char *ret = (const char *)sqlite3_column_text(stmt, i);
                if (ret == NULL) continue;
                char val = (char)ret[0];
                
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, char) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    // else directly use key-value coding
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeUnsignedShort || type == ELXObjectTypeUnsignedInt) {
                unsigned int val = (unsigned int)sqlite3_column_int(stmt, i);
                
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, unsigned int) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeUnsignedLong || type == ELXObjectTypeUnsignedLongLong) {
                unsigned long long val = (unsigned long long)sqlite3_column_int64(stmt, i);
                
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, unsigned long long) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeFloat || type == ELXObjectTypeDouble) {
                double val = sqlite3_column_double(stmt, i);
                
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, double) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    [obj setValue:@(val) forKey:colname];
                }
            } else if (type == ELXObjectTypeCString) {
                const unsigned char *buf = sqlite3_column_text(stmt, i);
                if (buf == NULL) continue;
                // we need to copy the memory since it's pointer type
                size_t len = strlen((const char *)buf) + 1;
                unsigned char *val = malloc(sizeof(const unsigned char) * len);
                memcpy((char *)val, buf, len * sizeof(const unsigned char));
                // c string type is not key value coding complaint, thus
                // directly use setter
                if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                IMP imp = [obj methodForSelector:setter];
                void (*func)(id, SEL, const unsigned char *) = (void *)imp;
                func(obj, setter, val);
            } else if (type == ELXObjectTypeObject) {
                // objects are seralized to blob, here we need to deserlize them first
                const void *blob = sqlite3_column_blob(stmt, i);
                if (blob == NULL) continue;
                int len = sqlite3_column_bytes(stmt, i);
                NSData *buffer = [NSData dataWithBytes:blob length:len];
                
                NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:buffer];
                id val = [unarchiver decodeObjectForKey:kELXObjectSerializationKey];
                [unarchiver finishDecoding];
                
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, id) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    [obj setValue:val forKey:colname];
                }
            } else if (type == ELXObjectTypeClass) {
                const char *classname = (const char *)sqlite3_column_text(stmt, i);
                if (classname == NULL) continue;
                Class val = objc_getClass(classname);
                
                // Class type is not key value coding complaint, thus
                // use setter directly
                if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                IMP imp = [obj methodForSelector:setter];
                void (*func)(id, SEL, Class) = (void *)imp;
                func(obj, setter, val);
            } else if (type == ELXObjectTypeSelector) {
                const void *blob = sqlite3_column_blob(stmt, i);
                if (blob == NULL) continue;
                SEL val = *((SEL *)blob);
                
                // SEL type is not key value coding complaint, thus
                // use setter directly
                if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                IMP imp = [obj methodForSelector:setter];
                void (*func)(id, SEL, SEL) = (void *)imp;
                func(obj, setter, val);
            } else if (type == ELXObjectTypeArray) {
                NSLog(WARNING_UNSUPPORTED_TYPE, colname);
            } else if (type == ELXObjectTypeStruct) {
                NSLog(WARNING_UNSUPPORTED_TYPE, colname);
            } else if (type == ELXObjectTypeUnion) {
                NSLog(WARNING_UNSUPPORTED_TYPE, colname);
            } else if (type == ELXObjectTypePtr) {
                NSLog(WARNING_UNSUPPORTED_TYPE, colname);
            } else if (type == ELXObjectTypeString) {
                const char *buffer = (const char *)sqlite3_column_text(stmt, i);
                if (buffer == NULL) continue;
                NSString *val = [NSString stringWithUTF8String:buffer];
                
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, NSString *) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    // else directly use key-value coding
                    [obj setValue:val forKey:colname];
                }
            } else if (type == ELXObjectTypeDateTime) {
                double inteval = sqlite3_column_double(stmt, i);
                NSDate *val = [NSDate dateWithTimeIntervalSinceReferenceDate:inteval];
                
                if (useCustomSetter) {
                    if (![obj respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [obj methodForSelector:setter];
                    void (*func)(id, SEL, NSDate *) = (void *)imp;
                    func(obj, setter, val);
                } else {
                    [obj setValue:val forKey:colname];
                }
            } else {
                NSLog(WARNING_UNSUPPORTED_TYPE, colname);
            }
        }
        
        [results addObject:obj];
    }
    
    // clean up
    sqlite3_finalize(stmt);
    // close the connection
    [self closeDatabase];
    
    
    return results;
}

/**
 * Parse the predicate to the valid SQL 'WHERE' clause
 *
 * @param predicate: the predicate to be parsed
 * @return NSSting *: the SQL 'WHERE' clause representation of the predicate
 */
+ (nonnull NSString *)parsePredicate:(nonnull NSPredicate *)predicate
{
    NSMutableString *clause = [NSMutableString new];
    
    if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        // compound predicate, group things together
        NSCompoundPredicate *compound = (NSCompoundPredicate *)predicate;
        if (compound.compoundPredicateType == NSAndPredicateType) {
            for (int i = 0; i < compound.subpredicates.count; i++) {
                NSPredicate *subpredicate = (NSPredicate *)compound.subpredicates[i];
                NSString *subclause = [self parsePredicate:subpredicate];
                [clause appendFormat:@"(%@)", subclause];
                
                if (i < (compound.subpredicates.count - 1)) [clause appendString:@" AND "];
            }
        } else if (compound.compoundPredicateType == NSOrPredicateType) {
            for (int i = 0; i < compound.subpredicates.count; i++) {
                NSPredicate *subpredicate = (NSPredicate *)compound.subpredicates[i];
                NSString *subclause = [self parsePredicate:subpredicate];
                [clause appendFormat:@"(%@)", subclause];
                
                if (i < (compound.subpredicates.count - 1)) [clause appendString:@" OR "];
            }
        } else if (compound.compoundPredicateType == NSNotPredicateType) {
            NSPredicate *subpredicate = (NSPredicate *)compound.subpredicates[0];
            NSString *subclause = [self parsePredicate:subpredicate];
            [clause appendFormat:@"NOT %@", subclause];
        } else {
            [NSException raise:ELXIllegalPredicateException format:ERR_ILL_PREDICATE_TYPE];
        }
    } else if ([predicate isKindOfClass:[NSComparisonPredicate class]]) {
        NSComparisonPredicate *comparison = (NSComparisonPredicate *)predicate;
        if (comparison.comparisonPredicateModifier != NSDirectPredicateModifier) {
            [NSException raise:ELXIllegalPredicateException format:ERR_UNSUPPORTED_PREDICATE_MODIFIER];
        }
        
        NSExpressionType lhsType = comparison.leftExpression.expressionType;
        NSExpressionType rhsType = comparison.rightExpression.expressionType;
        NSPredicateOperatorType operatorType = comparison.predicateOperatorType;
        BOOL typecheck = ((lhsType == NSKeyPathExpressionType || lhsType == NSConstantValueExpressionType) &&
                          (rhsType == NSKeyPathExpressionType || rhsType == NSConstantValueExpressionType));
        
        if (!typecheck) {
            [NSException raise:ELXIllegalPredicateException format:ERR_ILL_COMPARISON_PREDICATE];
        }
        
        NSString *lhsclause = [self parseExpression:comparison.leftExpression forOperatorType:operatorType isRHSExpression:NO];
        NSString *rhsclause = [self parseExpression:comparison.rightExpression forOperatorType:operatorType isRHSExpression:YES];
        
        if (operatorType == NSLessThanPredicateOperatorType) {
            [clause appendFormat:@"%@ < %@", lhsclause, rhsclause];
        } else if (operatorType == NSLessThanOrEqualToPredicateOperatorType) {
            [clause appendFormat:@"%@ <= %@", lhsclause, rhsclause];
        } else if (operatorType == NSGreaterThanPredicateOperatorType) {
            [clause appendFormat:@"%@ > %@", lhsclause, rhsclause];
        } else if (operatorType == NSGreaterThanOrEqualToPredicateOperatorType) {
            [clause appendFormat:@"%@ >= %@", lhsclause, rhsclause];
        } else if (operatorType == NSEqualToPredicateOperatorType) {
            [clause appendFormat:@"%@ = %@", lhsclause, rhsclause];
        } else if (operatorType == NSNotEqualToPredicateOperatorType) {
            [clause appendFormat:@"NOT %@ = %@", lhsclause, rhsclause];
        } else if (operatorType == NSLikePredicateOperatorType) {
            [clause appendFormat:@"%@ LIKE '%@'", lhsclause, rhsclause];
        } else if (operatorType == NSBeginsWithPredicateOperatorType) {
            [clause appendFormat:@"%@ LIKE '%@%%'", lhsclause, rhsclause];
        } else if (operatorType == NSEndsWithPredicateOperatorType) {
            [clause appendFormat:@"%@ LIKE '%%%@'", lhsclause, rhsclause];
        } else if (operatorType == NSInPredicateOperatorType) {
            [clause appendFormat:@"%@ IN %@", lhsclause, rhsclause];
        } else if (operatorType == NSBetweenPredicateOperatorType) {
            [clause appendFormat:@"%@ BETWEEN %@", lhsclause, rhsclause];
        } else if (operatorType == NSContainsPredicateOperatorType) {
            [clause appendFormat:@"%@ LIKE '%%%@%%'", lhsclause, rhsclause];
        } else {
            [NSException raise:ELXIllegalPredicateException format:ERR_UNSUPPORTED_PREDICATE_OPERATOR];
        }
    } else {
        [NSException raise:ELXIllegalPredicateException format:ERR_ILL_PREDICATE_TYPE];
    }
    
    return clause;
}

/**
 * Parse a expression from the predicate to valid SQL 'WHERE' clause component.
 *
 * @param: expression: the expression to be parsed
 * @param: operatorType: the operator type associated with this expression
 * @param: isrhs: whether this expression is at the right hand side of the predicate
 * @return: NSString *: the SQL 'WHERE' clause representation of the expression
 */
+ (nonnull NSString *)parseExpression:(nonnull NSExpression *)expression forOperatorType:(NSPredicateOperatorType)operatorType isRHSExpression:(BOOL)isrhs
{
    NSMutableString *result = [NSMutableString new];
    NSExpressionType type = expression.expressionType;
    BOOL noquote = (operatorType == NSLikePredicateOperatorType || operatorType == NSBeginsWithPredicateOperatorType ||
                    operatorType == NSEndsWithPredicateOperatorType || operatorType == NSContainsPredicateOperatorType);
    
    if (type == NSConstantValueExpressionType) {
        if (isrhs && operatorType == NSInPredicateOperatorType) {
            // for IN operator, the constant value will be an array of expressions
            if (![expression.constantValue isKindOfClass:[NSArray class]]) {
                [NSException raise:ELXIllegalPredicateException format:ERR_ILL_IN_OPERATOR];
            }
            
            [result appendString:@"("];
            NSArray *expressions = (NSArray *)expression.constantValue;
            for (int i = 0; i < expressions.count; i++) {
                NSString *clause = ([expressions[i] isKindOfClass:[NSExpression class]]) ?
                        [self parseExpression:expressions[i] forOperatorType:operatorType isRHSExpression:isrhs] :
                        [expressions[i] description];
                [result appendString: clause];
                if (i < expressions.count - 1) [result appendString:@", "];
            }
            [result appendString:@")"];
        } else if (isrhs && operatorType == NSBetweenPredicateOperatorType) {
            // for BETWEEN operator, the constant value must be an array of TWO expressions
            if (![expression.constantValue isKindOfClass:[NSArray class]]) {
                [NSException raise:ELXIllegalPredicateException format:ERR_ILL_BETWEEN_OPERATOR];
            }
            NSArray *expressions = (NSArray *)expression.constantValue;
            if (expressions.count != 2) {
                [NSException raise:ELXIllegalPredicateException format:ERR_ILL_BETWEEN_OPERATOR];
            }
            NSString *leftclause = ([expressions[0] isKindOfClass:[NSExpression class]]) ?
                    [self parseExpression:expressions[0] forOperatorType:operatorType isRHSExpression:isrhs] :
                    [expressions[0] description];
            NSString *rightclause = ([expressions[1] isKindOfClass:[NSExpression class]]) ?
                    [self parseExpression:expressions[1] forOperatorType:operatorType isRHSExpression:isrhs] :
                    [expressions[1] description];
            [result appendFormat:@"%@ AND %@", leftclause, rightclause];
        } else {
            // for other operator types, constant value are mostly NSNumbers, we can simply use
            // description to get its string representation
            
            // here special case for BOOL: we need to test whether BOOL is actually bool or signed char
            // if BOOL is typedefed from char, we need to leave the char value as it is so it can be query-ed.
            Class cfboolean = objc_lookUpClass("__NSCFBoolean");
            BOOL charencoding = (strcmp(@encode(BOOL), @encode(char)) == 0);
            if ([expression.constantValue isKindOfClass:cfboolean] && charencoding) {
                // special case for BOOL: bind plain char text
                BOOL value = [(NSNumber *)expression.constantValue boolValue];
                [result appendString:@"?"];
                [_globalQueryBindings addObject:[ELXQueryBinding bindingWithValue:[NSString stringWithFormat:@"%c", (char)value] type:@(ELXObjectTypeChar)]];
            } else {
                // we also need to check whether constantValue is type String
                // because we need to add quotation around strings, but not
                // around column names
                if ([expression.constantValue isKindOfClass:[NSString class]] && ![ELXObjectPropertyNameTable containsObject:[expression.constantValue description]] &&
                    !noquote) {
                    // string type but not column name, add quotation
                    [result appendFormat:@"'%@'", expression.constantValue];
                } else {
                    [result appendString:[expression.constantValue description]];
                }
            }
        }
    } else if (type == NSKeyPathExpressionType) {
        // if it's not a column name, don't add quotation
        if ([ELXObjectPropertyNameTable containsObject:expression.keyPath] || noquote) {
            [result appendFormat:@"%@", expression.keyPath];
        } else {
            [result appendFormat:@"'%@'", expression.keyPath];
        }
    } else {
        [NSException raise:ELXIllegalPredicateException format:ERR_ILL_COMPARISON_PREDICATE];
    }
    
    return result;
}

/**
 * Create a table for the current class
 */
+ (void)createTable
{
    NSMutableString *query = [NSMutableString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (", NSStringFromClass([self class])];

    // get the list of properties
    unsigned int pcount;
    objc_property_t *properties = class_copyPropertyList([self class], &pcount);
    // we also need the root properties from ELXObject
    unsigned int rcount;
    objc_property_t *rproperties = class_copyPropertyList([ELXObject class], &rcount);
    // special case: directly using ELXObject itself
    if ([NSStringFromClass(self) isEqualToString:NSStringFromClass([ELXObject class])]) {
        rcount = 0;
    }
    unsigned int tcount = pcount + rcount;
    for (unsigned int i = 0; i < tcount; i++) {
        objc_property_t property = (i < pcount) ? properties[i] : rproperties[i - pcount];
        NSString *name = [NSString stringWithUTF8String:property_getName(property)];
        NSDictionary *attr = [self parsePropertyAttribute:[NSString stringWithUTF8String:property_getAttributes(property)]];
        NSNumber *type = (NSNumber *)[attr objectForKey:kELXObjectPropertyTypeKey];
        NSString *sqltype = [ELXObjectPropertySQLTypeMap objectForKey:type];
        
        // there might be unsupported types
        if ([sqltype isEqualToString:kELXObjectUnsupportedKey]) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
            continue;
        }
        
        // append type
        [query appendFormat:@"%@ %@", name, sqltype];
        // we use elxuid as primary key
        if ([name isEqualToString:NSStringFromSelector(@selector(elxuid))]) {
            [query appendString:@" PRIMARY KEY NOT NULL"];
        }
        
        // append comma
        if (i < tcount - 1) [query appendString:@", "];
    }
    [query appendString:@")"];
    free(properties);
    free(rproperties);
    
    if (![self openDatabase]) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_OPEN_DB];
    }
    
    char *err;
    int rc = sqlite3_exec(_database, query.UTF8String, NULL, NULL, &err);
    
    if (rc != SQLITE_OK) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_INIT_TABLE, NSStringFromClass([self class])];
    }
    
    [self closeDatabase];
}

/**
 * Check whether a table for the current class already exists
 */
+ (BOOL)tableExists
{
    BOOL exists = NO;
    NSString *query = [NSString stringWithFormat:@"SELECT 'name' FROM sqlite_master WHERE type='table' AND name='%@'", NSStringFromClass([self class])];
    
    if (![self openDatabase]) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_OPEN_DB];
    }
    sqlite3_stmt *stmt = nil;
    int rc = sqlite3_prepare_v2(_database, query.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_PREP_STMT, rc];
    }
    
    if (sqlite3_step(stmt) == SQLITE_ROW) exists = YES;
    sqlite3_finalize(stmt);
    [self closeDatabase];
    
    return exists;
}

/**
 * Update the class table schema (delete/add columns) according to the current property list
 */
+ (void)updateSchema
{
    NSMutableDictionary<NSString *, NSString *> *insert = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *delete = [NSMutableDictionary new];
    // get current list of properties
    unsigned int pcount;
    objc_property_t *properties = class_copyPropertyList([self class], &pcount);
    unsigned int rcount;
    objc_property_t *rproperties = class_copyPropertyList([ELXObject class], &rcount);
    // special case: directly using ELXObject itself
    if ([NSStringFromClass(self) isEqualToString:NSStringFromClass([ELXObject class])]) {
        rcount = 0;
    }
    unsigned int tcount = rcount + pcount;
    for (unsigned int i = 0; i < tcount; i++) {
        objc_property_t property = (i < pcount) ? properties[i] : rproperties[i - pcount];
        NSString *name = [NSString stringWithUTF8String:property_getName(property)];
        NSDictionary *attr = [self parsePropertyAttribute:[NSString stringWithUTF8String:property_getAttributes(property)]];
        NSNumber *type = (NSNumber *)[attr objectForKey:kELXObjectPropertyTypeKey];
        NSString *sqltype = [ELXObjectPropertySQLTypeMap objectForKey:type];
        [insert setObject:sqltype forKey:name];
        // since update schema will be run everytime, we use this oppotunity to fill in the ELXObjectPropertyNameTable
        [ELXObjectPropertyNameTable addObject:name];
    }
    // clean up
    free(properties);
    // check against current schema
    if (![self openDatabase]) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_OPEN_DB];
    }
    NSString *query = [NSString stringWithFormat:@"PRAGMA table_info('%@')", NSStringFromClass([self class])];
    sqlite3_stmt *stmt = nil;
    int rc = sqlite3_prepare_v2(_database, query.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_PREP_STMT, rc];
    }
    
    // step through columns
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSString *colname = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        NSString *coltype = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        // check if this is new
        if ([insert objectForKey:colname]) {
            if ([(NSString *)[insert objectForKey:colname] isEqualToString:coltype]) {
                [insert removeObjectForKey:colname];
            } else {
                // need to change the type, thus remove first then insert
                [delete setObject:coltype forKey:colname];
            }
        } else {
            // need to delete it
            [delete setObject:coltype forKey:colname];
        }
    }
    
    // now need to insert/delete column if necessary
    // delete first
    if (delete.count != 0) {
        // need to re-compile the statement
        sqlite3_prepare_v2(_database, query.UTF8String, -1, &stmt, NULL);
        // need to delete, so create a new table and copy over
        // determine name and types
        NSMutableArray *names = [NSMutableArray new];
        NSMutableArray *types = [NSMutableArray new];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSString *name = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
            NSString *type = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
            
            if (![delete objectForKey:name]) {
                [names addObject:name];
                [types addObject:type];
            }
        }
        // create temp table statement
        NSMutableString *qcrtb = [NSMutableString stringWithFormat:@"CREATE TEMPORARY TABLE %@_backup (", NSStringFromClass([self class])];
        NSMutableString *qbcp = [NSMutableString stringWithFormat:@"INSERT INTO %@_backup SELECT ", NSStringFromClass([self class])];
        NSString *qdropo = [NSString stringWithFormat:@"DROP TABLE %@", NSStringFromClass([self class])];
        NSMutableString *qcrt = [NSMutableString stringWithFormat:@"CREATE TABLE %@ (", NSStringFromClass([self class])];
        NSMutableString *qrst = [NSMutableString stringWithFormat:@"INSERT INTO %@ SELECT ", NSStringFromClass([self class])];
        NSString *qdropt = [NSString stringWithFormat:@"DROP TABLE %@_backup", NSStringFromClass([self class])];
        // complete the statements
        for (NSInteger i = 0; i < names.count; i++) {
            NSString *name = (NSString *)names[i];
            NSString *type = (NSString *)types[i];
            
            [qcrtb appendString:[NSString stringWithFormat:@"%@ %@", name, type]];
            [qbcp appendString:[NSString stringWithFormat:@"%@", name]];
            [qcrt appendString:[NSString stringWithFormat:@"%@ %@", name, type]];
            [qrst appendString:[NSString stringWithFormat:@"%@", name]];
            
            if (i < names.count - 1) {
                [qcrtb appendString:@", "];
                [qbcp appendString:@", "];
                [qcrt appendString:@", "];
                [qrst appendString:@", "];
            }
        }
        // finish statements
        [qcrtb appendString:@")"];
        [qbcp appendString:[NSString stringWithFormat:@" FROM %@", NSStringFromClass([self class])]];
        [qcrt appendString:@")"];
        [qrst appendString:[NSString stringWithFormat:@" FROM %@_backup", NSStringFromClass([self class])]];
        
        // execute statements
        char *err;
        BOOL success = (sqlite3_exec(_database, qcrtb.UTF8String, NULL, NULL, &err) == SQLITE_OK);
        if (success) success = (sqlite3_exec(_database, qbcp.UTF8String, NULL, NULL, &err) == SQLITE_OK);
        if (success) success = (sqlite3_exec(_database, qdropo.UTF8String, NULL, NULL, &err) == SQLITE_OK);
        if (success) success = (sqlite3_exec(_database, qcrt.UTF8String, NULL, NULL, &err) == SQLITE_OK);
        if (success) success = (sqlite3_exec(_database, qrst.UTF8String, NULL, NULL, &err) == SQLITE_OK);
        if (success) success = (sqlite3_exec(_database, qdropt.UTF8String, NULL, NULL, &err) == SQLITE_OK);
        
        if (!success) {
            [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_UPDATE_SCHEMA, err];
        }
    }
    
    // now insert
    if (insert.count != 0) {
        // the alter query
        NSString *alter = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN ", NSStringFromClass([self class])];
        // loop through each property to add
        BOOL success = YES;
        char *err = NULL;
        NSArray *keys = [insert allKeys];
        
        for (int i = 0; i < keys.count; i++) {
            NSString *name = (NSString *)keys[i];
            if (success) {
                NSString *type = (NSString *)[insert objectForKey:name];
                NSString *query = [alter stringByAppendingString:[NSString stringWithFormat:@"%@ %@", name, type]];
                if (success) {
                    success = (sqlite3_exec(_database, query.UTF8String, NULL, NULL, &err) == SQLITE_OK);
                }
            }
        }
        
        if (!success) {
            [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_UPDATE_SCHEMA, err];
        }
    }
    // clean up
    sqlite3_finalize(stmt);
    [self closeDatabase];
}

/**
 * Parse the attribute string returned by property_getAttributes into dictionary format
 *
 * @param: attr: the objc property attribute string
 * @return: NSDictionary<NSString *, id> *: the dictionary representation of the attributes info
 */
+ (NSDictionary<NSString *, id> *)parsePropertyAttribute:(NSString *)attr
{
    NSMutableDictionary<NSString *, id> *info = [NSMutableDictionary new];
    NSArray<NSString *> *attributes = [attr componentsSeparatedByString:@","];
    for (NSString *attrbute in attributes) {
        NSString *attrcode = [attrbute substringToIndex:1];
        if ([attrcode caseInsensitiveCompare:@"T"] == NSOrderedSame) {
            // attribute type
            int codepos = 1;
            NSString *typecode = [attrbute substringWithRange:NSMakeRange(codepos, 1)];
            // typecode my not not be the at the first position
            while (![ELXObjectPropertyTypeMap objectForKey:typecode] && codepos < attrbute.length) {
                codepos++;
                typecode = [attrbute substringWithRange:NSMakeRange(codepos, 1)];
            }
            
            if ([typecode isEqualToString:@"@"]) {
                // special case for NSString and NSDate
                NSArray *component = [attrbute componentsSeparatedByString:@"\""];
                NSString *subtype = (NSString *)component[1];
                if ([subtype isEqualToString:@"NSString"] || [subtype isEqualToString:@"NSDate"])
                    typecode = subtype;
                
                // add class type to support NSSecureCoding
                [info setObject:subtype forKey:kELXObjectPropertyClassKey];
            }
            [info setObject:[ELXObjectPropertyTypeMap objectForKey:typecode] forKey:kELXObjectPropertyTypeKey];
        } else if ([attrcode caseInsensitiveCompare:@"G"] == NSOrderedSame) {
            // attribute getter
            NSString *getter = [attrbute substringFromIndex:1];
            [info setObject:getter forKey:kELXObjectPropertyCustomGetterKey];
        } else if ([attrcode caseInsensitiveCompare:@"S"] == NSOrderedSame) {
            // attribute setter
            NSString *setter = [attrbute substringFromIndex:1];
            [info setObject:setter forKey:kELXObjectPropertyCustomSetterKey];
        } else if ([attrcode caseInsensitiveCompare:@"D"] == NSOrderedSame) {
            // @dynamic attribute
            [info setObject:[NSNumber numberWithBool:YES] forKey:kELXObjectPropertyDynamicKey];
        }
    }
    
    return info;
}

/**
 * Bind a prepared statement with bindings of a given type
 *
 * @param statement: the prepared sqlite3 statement to be bind
 * @param bindings: an array of bindings
 * @param types: the types of the bindings
 */
+ (void)bindStatment:(sqlite3_stmt **)statement withBindings:(nonnull NSMutableArray<ELXQueryBinding *> *)bindings
{
    if (bindings.count == 0) return;
    
    sqlite3_stmt *stmt = *statement;
    for (NSInteger i = 0; i < bindings.count; i++) {
        ELXQueryBinding *qb = bindings[i];
        id binding = qb.value;
        ELXObjectType type = [qb.type unsignedIntegerValue];
        if ([binding isKindOfClass:[NSNumber class]]) {
            if (type == ELXObjectTypeShort || type == ELXObjectTypeInt ||
                type == ELXObjectTypeUnsignedShort || type == ELXObjectTypeUnsignedInt) {
                int value = [(NSNumber *)binding intValue];
                int pos = (int)(i + 1);
                sqlite3_bind_int(stmt, pos, value);
            } else if (type == ELXObjectTypeLong || type == ELXObjectTypeLongLong ||
                       type == ELXObjectTypeUnsignedLong || type == ELXObjectTypeUnsignedLongLong) {
                long long value = [(NSNumber *)binding longLongValue];
                int pos = (int)(i + 1);
                sqlite3_bind_int64(stmt, pos, value);
            } else if (type == ELXObjectTypeFloat || type == ELXObjectTypeDouble || type == ELXObjectTypeDateTime) {
                double value = [(NSNumber *)binding doubleValue];
                int pos = (int)(i + 1);
                sqlite3_bind_double(stmt, pos, value);
            } else if (type == ELXObjectTypeBOOL) {
                int value = [(NSNumber *)binding intValue];
                int pos = (int)(i + 1);
                sqlite3_bind_int(stmt, pos, value);
            }
        } else if ([binding isKindOfClass:[NSString class]]) {
            // bind text
            int pos = (int)(i+1);
            NSString *text = (NSString *)binding;
            sqlite3_bind_text(stmt, pos, text.UTF8String, -1, NULL);
        } else if ([binding isKindOfClass:[NSData class]]) {
            // bind BLOB
            int pos = (int)(i+1);
            NSData *data = (NSData *)binding;
            sqlite3_bind_blob(stmt, pos, data.bytes, (int)data.length, SQLITE_STATIC);
        } else if ([binding isKindOfClass:[NSNull class]]) {
            // bind NULL value
            int pos = (int)(i+1);
            sqlite3_bind_null(stmt, pos);
        }
    }
    
    // cleanup query bindings
    [bindings removeAllObjects];
}

/**
 * Create the path, including the intermediate directories of the database file
 */
+ (void)createDatabaseFile
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self.class databaseFile]]) return;
    
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.class databasePath]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    const char *path = [[self.class databaseFile] UTF8String];
    int rc = sqlite3_open(path, &_database);
    if (rc != SQLITE_OK) {
        [NSException raise:ELXFailedSQLiteOperationException format:ERR_FAILED_CREATE_DB, rc];
    }
}

/**
 * Open the sqlite3 database
 */
+ (BOOL)openDatabase
{
    const char *path = [[self databaseFile] UTF8String];
    if (!_database) {
        int rc = sqlite3_open(path, &_database);
        return (rc == SQLITE_OK);
    }
    
    return YES;
}

/**
 * Close the sqlite3 database
 */
+ (BOOL)closeDatabase
{
    if (!_database) return YES;
    
    int  rc;
    BOOL retry;
    BOOL triedFinalizingOpenStatements = NO;
    
    do {
        retry   = NO;
        rc      = sqlite3_close(_database);
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            if (!triedFinalizingOpenStatements) {
                triedFinalizingOpenStatements = YES;
                sqlite3_stmt *pStmt;
                while ((pStmt = sqlite3_next_stmt(_database, nil)) !=0) {
                    NSLog(@"Closing leaked statement");
                    sqlite3_finalize(pStmt);
                    retry = YES;
                }
            }
        }
        else if (SQLITE_OK != rc) {
            NSLog(@"error closing!: %d", rc);
        }
    }
    while (retry);
    
    _database = nil;
    return YES;
}

/**
 * Captilize the first letter of the string
 */
+ (nonnull NSString *)capitalizeFirstLetterString:(nonnull NSString *)str
{
    NSString *first = [str substringToIndex:1];
    NSString *rest = [str substringWithRange:NSMakeRange(1, str.length - 1)];
    return [NSString stringWithFormat:@"%@%@", first.capitalizedString, rest];
}

#pragma mark - Object Lifecycle
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self.class commonInit];
        self.elxuid = NSUIntegerMax;
        self.archiveOption = ELXObjectArchiveOptionManual;
    }
    return self;
}

/**
 * If ELXObjectArchiveOption is set to ELXObjectArchiveOptionOnObjectDelloc, the object willbe archived
 * automatically when dealloc is called
 */
- (void)dealloc
{
    if (self.archiveOption == ELXObjectArchiveOptionOnObjectDelloc)
        [self archiveObject];
}

#pragma mark - NSSecureCoding Methods
+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        // walk through each property and assign values
        unsigned int pcount;
        objc_property_t *properties = class_copyPropertyList([self class], &pcount);
        unsigned int rcount;
        objc_property_t *rproperties = class_copyPropertyList([ELXObject class], &rcount);
        // special case: directly using ELXObject itself
        if ([self isMemberOfClass:[ELXObject class]]) {
            rcount = 0;
        }
        unsigned int tcount = pcount + rcount;
        for (unsigned int i = 0; i < tcount; i++) {
            objc_property_t property = (i < pcount) ? properties[i] : rproperties[i - pcount];
            NSString *name = [NSString stringWithUTF8String:property_getName(property)];
            NSString *key = [NSString stringWithFormat:@"%@::%@", NSStringFromClass([self class]), name];
            NSDictionary *attr = [self.class parsePropertyAttribute:[NSString stringWithUTF8String:property_getAttributes(property)]];
            ELXObjectType type = [(NSNumber *)[attr objectForKey:kELXObjectPropertyTypeKey] unsignedIntegerValue];
            NSString *settername = (NSString *)[attr objectForKey:kELXObjectPropertyCustomSetterKey];
            BOOL useCustomSetter = (settername != nil);
            if (!settername) {
                // use the default setter
                settername = [NSString stringWithFormat:@"set%@:", [self.class capitalizeFirstLetterString:name]];
            }
            SEL setter = NSSelectorFromString(settername);
            
            if (type == ELXObjectTypeUnsignedChar) {
                NSNumber *buf = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:key];
                if (!buf) continue;
                unsigned char val = [buf unsignedCharValue];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, unsigned char) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeBOOL) {
                BOOL val = [aDecoder decodeBoolForKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, BOOL) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeShort || type == ELXObjectTypeInt) {
                int val = [aDecoder decodeIntForKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, int) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeLong || type == ELXObjectTypeLongLong) {
                long long val = [aDecoder decodeInt64ForKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, long long) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeChar) {
                NSNumber *buf = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:key];
                if (!buf) continue;
                char val = [buf charValue];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, char) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeUnsignedShort || type == ELXObjectTypeUnsignedInt) {
                unsigned int val = (unsigned int)[aDecoder decodeIntForKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, unsigned int) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeUnsignedLong || type == ELXObjectTypeUnsignedLongLong) {
                unsigned long long val = (unsigned long long)[aDecoder decodeInt64ForKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, unsigned long long) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeFloat || type == ELXObjectTypeDouble) {
                double val = [aDecoder decodeDoubleForKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, double) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:@(val) forKey:name];
                }
            } else if (type == ELXObjectTypeCString) {
                NSString *buf = [aDecoder decodeObjectOfClass:[NSString class] forKey:key];
                if (!buf) continue;
                const char *val = buf.UTF8String;
                if (val == NULL) continue;
                if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                IMP imp = [self methodForSelector:setter];
                void (*func)(id, SEL, const char *) = (void *)imp;
                func(self, setter, val);
            } else if (type == ELXObjectTypeObject) {
                // we have to determine the type
                NSString *classname = [attr objectForKey:kELXObjectPropertyClassKey];
                Class cls = objc_lookUpClass(classname.UTF8String);
                id val = [aDecoder decodeObjectOfClass:cls forKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, id) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:val forKey:name];
                }
            } else if (type == ELXObjectTypeClass) {
                NSString *classname = [aDecoder decodeObjectOfClass:[NSString class] forKey:key];
                if (!classname) continue;
                Class val = objc_lookUpClass(classname.UTF8String);
                if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                IMP imp = [self methodForSelector:setter];
                void (*func)(id, SEL, Class) = (void *)imp;
                func(self, setter, val);
            } else if (type == ELXObjectTypeSelector) {
                NSData *buf = [aDecoder decodeObjectOfClass:[NSData class] forKey:key];
                if (!buf) continue;
                SEL val = *((SEL *)buf.bytes);
                
                // SEL type is not key value coding complaint, thus
                // use setter directly
                if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                IMP imp = [self methodForSelector:setter];
                void (*func)(id, SEL, SEL) = (void *)imp;
                func(self, setter, val);
            } else if (type == ELXObjectTypeArray) {
                NSLog(WARNING_UNSUPPORTED_TYPE, name);
            } else if (type == ELXObjectTypeStruct) {
                NSLog(WARNING_UNSUPPORTED_TYPE, name);
            } else if (type == ELXObjectTypeUnion) {
                NSLog(WARNING_UNSUPPORTED_TYPE, name);
            } else if (type == ELXObjectTypePtr) {
                NSLog(WARNING_UNSUPPORTED_TYPE, name);
            } else if (type == ELXObjectTypeString) {
                // we have to determine the type
                NSString *val = [aDecoder decodeObjectOfClass:[NSString class] forKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, NSString *) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:val forKey:name];
                }
            } else if (type == ELXObjectTypeDateTime) {
                NSDate *val = [aDecoder decodeObjectForKey:key];
                // if there is custom setter, try custome setter first
                if (useCustomSetter) {
                    if (![self respondsToSelector:setter]) {
                        [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_SETTER];
                    }
                    IMP imp = [self methodForSelector:setter];
                    void (*func)(id, SEL, NSDate *) = (void *)imp;
                    func(self, setter, val);
                } else {
                    // else directly use key-value coding
                    [self setValue:val forKey:name];
                }
            }
        }
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    // walk through each property and get values
    unsigned int pcount;
    objc_property_t *properties = class_copyPropertyList([self class], &pcount);
    unsigned int rcount;
    objc_property_t *rproperties = class_copyPropertyList([ELXObject class], &rcount);
    // special case: directly using ELXObject itself
    if ([self isMemberOfClass:[ELXObject class]]) {
        rcount = 0;
    }
    unsigned int tcount = pcount + rcount;
    for (unsigned int i = 0; i < tcount; i++) {
        objc_property_t property = (i < pcount) ? properties[i] : rproperties[i - pcount];
        NSString *name = [NSString stringWithUTF8String:property_getName(property)];
        NSString *key = [NSString stringWithFormat:@"%@::%@", NSStringFromClass([self class]), name];
        NSDictionary *attr = [self.class parsePropertyAttribute:[NSString stringWithUTF8String:property_getAttributes(property)]];
        ELXObjectType type = [(NSNumber *)[attr objectForKey:kELXObjectPropertyTypeKey] unsignedIntegerValue];
        NSString *gettername = (NSString *)[attr objectForKey:kELXObjectPropertyCustomGetterKey];
        BOOL useCustomeGetter = (gettername != nil);
        SEL getter = (gettername == nil) ? NSSelectorFromString(name) : NSSelectorFromString(gettername);
        
        if (type == ELXObjectTypeUnsignedChar) {
            unsigned char val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                unsigned char (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] unsignedCharValue];
            }
            
            NSNumber *value = [NSNumber numberWithUnsignedChar:val];
            [aCoder encodeObject:value forKey:key];
        } else if (type == ELXObjectTypeBOOL) {
            BOOL val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                BOOL (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] boolValue];
            }
            [aCoder encodeBool:val forKey:key];
        } else if (type == ELXObjectTypeShort || type == ELXObjectTypeInt) {
            int val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                int (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] intValue];
            }
            [aCoder encodeInt:val forKey:key];
        } else if (type == ELXObjectTypeLong || type == ELXObjectTypeLongLong) {
            long long val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                long long (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] longLongValue];
            }
            [aCoder encodeInt64:val forKey:key];
        } else if (type == ELXObjectTypeChar) {
            char val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                char (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] unsignedCharValue];
            }
            
            NSNumber *value = [NSNumber numberWithChar:val];
            [aCoder encodeObject:value forKey:key];
        } else if (type == ELXObjectTypeUnsignedShort || type == ELXObjectTypeUnsignedInt) {
            unsigned int val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                unsigned int (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] unsignedIntValue];
            }
            [aCoder encodeInt:val forKey:key];
        } else if (type == ELXObjectTypeUnsignedLong || type == ELXObjectTypeUnsignedLongLong) {
            unsigned long long val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                unsigned long long (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] unsignedLongLongValue];
            }
            [aCoder encodeInt64:val forKey:key];
        } else if (type == ELXObjectTypeFloat || type == ELXObjectTypeDouble) {
            double val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                double (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [(NSNumber *)[self valueForKey:name] doubleValue];
            }
            [aCoder encodeDouble:val forKey:key];
        } else if (type == ELXObjectTypeCString) {
            const char *val = NULL;
            NSString *value = nil;
            
            if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
            IMP imp = [self methodForSelector:getter];
            const char *(*func)(id, SEL) = (void *)imp;
            val = func(self, getter);
            
            if (val) value = [NSString stringWithUTF8String:val];
            
            [aCoder encodeObject:value forKey:key];
        } else if (type == ELXObjectTypeObject) {
            id val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                id (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [self valueForKey:name];
            }
            
            if (!val) continue;
            // objects properties must conform NSCoding protocol to be seralized
            Protocol *nscoding = objc_getProtocol(@"NSCoding".UTF8String);
            Class cls = [val class];
            BOOL conformsProtocol = class_conformsToProtocol(cls, nscoding);
            // here have to recursively check super classes
            while (!conformsProtocol && ![NSStringFromClass(cls) isEqualToString:@"NSObject"]) {
                cls = class_getSuperclass(cls);
                conformsProtocol = class_conformsToProtocol(cls, nscoding);
            }
            
            if (!conformsProtocol) {
                NSLog(WARNING_NOT_NSCODING, name);
                continue;
            }
            
            [aCoder encodeObject:val forKey:key];
        } else if (type == ELXObjectTypeClass) {
            Class val = NULL;
            NSValue *value;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                Class (*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [self valueForKey:name];
            }
            
            if (!val && value) [value getValue:&val];
            NSString *valname = NSStringFromClass(val);
            [aCoder encodeObject:valname forKey:key];
        } else if (type == ELXObjectTypeSelector) {
            SEL val = NULL;
            NSData *value = nil;
            
            if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
            IMP imp = [self methodForSelector:getter];
            SEL (*func)(id, SEL) = (void *)imp;
            val = func(self, getter);
            
            value = (val != NULL) ? [NSData dataWithBytes:&val length:sizeof(SEL)] : value;
            [aCoder encodeObject:value forKey:key];
        } else if (type == ELXObjectTypeArray) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        } else if (type == ELXObjectTypeStruct) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        } else if (type == ELXObjectTypeUnion) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        } else if (type == ELXObjectTypePtr) {
            NSLog(WARNING_UNSUPPORTED_TYPE, name);
        } else if (type == ELXObjectTypeString) {
            NSString *val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                NSString *(*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [self valueForKey:name];
            }
            [aCoder encodeObject:val forKey:key];
        } else if (type == ELXObjectTypeDateTime) {
            NSDate *val;
            if (useCustomeGetter) {
                if (![self respondsToSelector:getter]) {
                    [NSException raise:ELXInvalidPropertyException format:ERR_INVALID_GETTER];
                }
                IMP imp = [self methodForSelector:getter];
                NSDate *(*func)(id, SEL) = (void *)imp;
                val = func(self, getter);
            } else {
                val = [self valueForKey:name];
            }
            [aCoder encodeObject:val forKey:key];
        }
    }
}

@end
//
//  ELXObject.h
//  Elixir
//
//  Created by Yizhe Hu on 1/16/16.
//  Copyright © 2016 Yizhe Hu. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, ELXObjectArchiveOption) {
    ELXObjectArchiveOptionManual = 0,                   // Archive object manually
    ELXObjectArchiveOptionOnObjectDelloc = (1 << 0),    // Archive object automatically when object is deallocated (default)
};

/**
 * Use Elixir by subclassing ELXObject
 */
@interface ELXObject : NSObject <NSSecureCoding>

#pragma mark - Archiving & Deleting Objects
/**
 * Object will be written to on-disk or in-memory database when invoked.
 * This method is automatically invoked at -(void)delloc with ELXObjectArchiveOptionOnObjectDelloc option.
 */
- (void)archiveObject;
/**
 * Remove the object from on-disk or in-memory database
 * NOTE: if an object is saved both on-disk and in-memory, only the version it's currently in will be deleted.
 */
- (void)deleteObject;

#pragma mark - Query Objects
/**
 * Get all objects (both on-disk and in-memory) of this class.
 * If no objects found, an empty array will be returned.
 *
 * @return NSArray<ELXObject *> *: an array of all objects in database
 */
+ (nonnull NSArray<ELXObject *> *)allObjects;
/**
 * Get objects matching the given predicate from both on-disk and in-memory database.
 * Here predicateFormat should be in NSPredicate Predicate Format String Syntax.
 * This method will try to construct a NSPredicate according to predicateFormat then perform the query.
 *
 * @param predicateFormat: the NSPredicate Predicate Format String to construct predicate
 * @return NSArray<ELXObject *> *: an array of objects matching the given predicate
 */
+ (nonnull NSArray<ELXObject *> *)objectsWhere:(nonnull NSString *)predicateFormat, ...;
/**
 * Get objects matching the given predicate from both on-disk and in-memory database.
 *
 * @param predicate: the NSPredicate to query
 * @return NSArray<ELXObject *> *: an array of objects matching the given predicate
 */
+ (nonnull NSArray<ELXObject *> *)objectsWithPredicate:(nonnull NSPredicate *)predicate;

#pragma mark - In Memory Only Behavior
/**
 * If set to YES, the current object will be in-memory-only.
 * This means all the changes will only be buffered in memory, but you can still query the object.
 * NOTE: if you set a object to be in-memory-only after archiving it, the further changes will
 * be cached in memory only.
 *
 * @param inMemoryOnly: whether this object should be in-memory-only
 */
- (void)setInMemoryOnly:(BOOL)inMemoryOnly;

#pragma mark - Configuration
/**
 * Override this method to change the path to the on-disk database file.
 * WARNING: Do NOT change this path after you have already saved items to database
 * because the data base will NOT be relocated
 *
 * @return NSSting *: the string path to the on-disk database file
 */
+ (nonnull NSString *)databasePath;
/**
 * Set the archive option to the current object. See ELXObjectArchiveOption ENUM for the options.
 * The default value is ELXObjectArchiveOptionManual.
 *
 * @param ELXObjectArchiveOption: the new archive option to be set
 */
- (void)setArchiveOption:(ELXObjectArchiveOption)archiveOption;

@end

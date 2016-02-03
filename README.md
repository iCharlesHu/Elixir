# Elixir

**TL;DR:** Elixir is a simple and lightweight library that lets you easily persist your objects (i.e. make them live forever*) and query objects.

(*: sometimes when grownups say forever, they mean a very long time.)

## Overview
Let's face it: most of times, we need some of our objects to live just longer than the running application itself. Backend by SQLite, Elixir is a simple (only 4 core APIs) and lightweight (only 2 files, around 2000 lines of code) persistent solution. It fully utilizes Objective-C's runtime environment to automatically save and load object properties to and from a sqlite database with minimum user interaction; it provides object query support with the NSPredicate interface, and most importantly, with simplicity as the main design objective, Elixir is very easy to use. Elixir is perfect for the projects that are too complex to use NSUserDefault, but not complicated enough to require the convolution of CoreData or raw SQL.

## Installation
#### CocoaPods
(coming later)

#### Carthage
(coming later)

#### Manual
Since there are only 2 files, you can easily include Elixir adding the source files directly.

Elixir is backend by `sqlite`, therefore you need to link `libsqlite3` library to your project. To do so, go to your target > Build Phases > Link Binary with Libraries, and click "+" and search for `libsqlite3`.

## Usage
Before using Elixir, make sure you include the `ELXObject` header file:
```obj-c
#import "ELXObject.h"
```
To use Elixir, **subclass** any object that you wish to persistent on disk from `ELXObject`.

### Archiving Object
```obj-c
- (void)archiveObject
```
As the name suggests, this method will insert the object into database (in-memory or on-disk).

### Deleting Object
```obj-c
- (void)deleteObject
```
NOTE: if an object is saved both on-disk and in-memory, only the version it's currently in will be deleted.

### Querying Objects
```obj-c
+ (nonnull NSArray<ELXObject *> *)allObjects;
+ (nonnull NSArray<ELXObject *> *)objectsWhere:(nonnull NSString *)predicateFormat, ...;
+ (nonnull NSArray<ELXObject *> *)objectsWithPredicate:(nonnull NSPredicate *)predicate;
```
You can use NSPredicate to query your objects (see Apple's [documentation](https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/Predicates/Articles/pSyntax.html) for Predicate Format String Syntax). Currently Elixir supports these predicate comparisons:
- Basic Comparisons: =, >, >=, <, <=, !=, BETWEEN, IN.
- String Comparison: BEGINSWITH, CONTAINS, LIKE.
- Compound Predicates: AND, OR, NOT.

These methods will return an empty `NSArray` if no objects found.

Note that although SQL does not enforce column name (property name) to be the left-hand-side of the comparison, some predicates (for example, `BETWEEN` and `IN`) do emphasis this order. Therefore, it's always a good practice to put property name as the left-hand-side and the value you are comparing to as the right hand side when defining a predicate.

## In-Memory-Only Mode
You can set a object to be saved in memory only by invoking
```obj-c
- (void)setInMemoryOnly:(BOOL)inMemoryOnly;
```
When an object is in memory only, it will no longer be write to database on disk; instead, it will be cached in memory. This object will still appear as a result of your query. In memory mode is a great way to save temporary data.

## Configuration
### ELXObjectArchiveOption
There are currently two `ELXObjectArchiveOptions`:
- With `ELXObjectArchiveOptionManual`, you have to archive objects by manually invoke `- (void)archieveObject`.
- With `ELXObjectArchiveOptionOnObjectDelloc`, the object will be automatically saved when it's being dealloced.

The default value is `ELXObjectArchiveOptionManual`.

### Database File Path
On OS X, the default database file path for Elixir is `~/Library/Application Support/com.iCharlesHu.Elixir/base/elixir.db` (`NSApplicationSupportDirectory` with `NSUserDomainMask`).

On iOS, the default database file path is (within App's sandbox): `/Documents/base/elixir.db` (`NSDocumentDirectory` with `NSUserDomainMask`).
You can change the database file path by **overriding** this method.

## Misc
### Supported Datatypes
All primitive datatypes are supported except `struct`, `union`, `array`(not `NSArray`), and `pointers` (see Limitations). All objects conforming `NSCoding` (or `NSSecureCoding`) are supported.

### Property Attributes
Custom getters and setters are supported. Elixir will try to get/set property values via key-value coding, or your custom getters and setters if provided. However, there are several datatypes that are not key-value coding complaint (i.e. C string, Class and SEL), and Elixir relies solely on the setters to update those values. Therefore, if you are using these types, please avoid making them `readonly`.

### Ivars
By design, Elixir will only store object properties, NOT Ivars. Therefore, you can use Ivars to store some value that you don't wish to be saved.

### Schema Update
Elixir will automatically check the current list of properties against saved table schema, and add/delete columns when needed. However, since deleting a column is very costly and it might introduce data lose, please try to **avoid** deleting columns.


**NOTE:** do *NOT* **rename** object properties. Elixir will treat it as a new property and delete the old column, which will cause the loss of data.

### Limitations
The primary design goal Elixir is to be *lightweight* and *simple to use*. Therefore, some functionalities are sacrificed for the simplicity. Specifically:
- `struct`, `union`, `array`, and `pointer` types are *NOT* supported. You can still use them as properties, but they will not be saved to database. The reason behind this decision is that Objective-C forbits the creation of an unknown struct (or union) at runtime. However, you can pack your structs to `NSData` or `NSValue` and save them instead.
- At this stage, all the `NSCoding` conforming objects (except `NSDate` and `NSString`, but including *all* the collection types) are serialized and stored as `blob` in the SQL table. This means predicate comparison on object properties will *NOT* work. Predicate comparisons mostly work on strings and numeric properties.

## License
This code is distributed under the terms and conditions of the MIT license.
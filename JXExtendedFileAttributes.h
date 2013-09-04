//
//  XAttr.h
//  xattr
//
//  Created by Robert Pointon on 14/06/2005.
//
//  Copyright 2005 Robert Pointon. Do whatever you want. I make no claim that it’s correct or bug free.
//  Copyright 2013 Jan Weiß. Some rights reserved: <http://opensource.org/licenses/mit-license.php>
//

#import <Cocoa/Cocoa.h>

@interface JXExtendedFileAttributes : NSObject {
	int _fd;
}

// Returns nil on failure
- (instancetype)initWithURL:(NSURL *)theURL;
- (instancetype)initWithFile:(NSString *)path;

// Returns an array of NSString, returns nil on failure
- (NSArray *)keys;

// Returns nil on failure
- (NSData *)dataForKey:(NSString *)key;

// Returns YES if successful
- (BOOL)removeDataForKey:(NSString *)key;

// Returns YES if successful
- (BOOL)removeAllData;

// Returns YES if successful
// Removes data if value is nil
- (BOOL)setData:(NSData *)value forKey:(NSString *)key;

// Convenience methods auto-detecting necessary conversions.
- (id)objectForKey:(NSString *)key;
- (BOOL)setObject:(id <NSObject, NSCoding>)value forKey:(NSString *)key;

// Close file immediately rather than waiting for dealloc
- (void)closeFile;

@end

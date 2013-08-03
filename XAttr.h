//
//  XAttr.h
//  xattr
//
//  Created by Robert Pointon on 14/06/2005.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface XAttr : NSObject {
	int fd;
}

- (id)initWithURL:(NSURL *)theURL;
- (id)initWithFile:(NSString *)path;

// Returns an array of NSString, returns nil on failure
- (NSArray *)keys;

// Returns nil on failure
- (NSData *)dataForKey:(NSString *)key;

// Returns YES if successful
- (BOOL)removeDataForKey:(NSString *)key;

// Returns YES if successful
- (BOOL)removeAllData;

// Returns YES if successful
- (BOOL)setData:(NSData *)value forKey:(NSString *)key;

// Close file immediately rather than waiting for dealloc
- (void)closeFile;

@end

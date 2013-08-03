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

- (id)initWithFilePath:(NSString *)path;

// Return array of NSString*, return nil if fails
- (NSArray *)keys;

// Return nil if fails
- (NSData *)dataForKey:(NSString *)key;

// Return YES if succeeded
- (BOOL)removeDataForKey:(NSString *)key;

// Return YES if succeeded
- (BOOL)removeAllData;

// Return YES if succeeded
- (BOOL)setData:(NSData *)value forKey:(NSString *)key;

// Close immediately rather than wait for dealloc
- (void)closeFile;

@end

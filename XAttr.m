//
//  XAttr.m
//  xattr
//
//  Created by Robert Pointon on 14/06/2005.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "XAttr.h"

#include <sys/xattr.h>
#include <sys/fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

@implementation XAttr

- (NSData *)getAttributeListData
{
	int options = 0x00;
	char *buff;
	
	ssize_t size = flistxattr(fd, NULL, 0, options);
	if (size == -1) {
		return nil;
	}
	
	NSMutableData *data = [NSMutableData dataWithCapacity:size];
	[data setLength:size];
	
spin: // Spin in case the size changes under us…
	buff = (char *)[data mutableBytes];
	errno = 0;
	
	size = flistxattr(fd, buff, size, options);
	if (size != -1) {
		// Success.
		[data setLength:size];
		return data;
	}
	
	if (errno == ERANGE) {
		// Guess the value size again.
		size = flistxattr(fd, NULL, 0, options);
		if (size != -1) {
			[data setLength:size];
			goto spin;
		}
	}
	
	// Failure.
	return nil;
}

- (NSData *)valueDataForCStringKey:(const char *)key
{
	int options = 0x00;
	char *buff;
	
	ssize_t size = fgetxattr(fd, key, NULL, 0, 0, options);
	if (size == -1) {
		return nil;
	}
	
	NSMutableData *data = [NSMutableData dataWithCapacity:size];
	[data setLength:size];
	
spin: // Spin in case the size changes under us…
	buff = (char *)[data mutableBytes];
	errno = 0;
	
	size = fgetxattr(fd, key, buff, size, 0, options);
	if (size != -1) {
		// Success.
		[data setLength:size];
		return data;
	}
	
	if (errno == ERANGE) {
		// Guess the value size again.
		size = fgetxattr(fd, key, NULL, 0, 0, options);
		if (size != -1) {
			[data setLength:size];
			goto spin;
		}
	}
	
	// Failure.
	return nil;
}

- (void)closeFile
{
	if (fd != -1) {
		close(fd);
		fd = -1;
	}
}

- (void)dealloc
{
	[self closeFile];
	
	[super dealloc];
}

- (id)initWithURL:(NSURL *)theURL;
{
	if ([theURL isFileURL] || [theURL isFileReferenceURL]) {
		return [self initWithFile:[theURL path]];
	}
	else {
		return nil;
	}
}

- (id)initWithFile:(NSString *)path
{
	if (self = [super init]) {
		fd = open([path fileSystemRepresentation], O_RDONLY, 0);
		if (fd < 0) {
			//NSLog(@"Err: Unable to open file");
			[self release];
			return nil;
		}
	}
	return self;
}

- (BOOL)removeAllData
{
	NSData *list = [self getAttributeListData];
	
	if (!list) {
		return NO;
	}
	
	int options = 0x00;
	char *key;
	char *start = (char *)[list bytes];
	
	for (key = start; (key - start) < [list length]; key += strlen(key) + 1) {
		int ret = fremovexattr(fd, key, options);
		if (ret != 0) {
			return NO;
		}
	}
	
	return YES;
}


#define xattrKeynameCStringForNSString(keyname, key)	\
	char keyname[XATTR_MAXNAMELEN + 1];\
	if ([key getCString:keyname maxLength:(XATTR_MAXNAMELEN + 1) encoding:NSUTF8StringEncoding] == NO)  return NO;


- (BOOL)removeDataForKey:(NSString *)key
{
	if (fd == -1) {
		return NO;
	}
	
	int options = 0x00;
	
	xattrKeynameCStringForNSString(keyname, key);
	int ret = fremovexattr(fd, keyname, options);
	return ret == 0;
}

- (BOOL)setData:(NSData *)value forKey:(NSString *)key
{
	if (fd == -1) {
		return NO;
	}
	
	int options = 0x00;
	
	xattrKeynameCStringForNSString(keyname, key);
	int ret = fsetxattr(fd, keyname, (char *)[value bytes], [value length], 0, options);
	return ret == 0;
}

- (NSData *)dataForKey:(NSString *)key
{
	if (fd == -1) {
		return nil;
	}
	
	xattrKeynameCStringForNSString(keyname, key);
	return [self valueDataForCStringKey:keyname];
}

- (NSArray *)keys
{
	NSData *listData = [self getAttributeListData];
	if (!listData) {
		return nil;
	}
	
	NSMutableArray *array = [[NSMutableArray alloc] init];
	char *key;
	char *start = (char *)[listData bytes];
	
	for (key = start; (key - start) < [listData length]; key += strlen(key) + 1) {
		NSString *name = [NSString stringWithUTF8String:key];
		[array addObject:name];
	}
	
	return [array autorelease];
}

@end

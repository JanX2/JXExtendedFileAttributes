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

- (NSData *)getList
{
	int options = 0x00;
	char *buff;
	ssize_t size = flistxattr(fd, NULL, 0, options);
	if (size == -1) {
		return nil;
	}
	NSMutableData *data = [NSMutableData dataWithCapacity:size];
	[data setLength:size];
spin: //spin in case the size changes under us...
	buff = (char *)[data mutableBytes];
	errno = 0;
	size = flistxattr(fd, buff, size, options);
	if (size != -1) {
		//success
		[data setLength:size];
		return data;
	}
	if (errno == ERANGE) {
		//guess the value size again
		size = flistxattr(fd, NULL, 0, options);
		if (size != -1) {
			[data setLength:size];
			goto spin;
		}
	}
	//failure
	return nil;
}

- (NSData *)getValue:(const char *)key
{
	int options = 0x00;
	char *buff;
	ssize_t size = fgetxattr(fd, key, NULL, 0, 0, options);
	if (size == -1) {
		return nil;
	}
	NSMutableData *data = [NSMutableData dataWithCapacity:size];
	[data setLength:size];
spin: //spin in case the size changes under us...
	buff = (char *)[data mutableBytes];
	errno = 0;
	size = fgetxattr(fd, key, buff, size, 0, options);
	if (size != -1) {
		//success
		[data setLength:size];
		return data;
	}
	if (errno == ERANGE) {
		//guess the value size again
		size = fgetxattr(fd, key, NULL, 0, 0, options);
		if (size != -1) {
			[data setLength:size];
			goto spin;
		}
	}
	//failure
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
	NSLog(@"dealloc: XAttr");
	[self closeFile];
	[super dealloc];
}

- (id)initWithURL:(NSURL *)theURL;
{
	if ([theURL isFileURL] || [theURL isFileReferenceURL]) {
		return [self initWithFilePath:[theURL path]];
	} else {
		return nil;
	}
}

- (id)initWithFilePath:(NSString *)path
{
	if (self = [super init]) {
		fd = open([path fileSystemRepresentation], O_RDONLY, 0);
		if (fd < 0) {
			NSLog(@"Err: Unable to open file");
		}
	}
	return self;
}

- (BOOL)removeAllData
{
	NSData *list = [self getList];
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

- (BOOL)removeDataForKey:(NSString *)key
{
	if (fd == -1) {
		return NO;
	}
	int options = 0x00;
	const char *keyname = [key UTF8String];
	int ret = fremovexattr(fd, keyname, options);
	return ret == 0;
}

- (BOOL)setData:(NSData *)value forKey:(NSString *)key
{
	if (fd == -1) {
		return NO;
	}
	int options = 0x00;
	const char *keyname = [key UTF8String];
	int ret = fsetxattr(fd, keyname, (char *)[value bytes], [value length], 0, options);
	return ret == 0;
}

//will return nil if fails to read data
- (NSData *)dataForKey:(NSString *)key
{
	if (fd == -1) {
		return nil;
	}
	const char *keyname = [key UTF8String];
	return [self getValue:keyname];
}

//will return nil if fails to read data
- (NSArray *)keys
{
	NSData *list = [self getList];
	if (!list) {
		return nil;
	}
	NSMutableArray *array = [[NSMutableArray alloc] init];
	char *key;
	char *start = (char *)[list bytes];
	for (key = start; (key - start) < [list length]; key += strlen(key) + 1) {
		NSString *name = [NSString stringWithUTF8String:key];
		[array addObject:name];
	}
	return [array autorelease];
}

@end

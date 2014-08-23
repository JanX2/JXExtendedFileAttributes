//
//  JXExtendedFileAttributes.m
//  xattr
//
//  Created by Robert Pointon on 14/06/2005.
//
//  Copyright 2005 Robert Pointon. Do whatever you want. I make no claim that it’s correct or bug free.
//  Copyright 2013 Jan Weiß. Some rights reserved: <http://opensource.org/licenses/mit-license.php>
//

#import "JXExtendedFileAttributes.h"

#include <sys/xattr.h>
#include <sys/fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>


NSString * const JXAppleStringEncodingAttributeKey = @"com.apple.TextEncoding";

@implementation JXExtendedFileAttributes

- (NSData *)_getAttributeListData
{
	int options = 0x00;
	char *buff;
	
	ssize_t size = flistxattr(_fd, NULL, 0, options);
	if (size == -1) {
		return nil;
	}
	
	NSMutableData *data = [NSMutableData dataWithCapacity:size];
	[data setLength:size];
	
spin: // Spin in case the size changes under us…
	buff = (char *)[data mutableBytes];
	errno = 0;
	
	size = flistxattr(_fd, buff, size, options);
	if (size != -1) {
		// Success.
		[data setLength:size];
		return data;
	}
	
	if (errno == ERANGE) {
		// Guess the value size again.
		size = flistxattr(_fd, NULL, 0, options);
		if (size != -1) {
			[data setLength:size];
			goto spin;
		}
	}
	
	// Failure.
	return nil;
}

- (NSData *)_valueDataForCStringKey:(const char *)key
{
	int options = 0x00;
	char *buff;
	
	ssize_t size = fgetxattr(_fd, key, NULL, 0, 0, options);
	if (size == -1) {
		return nil;
	}
	
	NSMutableData *data = [NSMutableData dataWithCapacity:size];
	[data setLength:size];
	
spin: // Spin in case the size changes under us…
	buff = (char *)[data mutableBytes];
	errno = 0;
	
	size = fgetxattr(_fd, key, buff, size, 0, options);
	if (size != -1) {
		// Success.
		[data setLength:size];
		return data;
	}
	
	if (errno == ERANGE) {
		// Guess the value size again.
		size = fgetxattr(_fd, key, NULL, 0, 0, options);
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
	if (_fd != -1) {
		close(_fd);
		_fd = -1;
	}
}

- (void)dealloc
{
	[self closeFile];
	
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

- (instancetype)initWithURL:(NSURL *)theURL;
{
	if ([theURL isFileURL] || [theURL isFileReferenceURL]) {
		return [self initWithFile:[theURL path]];
	}
	else {
		return nil;
	}
}

- (instancetype)initWithFile:(NSString *)path
{
	if (self = [super init]) {
		_fd = open([path fileSystemRepresentation], O_RDONLY, 0);
		if (_fd < 0) {
			//NSLog(@"Err: Unable to open file");
#if !__has_feature(objc_arc)
			[self release];
#endif
			return nil;
		}
	}
	return self;
}

- (BOOL)removeAllData
{
	NSData *listData = [self _getAttributeListData];
	
	if (listData == nil) {
		return NO;
	}
	
	int options = 0x00;
	char *key;
	char *start = (char *)[listData bytes];
	
	for (key = start; (key - start) < (ssize_t)[listData length]; key += strlen(key) + 1) {
		int ret = fremovexattr(_fd, key, options);
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
	if (key == nil || _fd == -1) {
		return NO;
	}
	
	int options = 0x00;
	
	xattrKeynameCStringForNSString(keyname, key);
	int ret = fremovexattr(_fd, keyname, options);
	return ret == 0;
}

- (BOOL)setData:(NSData *)value forKey:(NSString *)key
{
	if (value == nil) {
		return [self removeDataForKey:key];
	}
	
	if (key == nil || _fd == -1) {
		return NO;
	}
	
	int options = 0x00;
	
	xattrKeynameCStringForNSString(keyname, key);
	int ret = fsetxattr(_fd, keyname, (char *)[value bytes], [value length], 0, options);
	return ret == 0;
}

- (NSData *)dataForKey:(NSString *)key
{
	if (key == nil || _fd == -1) {
		return nil;
	}
	
	xattrKeynameCStringForNSString(keyname, key);
	return [self _valueDataForCStringKey:keyname];
}

- (NSArray *)keys
{
	NSData *listData = [self _getAttributeListData];
	if (listData == nil) {
		return nil;
	}
	
	NSMutableArray *array = [NSMutableArray array];
	char *key;
	char *start = (char *)[listData bytes];
	
	for (key = start; (key - start) < (ssize_t)[listData length]; key += strlen(key) + 1) {
		NSString *name = @(key);
		[array addObject:name];
	}
	
	return array;
}


#pragma mark Convenience methods

- (id)objectForKey:(NSString *)key;
{
	NSData *data = [self dataForKey:key];
	id value = nil;
	
	id unarchivedRoot = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	if (unarchivedRoot != nil) {
		value = unarchivedRoot;
	}
	else {
        value = plistRootForData(data);
	}
	
	if (value == nil) {
		// Fallback 1.
		value = stringForData(data);
	}
	
	if (value == nil) {
		// Fallback 2.
		value = data;
	}
	
	return value;
}

- (BOOL)setObject:(id <NSObject, NSCoding>)value forKey:(NSString *)key;
{
	NSPropertyListFormat outFormat = NSPropertyListBinaryFormat_v1_0;
	NSData *data = nil;

	if ([value isKindOfClass:[NSString class]]) {
		data = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
	}
	else if ([value isKindOfClass:[NSData class]]) {
		data = (NSData *)value;
	}
    else if ([NSPropertyListSerialization propertyList:value
									  isValidForFormat:outFormat]) {
		data = [NSPropertyListSerialization dataWithPropertyList:value
														  format:outFormat
														 options:0
														   error:NULL];
    }
	else {
		data = [NSKeyedArchiver archivedDataWithRootObject:value];
	}
	
	if (data == nil) {
		return NO;
	}
	else {
		return [self setData:data forKey:key];
	}

}


- (id)objectForKey:(NSString *)key ofType:(JXExtendedFileAttributesValueTypes)valueType;
{
	NSData *data = [self dataForKey:key];
	if (data == nil)  return nil;
	
	id value = nil;
	
	switch (valueType) {
		case JXExtendedFileAttributesNSStringType:
			value = stringForData(data);
			break;
			
		case JXExtendedFileAttributesNSPropertyListType:
			value = plistRootForData(data);
			break;
			
		case JXExtendedFileAttributesNSCodingType:
			value = [NSKeyedUnarchiver unarchiveObjectWithData:data];
			break;
			
		case JXExtendedFileAttributesNSDataType:
			value = data;
			break;
			
		default:
			break;
	}
	
	return value;
}

- (BOOL)setObject:(id <NSObject, NSCoding>)value ofType:(JXExtendedFileAttributesValueTypes)valueType forKey:(NSString *)key;
{
	NSPropertyListFormat outFormat = NSPropertyListBinaryFormat_v1_0;
	NSData *data = nil;
	NSError *error;
	
	switch (valueType) {
		case JXExtendedFileAttributesNSStringType:
			data = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
			break;
			
		case JXExtendedFileAttributesNSPropertyListType:
			if ([NSPropertyListSerialization propertyList:value
										 isValidForFormat:outFormat]) {
				data = [NSPropertyListSerialization dataWithPropertyList:value
																  format:outFormat
																 options:0
																   error:&error];
			}
			break;
			
		case JXExtendedFileAttributesNSCodingType:
			data = [NSKeyedArchiver archivedDataWithRootObject:value];
			break;
			
		case JXExtendedFileAttributesNSDataType:
			data = (NSData *)value;
			break;
			
		default:
			break;
	}
	
	if (data == nil) {
		return NO;
	}
	else {
		return [self setData:data forKey:key];
	}
	
}


- (NSString *)stringForKey:(NSString *)key;
{
	NSData *data = [self dataForKey:key];
	if (data == nil)  return nil;
	
	NSString *value = stringForData(data);
	
	return value;
}

- (BOOL)setString:(NSString *)value forKey:(NSString *)key;
{
	NSData *data = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
	return [self setData:data forKey:key];
}


+ (NSStringEncoding)stringEncodingForAttribute:(NSString *)encodingAttribute;
{
	if (encodingAttribute == nil)  return 0;
	
	NSStringEncoding encoding = 0;
	BOOL success = NO;
	
	NSArray *array = [encodingAttribute componentsSeparatedByString:@";"];
	if (array.count >= 2) {
		CFStringRef encodingName = (__bridge CFStringRef)array[0];
		CFStringEncoding cfEncodingFromName = CFStringConvertIANACharSetNameToEncoding(encodingName);
		
		NSString *encodingNumberString = array[1];
		CFStringEncoding cfEncoding = (CFStringEncoding)[encodingNumberString longLongValue];
		
		if (cfEncoding == cfEncodingFromName) {
			encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
			success = YES;
		}
	}
	else {
		NSLog(@"Could not parse ‘%@’ for key ‘%@’", encodingAttribute, JXAppleStringEncodingAttributeKey);
	}
	
	encoding = success ? encoding : 0;
	
	return encoding;
}

- (NSStringEncoding)appleStringEncoding;
{
	NSString *encodingAttribute = [self stringForKey:JXAppleStringEncodingAttributeKey];
	
	NSStringEncoding encoding = [[self class] stringEncodingForAttribute:encodingAttribute];
	
	return encoding;
}

+ (NSString *)attributeForEncoding:(NSStringEncoding)encoding;
{
	if (encoding == 0)  return nil;
	
	CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding);
	CFStringRef encodingName = CFStringConvertEncodingToIANACharSetName(cfEncoding);
	NSString *encodingAttribute = [NSString stringWithFormat:@"%@;%lu", encodingName, (unsigned long)cfEncoding];
	
	return encodingAttribute;
}

- (BOOL)setAppleStringEncoding:(NSStringEncoding)encoding;
{
	NSString *encodingAttribute = [[self class] attributeForEncoding:encoding];
	
	if (encodingAttribute == nil)  return NO;
	
	return [self setString:encodingAttribute
					forKey:JXAppleStringEncodingAttributeKey];
}


#pragma mark Utility functions

id plistRootForData(NSData *data) {
    id plistRoot = [NSPropertyListSerialization propertyListWithData:data
															 options:NSPropertyListImmutable
															  format:NULL
															   error:NULL];
    return plistRoot;
}

NSString * stringForData(NSData *data) {
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
#if !__has_feature(objc_arc)
	[string autorelease];
#endif
	
    return string;
}

@end

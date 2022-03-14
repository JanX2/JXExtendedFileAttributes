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


#define XATTR_MAXNAMELEN_TERMINATED	(XATTR_MAXNAMELEN + 1)
#define NAME_BUFFER_DEFAULT_SIZE	(XATTR_MAXNAMELEN_TERMINATED * 4)
#define VALUE_BUFFER_DEFAULT_SIZE	512


@implementation JXExtendedFileAttributes

- (BOOL)_processAttributeListData:(BOOL (^)(const char *, ssize_t))process
{
	int options = 0x00;
	char *buffer;
	
	char *dynamic = NULL;
	
	char fixed[NAME_BUFFER_DEFAULT_SIZE];
	ssize_t size = NAME_BUFFER_DEFAULT_SIZE;
	
	BOOL success = NO;
	
	do { // Repeat in case the buffer size needs to increase…
		BOOL useDynamic = dynamic != NULL;
		buffer = useDynamic ? dynamic : (char *)&fixed;
		
		errno = 0;
		size = flistxattr(_fd, buffer, size, options);
		int errorCode = errno;
		
		if (size != -1) {
			// Success.
			success = process(buffer, size);
			break;
		}
		
		if (errorCode == ERANGE) {
			// Request the size again.
			size = flistxattr(_fd, NULL, 0, options);
			
			if (size != -1) {
				// Increase buffer size.
				dynamic = calloc(size, sizeof(char));
				continue;
			}
		}
		
		// We don’t have a strategy implemented for recovering from this failure.
		break;
	} while (1);
	
	if (dynamic) {
		free(dynamic);
		dynamic = NULL;
	}
	
	return success;
}

void allocExternalDefault(char **buffer, ssize_t size) {
	*buffer = calloc(size, sizeof(char));
}

void deallocExternalDefault(char **buffer) {
	free(*buffer);
	*buffer = NULL;
}

- (BOOL)_processValueData:(BOOL (^)(const char *, ssize_t))process
			allocExternal:(void (^)(char **buffer, ssize_t size))allocExternal
		  deallocExternal:(void (^)(char **buffer))deallocExternal
			forCStringKey:(const char *)key
{
	int options = 0x00;
	char *buffer;
	
	__block char *dynamic = NULL;

	char fixed[VALUE_BUFFER_DEFAULT_SIZE];
	__block ssize_t size = VALUE_BUFFER_DEFAULT_SIZE;
	
	BOOL (^resizeExternal)(void) = ^{
		// Request the size.
		size = fgetxattr(self->_fd, key, NULL, 0, 0, options);
		
		if (size != -1) {
			// Increase buffer size.
			if (allocExternal) {
				allocExternal(&dynamic, size);
			}
			else {
				allocExternalDefault(&dynamic, size);
			}
			
			return YES;
		}
		
		return NO;
	};
	
	if (allocExternal) {
		// Request pre-allocated space, if not using the `fixed` internal buffer.
		resizeExternal();
	}
	
	BOOL success = NO;
	
	do { // Repeat in case the buffer size needs to increase…
		BOOL useDynamic = dynamic != NULL;
		buffer = useDynamic ? dynamic : (char *)&fixed;
		
		errno = 0;
		size = fgetxattr(_fd, key, buffer, size, 0, options);
		int errorCode = errno;
		
		if (size != -1) {
			// Success.
			success = process(buffer, size);
			break;
		}
		
		if (errorCode == ERANGE) {
			BOOL didResize = resizeExternal();
			if (didResize) {
				continue;
			}
		}
		
		// We don’t have a strategy implemented for recovering from this failure.
		break;
	} while (1);
	
	if (dynamic) {
		if (deallocExternal) {
			deallocExternal(&dynamic);
		}
		else {
			deallocExternalDefault(&dynamic);
		}
	}
	
	return success;
}

- (NSData *)_valueDataForCStringKey:(const char *)key
{
	__block NSData *data = nil;
	
	[self _processValueData:^BOOL(const char *bytes, ssize_t size) {
		if (data == nil) {
			// This shouldn’t be reached as the `allocExternal` block should always be called.
			data = [NSData dataWithBytes:bytes length:size];
		}
		
		return YES;
	}
			  allocExternal:^(char **buffer, ssize_t size) {
		NSMutableData *mutableData = nil;
		
		if (data) {
			// From previous `allocExternal` call. Reuse.
			mutableData = (NSMutableData *)data;
		}
		else {
			mutableData = [NSMutableData dataWithCapacity:size];
		}
		
		mutableData.length = size;
		*buffer = (char *)mutableData.mutableBytes;
		
		data = mutableData;
	}
			deallocExternal:^(char **buffer) {
		// Do nothing. We want to keep `data` allocated and filled as it is.
	}
			  forCStringKey:key];
	
	return data;
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
}

- (instancetype)initWithURL:(NSURL *)theURL;
{
	if (theURL.fileURL || [theURL isFileReferenceURL]) {
		return [self initWithFile:theURL.path];
	}
	else {
		return nil;
	}
}

- (instancetype)initWithFile:(NSString *)path
{
	if ((self = [super init])) {
		_fd = open(path.fileSystemRepresentation, O_RDONLY, 0);
		if (_fd < 0) {
			//NSLog(@"Err: Unable to open file");
			return nil;
		}
	}
	return self;
}

- (BOOL)removeAllData
{
	BOOL success =
	[self _processAttributeListData:^BOOL(const char *bytes, ssize_t size) {
		int options = 0x00;
		const char *key;
		const char *start = bytes;
		
		for (key = start; (key - start) < size; key += strlen(key) + 1) {
			int ret = fremovexattr(self->_fd, key, options);
			if (ret != 0) {
				return NO;
			}
		}
		
		return YES;
	}];
	
	return success;
}


#define xattrKeynameCStringForNSStringKeyWithErrorReturnValue(keyname, key, errorReturnValue)	\
	char keyname[XATTR_MAXNAMELEN_TERMINATED];\
	if ([key getCString:keyname maxLength:(XATTR_MAXNAMELEN_TERMINATED) encoding:NSUTF8StringEncoding] == NO)  return errorReturnValue;


- (BOOL)removeDataForKey:(NSString *)key
{
	if (key == nil || _fd == -1) {
		return NO;
	}
	
	int options = 0x00;
	
	xattrKeynameCStringForNSStringKeyWithErrorReturnValue(keyname, key, NO);
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
	
	xattrKeynameCStringForNSStringKeyWithErrorReturnValue(keyname, key, NO);
	int ret = fsetxattr(_fd, keyname, (const char *)value.bytes, value.length, 0, options);
	return ret == 0;
}

- (NSData *)dataForKey:(NSString *)key
{
	if (key == nil || _fd == -1) {
		return nil;
	}
	
	xattrKeynameCStringForNSStringKeyWithErrorReturnValue(keyname, key, nil);
	return [self _valueDataForCStringKey:keyname];
}

- (NSArray *)keys
{
	__block NSMutableArray *array = nil;
	
	BOOL success =
	[self _processAttributeListData:^BOOL(const char *bytes, ssize_t size) {
		array = [NSMutableArray array];
		
		const char *key;
		const char *start = bytes;
		
		for (key = start; (key - start) < size; key += strlen(key) + 1) {
			NSString *name = @(key);
			[array addObject:name];
		}
		
		return YES;
	}];
	
	if (!success) {
		return nil;
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
		CFStringEncoding cfEncoding = (CFStringEncoding)encodingNumberString.longLongValue;
		
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


static NSArray * _relevantKeysForIntent(NSArray *keys, xattr_operation_intent_t intent) API_AVAILABLE(macosx(10.10)) {
	// Filter keys by intent.
	NSIndexSet *irrelevantIndexes = [keys indexesOfObjectsPassingTest:^BOOL(NSString * _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
		xattrKeynameCStringForNSStringKeyWithErrorReturnValue(keyname, key, NO);
		BOOL relevantForComparison = (xattr_preserve_for_intent(keyname, intent) == 1);
		return (relevantForComparison == NO);
	}];
	
	NSMutableArray *relevantKeys = [keys mutableCopy];
	[relevantKeys removeObjectsAtIndexes:irrelevantIndexes];
	
	// Sort keys.
	[relevantKeys sortUsingSelector:@selector(compare:)];
	
	return relevantKeys;
}

- (BOOL)compare:(JXExtendedFileAttributes *)other withIntent:(xattr_operation_intent_t)intent;
{
	NSArray *selfKeys = _relevantKeysForIntent(self.keys, intent);
	NSArray *otherKeys = _relevantKeysForIntent(other.keys, intent);
	
	// Compare keys.
	if ([selfKeys isEqualToArray:otherKeys]) {
		BOOL equalValues = YES;
		// If all keys match, compare values.
		for (NSString *key in self.keys) {
			NSData *selfData = [self dataForKey:key];
			NSData *otherData = [other dataForKey:key];

			if ([selfData isEqualToData:otherData] == NO) {
				//NSLog(@"%@", selfData);
				//NSLog(@"%@", otherData);
				equalValues = NO;
				break;
			}
		}
		
		return equalValues;
	}
	else {
		//NSLog(@"%@", selfKeys);
		//NSLog(@"%@", otherKeys);
		return NO;
	}

	return NO;
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
	
	return string;
}

@end

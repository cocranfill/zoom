//
//  ZoomStoryID.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on Tue Jan 13 2004.
//  Copyright (c) 2004 Andrew Hunter. All rights reserved.
//

#import "ZoomStoryID.h"
#import "ZoomBlorbFile.h"

#include "ifmetabase.h"

@implementation ZoomStoryID

- (id) initWithZCodeStory: (NSData*) gameData {
	self = [super init];
	
	if (self) {
		const unsigned char* bytes = [gameData bytes];
		int length = [gameData length];
		
		if ([gameData length] < 64) {
			// Too little data for this to be a Z-Code file
			[self release];
			return nil;
		}

		if (bytes[0] == 'F' && bytes[1] == 'O' && bytes[2] == 'R' && bytes[3] == 'M') {
			// This is not a Z-Code file; it's possibly a blorb file, though
			
			// Try to interpret as a blorb file
			ZoomBlorbFile* blorbFile = [[ZoomBlorbFile alloc] initWithData: gameData];
			
			if (blorbFile == nil) {
				[self release];
				return nil;
			}
			
			// See if we can get the ZCOD chunk
			NSData* data = [blorbFile dataForChunkWithType: @"ZCOD"];
			if (data == nil) {
				[blorbFile release];
				[self release];
				return nil;
			}
			
			if ([data length] < 64) {
				// This file is too short to be a Z-Code file
				[blorbFile release];
				[self release];
				return nil;
			}
			
			// Change to using the blorb data instead
			bytes = [[[data retain] autorelease] bytes];
			length = [data length];
			[blorbFile release];
		}
		
		// Interpret the Z-Code data into an identification
		needsFreeing = YES;
		ident = IFMB_ZcodeId((((int)bytes[0x2])<<8)|((int)bytes[0x3]),
							 bytes + 0x12,
							 (((int)bytes[0x1c])<<8)|((int)bytes[0x1d]));
		
		// Scan for the string 'UUID://' - use this as an ident for preference if it exists (and represents a valid UUID)
		int x;
		BOOL gotUUID = NO;
		
		for (x=0; x<length-48; x++) {
			if (bytes[x] == 'U' && bytes[x+1] == 'U' && bytes[x+2] == 'I' && bytes[x+3] == 'D' &&
				bytes[x+4] == ':' && bytes[x+5] == '/' && bytes[x+6] == '/') {
				// This might be a UUID section
				char uuidText[49];
				
				// Check to see if we've got a UUID
				int y;
				int digitCount = 0;
				gotUUID = YES;
				
				for (y=0; y<7; y++) uuidText[y] = bytes[x+y];
				for (y=7; y<48; y++) {
					uuidText[y] = bytes[x+y];
					
					if (bytes[x+y-1] == '/' && bytes[x+y] == '/') break;
					if (bytes[x+y] == '-' || bytes[x+y] == '/') continue;
					if ((bytes[x+y] >= '0' && bytes[x+y] <= '9') ||
						(bytes[x+y] >= 'a' && bytes[x+y] <= 'f') ||
						(bytes[x+y] >= 'A' && bytes[x+y] <= 'F')) {
						digitCount++;
						continue;
					}
					
					gotUUID = NO;
					break;
				}
				
				if (gotUUID) {
					IFID uuidId = IFMB_IdFromString(uuidText);
					
					if (uuidId == NULL) {
						gotUUID = false;
					} else {
						IFMB_FreeId(ident);
						ident = uuidId;
					}
				}

				if (gotUUID) break;
			}
		}
	}
	
	return self;
}

- (id) initWithZCodeFile: (NSString*) zcodeFile {
	self = [super init];
	
	if (self) {
		const unsigned char* bytes;
		int length;
		
		NSFileHandle* fh = [NSFileHandle fileHandleForReadingAtPath: zcodeFile];
		NSData* data = [fh readDataToEndOfFile];
		[fh closeFile];
		
		if ([data length] < 64) {
			// This file is too short to be a Z-Code file
			[self release];
			return nil;
		}
		
		bytes = [data bytes];
		length = [data length];
		
		if (bytes[0] == 'F' && bytes[1] == 'O' && bytes[2] == 'R' && bytes[3] == 'M') {
			// This is not a Z-Code file; it's possibly a blorb file, though
						
			// Try to interpret as a blorb file
			ZoomBlorbFile* blorbFile = [[ZoomBlorbFile alloc] initWithContentsOfFile: zcodeFile];
			
			if (blorbFile == nil) {
				[self release];
				return nil;
			}
			
			// See if we can get the ZCOD chunk
			data = [blorbFile dataForChunkWithType: @"ZCOD"];
			if (data == nil) {
				[blorbFile release];
				[self release];
				return nil;
			}
			
			if ([data length] < 64) {
				// This file is too short to be a Z-Code file
				[blorbFile release];
				[self release];
				return nil;
			}
			
			// Change to using the blorb data instead
			bytes = [[[data retain] autorelease] bytes];
			length = [data length];
			[blorbFile release];
		}
		
		if (bytes[0] > 8) {
			// This cannot be a Z-Code file
			[self release];
			return nil;
		}
		
		// Interpret the Z-Code data into an identification
		needsFreeing = YES;
		ident = IFMB_ZcodeId((((int)bytes[0x2])<<8)|((int)bytes[0x3]),
							 bytes + 0x12,
							 (((int)bytes[0x1c])<<8)|((int)bytes[0x1d]));
		
		// Scan for the string 'UUID://' - use this as an ident for preference if it exists (and represents a valid UUID)
		int x;
		BOOL gotUUID = NO;
		
		for (x=0; x<length-48; x++) {
			if (bytes[x] == 'U' && bytes[x+1] == 'U' && bytes[x+2] == 'I' && bytes[x+3] == 'D' &&
				bytes[x+4] == ':' && bytes[x+5] == '/' && bytes[x+6] == '/') {
				// This might be a UUID section
				char uuidText[49];
				
				// Check to see if we've got a UUID
				int y;
				int digitCount = 0;
				gotUUID = YES;
				
				for (y=0; y<7; y++) uuidText[y] = bytes[x+y];
				for (y=7; y<48; y++) {
					uuidText[y] = bytes[x+y];
					
					if (bytes[x+y-1] == '/' && bytes[x+y] == '/') break;
					if (bytes[x+y] == '-' || bytes[x+y] == '/') continue;
					if ((bytes[x+y] >= '0' && bytes[x+y] <= '9') ||
						(bytes[x+y] >= 'a' && bytes[x+y] <= 'f') ||
						(bytes[x+y] >= 'A' && bytes[x+y] <= 'F')) {
						digitCount++;
						continue;
					}
					
					gotUUID = NO;
					break;
				}
				
				if (gotUUID) {
					IFID uuidId = IFMB_IdFromString(uuidText);
					
					if (uuidId == NULL) {
						gotUUID = false;
					} else {
						IFMB_FreeId(ident);
						ident = uuidId;
					}
				}
				
				if (gotUUID) break;
			}
		}
	}
	
	return self;
}

- (id) initWithData: (NSData*) genericGameData {
	self = [super init];
	
	if (self) {
		// IMPLEMENT ME: take MD5 of file
	}
	
	return self;
}

- (id) initWithIdent: (struct IFID*) idt {
	self = [super init];
	
	if (self) {
		ident = IFMB_CopyId(idt);
		needsFreeing = YES;
	}
	
	return self;
}

- (id) initWithZcodeRelease: (int) release
					 serial: (const unsigned char*) serial
				   checksum: (int) checksum {
	self = [super init];
	
	if (self) {
		ident = IFMB_ZcodeId(release, serial, checksum);
		needsFreeing = YES;
	}
	
	return self;
}

- (void) dealloc {
	if (needsFreeing) {
		IFMB_FreeId(ident);
	}
	
	[super dealloc];
}

- (struct IFID*) ident {
	return ident;
}

// = NSCopying =
- (id) copyWithZone: (NSZone*) zone {
	ZoomStoryID* newID = [[ZoomStoryID allocWithZone: zone] init];
	
	newID->ident = IFMB_CopyId(ident);
	newID->needsFreeing = YES;
	
	return newID;
}

// = NSCoding =
- (void)encodeWithCoder:(NSCoder *)encoder {
	// Version might change later on
	int version = 2;
	
	[encoder encodeValueOfObjCType: @encode(int) 
								at: &version];
	
	char* stringId = IFMB_IdToString(ident);
	NSString* stringIdent = [NSString stringWithUTF8String: stringId];
	[encoder encodeObject: stringIdent];
	free(stringId);
}

enum IFMDFormat {
	IFFormat_Unknown = 0x0,
	
	IFFormat_ZCode,
	IFFormat_Glulx,
	
	IFFormat_TADS,
	IFFormat_HUGO,
	IFFormat_Alan,
	IFFormat_Adrift,
	IFFormat_Level9,
	IFFormat_AGT,
	IFFormat_MagScrolls,
	IFFormat_AdvSys,
	
	IFFormat_UUID,			/* 'Special' format used for games identified by a UUID */
};

typedef unsigned char IFMDByte;

- (id)initWithCoder:(NSCoder *)decoder {
	self = [super init];
	
	if (self) {
		ident = NULL;
		needsFreeing = YES;
		
		// As above, but backwards
		int version;
		
		[decoder decodeValueOfObjCType: @encode(int) at: &version];
		
		if (version == 1) {
			// General stuff (data format, MD5, etc) [old v1 format used by versions of Zoom prior to 1.0.5dev3]
			char md5sum[16];
			IFMDByte usesMd5;
			enum IFMDFormat dataFormat;
			
			[decoder decodeValueOfObjCType: @encode(enum IFMDFormat) 
										at: &dataFormat];
			[decoder decodeValueOfObjCType: @encode(IFMDByte)
										at: &usesMd5];
			if (usesMd5) {
				[decoder decodeArrayOfObjCType: @encode(IFMDByte)
										 count: 16
											at: md5sum];
			}
			
			switch (dataFormat) {
				case IFFormat_ZCode:
				{
					char serial[6];
					int release;
					int checksum;
					
					[decoder decodeArrayOfObjCType: @encode(IFMDByte)
											 count: 6
												at: serial];
					[decoder decodeValueOfObjCType: @encode(int)
												at: &release];
					[decoder decodeValueOfObjCType: @encode(int)
												at: &checksum];
					
					ident = IFMB_ZcodeId(release, serial, checksum);
					break;
				}
					
				case IFFormat_UUID:
				{
					unsigned char uuid[16];
					
					[decoder decodeArrayOfObjCType: @encode(unsigned char)
											 count: 16
												at: uuid];
					ident = IFMB_UUID(uuid);
					break;
				}
					
				default:
					/* No other formats are supported yet */
					break;
			}		
		} else if (version == 2) {
			NSString* idString = (NSString*)[decoder decodeObject];
			
			ident = IFMB_IdFromString([idString UTF8String]);
		} else {
			// Only v1 and v2 decodes supported ATM
			[self release];
			
			NSLog(@"Tried to load a version %i ZoomStoryID (this version of Zoom supports only versions 1 and 2)", version);
			
			return nil;
		}
	}
	
	return self;
}

// = Hashing/comparing =
- (unsigned) hash {
	return [[self description] hash];
}

- (BOOL) isEqual: (id)anObject {
	if ([anObject isKindOfClass: [ZoomStoryID class]]) {
		ZoomStoryID* compareWith = anObject;
		
		if (IFMB_CompareIds(ident, [compareWith ident]) == 0) {
			return YES;
		} else {
			return NO;
		}
	} else {
		return NO;
	}
}

- (NSString*) description {
	char* stringId = IFMB_IdToString(ident);
	NSString* identString = [NSString stringWithUTF8String: stringId];
	free(stringId);
	
	return identString;
}

@end

//
//  ZoomStoryOrganiser.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on Thu Jan 22 2004.
//  Copyright (c) 2004 Andrew Hunter. All rights reserved.
//

#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>

#import <Cocoa/Cocoa.h>

#import "ZoomStoryOrganiser.h"
#import "ZoomAppDelegate.h"
#import "ZoomPreferences.h"

NSString* ZoomStoryOrganiserChangedNotification = @"ZoomStoryOrganiserChangedNotification";
NSString* ZoomStoryOrganiserProgressNotification = @"ZoomStoryOrganiserProgressNotification";

static NSString* defaultName = @"ZoomStoryOrganiser";
static NSString* extraDefaultsName = @"ZoomStoryOrganiserExtra";
static NSString* ZoomGameDirectories = @"ZoomGameDirectories";
static NSString* ZoomGameStorageDirectory = @"ZoomGameStorageDirectory";
static NSString* ZoomIdentityFilename = @".zoomIdentity";

@implementation ZoomStoryOrganiser

// = Internal functions =

- (NSDictionary*) dictionary {
	NSMutableDictionary* defaultDictionary = [NSMutableDictionary dictionary];
	
	NSEnumerator* filenameEnum = [filenamesToIdents keyEnumerator];
	NSString* filename;
	
	while (filename = [filenameEnum nextObject]) {
		NSData* encodedId = [NSArchiver archivedDataWithRootObject: [filenamesToIdents objectForKey: filename]];
		
		[defaultDictionary setObject: encodedId
							  forKey: filename];
	}
		
	return defaultDictionary;
}

- (NSDictionary*) extraDictionary {
	return [NSDictionary dictionary];
}

- (void) storePreferences {
	[[NSUserDefaults standardUserDefaults] setObject:[self dictionary] 
											  forKey:defaultName];
	[[NSUserDefaults standardUserDefaults] setObject:[self extraDictionary] 
											  forKey:extraDefaultsName];
}

- (void) preferenceThread: (NSDictionary*) threadDictionary {
	NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
	NSDictionary* prefs = [threadDictionary objectForKey: @"preferences"];
	//NSDictionary* prefs2 = [threadDictionary objectForKey: @"extraPreferences"]; - unused, presently
	
	int counter = 0;
	
	// Connect to the main thread
	[[NSRunLoop currentRunLoop] addPort: port2
                                forMode: NSDefaultRunLoopMode];
	subThread = [[NSConnection allocWithZone: [self zone]]
        initWithReceivePort: port2
                   sendPort: port1];
	[subThread setRootObject: self];
	
	// Notify the main thread that things are happening
	[(ZoomStoryOrganiser*)[subThread rootProxy] startedActing];
			
	// Preference keys indicate the filenames
	NSEnumerator* filenameEnum = [prefs keyEnumerator];
	NSString* filename;
	
	while (filename = [filenameEnum nextObject]) {
		NSData* storyData = [prefs objectForKey: filename];
		ZoomStoryID* fileID = [NSUnarchiver unarchiveObjectWithData: storyData];
		ZoomStoryID* realID = [[ZoomStoryID alloc] initWithZCodeFile: filename];
		
		if (fileID != nil && realID != nil && [fileID isEqual: realID]) {
			// Check for a pre-existing entry
			[storyLock lock];
			
			NSString* oldFilename;
			ZoomStoryID* oldIdent;
			
			oldFilename = [identsToFilenames objectForKey: fileID];
			oldIdent = [filenamesToIdents objectForKey: filename];
			
			if (oldFilename && oldIdent && [oldFilename isEqualToString: filename] && [oldIdent isEqualTo: fileID]) {
				[storyLock unlock];
				continue;
			}
			
			// Remove old entries
			if (oldFilename) {
				[identsToFilenames removeObjectForKey: fileID];
				[storyFilenames removeObject: oldFilename];
			}
			
			if (oldIdent) {
				[filenamesToIdents removeObjectForKey: filename];
				[storyIdents removeObject: oldIdent];
			}
			
			// Add this entry
			NSString* newFilename = [[filename copy] autorelease];
			NSString* newIdent    = [[fileID copy] autorelease];
			
			[storyFilenames addObject: newFilename];
			[storyIdents addObject: newIdent];
			
			[identsToFilenames setObject: newFilename forKey: newIdent];
			[filenamesToIdents setObject: newIdent forKey: newFilename];
			
			[storyLock unlock];
		}
		
		[realID release];
		
		counter++;
		if (counter > 40) {
			counter = 0;
			[(ZoomStoryOrganiser*)[subThread rootProxy] organiserChanged];
		}
	}	
	
	[(ZoomStoryOrganiser*)[subThread rootProxy] organiserChanged];
	
	// If story organisation is on, we need to check for any disappeared stories that have appeared in
	// the organiser directory, and recreate any story data as required.
	//
	// REMEMBER: this is not the main thread! Don't make bad things happen!
	if ([[ZoomPreferences globalPreferences] keepGamesOrganised]) {
		// Directory scanning time. NSFileManager is not thread-safe, so we use opendir instead
		// (Yup, pain in the neck)
		NSString* orgDir = [[ZoomPreferences globalPreferences] organiserDirectory];
		DIR* orgD = opendir([orgDir UTF8String]);
		struct dirent* ent;
		
		while (orgD && (ent = readdir(orgD))) {
			NSString* groupName = [NSString stringWithUTF8String: ent->d_name];
			
			// Don't really want to iterate these
			if ([groupName isEqualToString: @".."] ||
				[groupName isEqualToString: @"."]) {
				continue;
			}
			
			// Must be a directory
			if (ent->d_type != DT_DIR) continue;
			
			// Iterate through the files in this directory
			NSString* newDir = [orgDir stringByAppendingPathComponent: groupName];
			
			DIR* groupD = opendir([newDir UTF8String]);
			struct dirent* gEnt;
			
			while (groupD && (gEnt = readdir(groupD))) {
				NSString* gameName = [NSString stringWithUTF8String: gEnt->d_name];
				
				// Don't really want to iterate these
				if ([gameName isEqualToString: @".."] ||
					[gameName isEqualToString: @"."]) {
					continue;
				}
				
				// Must be a directory
				if (gEnt->d_type != DT_DIR) continue;
				
				// See if there's a game.z5 there
				NSString* gameDir = [newDir stringByAppendingPathComponent: gameName];
				NSString* gameFile = [gameDir stringByAppendingPathComponent: @"game.z5"];
				
				struct stat sb;
				if (stat([gameFile UTF8String], &sb) != 0) continue;
				
				// See if it's already in our database
				[storyLock lock];
				ZoomStoryID* fileID = [filenamesToIdents objectForKey: gameFile];
				
				if (fileID == nil) {
					// Pass this off to the main thread
					[self performSelectorOnMainThread: @selector(foundFileNotInDatabase:)
										   withObject: [NSArray arrayWithObjects: groupName, gameName, gameFile, nil]
										waitUntilDone: NO];
				}
				[storyLock unlock];
			}
			
			if (groupD) closedir(groupD);
		}
		
		if (orgD) closedir(orgD);
	}

	[(ZoomStoryOrganiser*)[subThread rootProxy] organiserChanged];

	// Tidy up
	[(ZoomStoryOrganiser*)[subThread rootProxy] endedActing];

	[subThread release];
	[port1 release];
	[port2 release];

	subThread = nil;
	port1 = port2 = nil;
	
	// Done
	[threadDictionary release];
	[self release];
	
	// Clear the pool
	[p release];
}

- (void) loadPreferences {
	NSDictionary* prefs = [[NSUserDefaults standardUserDefaults] objectForKey: defaultName];
	NSDictionary* extraPrefs = [[NSUserDefaults standardUserDefaults] objectForKey: defaultName];
	
	// Detach a thread to decode the dictionary
	NSDictionary* threadDictionary =
		[[NSDictionary dictionaryWithObjectsAndKeys:
			prefs, @"preferences",
			extraPrefs, @"extraPreferences",
			nil] retain];
	
	// Create a connection so the threads can communicate
	port1 = [[NSPort port] retain];
	port2 = [[NSPort port] retain];
	
	mainThread = [[NSConnection allocWithZone: [self zone]]
		initWithReceivePort: port1
                   sendPort: port2];
	[mainThread setRootObject: self];
	
	// Run the thread
	[self retain]; // Released by the thread when it finishes
	[NSThread detachNewThreadSelector: @selector(preferenceThread:)
							 toTarget: self
						   withObject: threadDictionary];
}

- (void) organiserChanged {
	[self storePreferences];
	
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryOrganiserChangedNotification
														object: self];
}

- (void) foundFileNotInDatabase: (NSArray*) info {
	// Called from the preferenceThread when a story not in the database is found
	NSString* groupName = [info objectAtIndex: 0];
	NSString* gameName = [info objectAtIndex: 1];
	NSString* gameFile = [info objectAtIndex: 2];
	
	static BOOL loggedNote = NO;
	if (!loggedNote) {
		loggedNote = YES;
	}
	
	// Check for story metadata first
	ZoomStoryID* newID = [[[ZoomStoryID alloc] initWithZCodeFile: gameFile] autorelease];
	
	if (newID == nil) {
		NSLog(@"Found unindexed game at %@, but failed to obtain an ID. Not indexing");
		return;
	}
	
	ZoomMetadata* data = [[NSApp delegate] userMetadata];	
	ZoomStory* oldStory = [[NSApp delegate] findStory: newID];
	
	if (oldStory == nil) {
		NSLog(@"Creating metadata entry for story '%@'", gameName);
		
		ZoomStory* newStory = [[ZoomStory alloc] init];
		
		[newStory setTitle: gameName];
		if (![groupName isEqualToString: @"Ungrouped"]);
		[newStory setGroup: groupName];
		[newStory addID: newID];
		
		[data storeStory: newStory];
	} else {
		NSLog(@"Found metadata for story '%@'", gameName);
	}
	
	// Now store with us
	[self addStory: gameFile
		 withIdent: newID
		  organise: NO];
}

// = Initialisation =

+ (void) initialize {
	// User defaults
    NSUserDefaults *defaults  = [NSUserDefaults standardUserDefaults];
	ZoomStoryOrganiser* defaultPrefs = [[[[self class] alloc] init] autorelease];
	
		NSArray* libraries = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString* libraryDir = [[libraries objectAtIndex: 0] stringByAppendingPathComponent: @"Interactive Fiction"];
	
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys: [defaultPrefs dictionary], defaultName,
		libraryDir, ZoomGameStorageDirectory, nil];
	
    [defaults registerDefaults: appDefaults];	
}

- (id) init {
	self = [super init];
	
	if (self) {
		storyFilenames = [[NSMutableArray alloc] init];
		storyIdents = [[NSMutableArray alloc] init];
		
		filenamesToIdents = [[NSMutableDictionary alloc] init];
		identsToFilenames = [[NSMutableDictionary alloc] init];
		
		storyLock = [[NSLock alloc] init];
		port1 = nil;
		port2 = nil;
		mainThread = nil;
		subThread = nil;
		
		// Any time a story changes, we move it
		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(someStoryHasChanged:)
													 name: ZoomStoryDataHasChangedNotification
												   object: nil];
	}
	
	return self;
}

- (void) dealloc {
	[storyFilenames release];
	[storyIdents release];
	[filenamesToIdents release];
	[identsToFilenames release];
	
	[storyLock release];
	[port1 release];
	[port2 release];
	[mainThread release];
	[subThread release];
	
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	
	[super dealloc];
}

// = The shared organiser =

static ZoomStoryOrganiser* sharedOrganiser = nil;

+ (ZoomStoryOrganiser*) sharedStoryOrganiser {
	if (!sharedOrganiser) {
		sharedOrganiser = [[ZoomStoryOrganiser alloc] init];
		[sharedOrganiser loadPreferences];
	}
	
	return sharedOrganiser;
}

// = Storing stories =

- (void) addStory: (NSString*) filename
		withIdent: (ZoomStoryID*) ident {
	[self addStory: filename
		 withIdent: ident
		  organise: NO];
}

- (void) removeStoryWithIdent: (ZoomStoryID*) ident {
	[storyLock lock];
	
	NSString* filename = [identsToFilenames objectForKey: ident];
	
	if (filename != nil) {
		[filenamesToIdents removeObjectForKey: filename];
		[identsToFilenames removeObjectForKey: ident];
		[storyIdents removeObjectIdenticalTo: ident];
		[storyFilenames removeObject: filename];
	}
	
	[storyLock unlock];
	[self organiserChanged];
}

- (void) addStory: (NSString*) filename
		withIdent: (ZoomStoryID*) ident
		 organise: (BOOL) organise {	
	[storyLock lock];
	
	NSString* oldFilename;
	ZoomStoryID* oldIdent;
	
	oldFilename = [identsToFilenames objectForKey: ident];
	oldIdent = [filenamesToIdents objectForKey: oldFilename];
	
	if (organise) {
		ZoomStory* theStory = [[NSApp delegate] findStory: ident];
		
		// If there's no story registered, then we need to create one
		if (theStory == nil) {
			theStory = [[ZoomStory alloc] init];
			
			[theStory addID: ident];
			[theStory setTitle: [[filename lastPathComponent] stringByDeletingPathExtension]];
			
			[[[NSApp delegate] userMetadata] storeStory: [theStory autorelease]];
			[[[NSApp delegate] userMetadata] writeToDefaultFile];
		}

		// Copy to a standard directory, change the filename we're using
		filename = [filename stringByStandardizingPath];
		
		NSString* fileDir = [self directoryForIdent: ident create: YES];
		NSString* destFile = [fileDir stringByAppendingPathComponent: @"game.z5"];
		destFile = [destFile stringByStandardizingPath];
		
		if (![filename isEqualToString: destFile]) {
			[[NSFileManager defaultManager] removeFileAtPath: destFile handler: nil];
			if ([[NSFileManager defaultManager] copyPath: filename
												  toPath: destFile
												 handler: nil]) {
				filename = destFile;
			} else {
				NSLog(@"Warning: couldn't copy '%@' to '%@'", filename, destFile);
			}
		}
	}
	
	if (oldFilename && oldIdent && [oldFilename isEqualToString: filename] && [oldIdent isEqualTo: ident]) {
		// Nothing to do
		[storyLock unlock];
		return;
	}
	
	if (oldFilename) {
		[identsToFilenames removeObjectForKey: ident];
		[filenamesToIdents removeObjectForKey: oldFilename];
		[storyFilenames removeObject: oldFilename];
	}

	if (oldIdent) {
		[filenamesToIdents removeObjectForKey: filename];
		[identsToFilenames removeObjectForKey: oldIdent];
		[storyIdents removeObject: oldIdent];
	}
	
	[filenamesToIdents removeObjectForKey: filename];
	[identsToFilenames removeObjectForKey: ident];
	
	NSString* newFilename = [[filename copy] autorelease];
	NSString* newIdent    = [[ident copy] autorelease];
		
	[storyFilenames addObject: newFilename];
	[storyIdents addObject: newIdent];
	
	[identsToFilenames setObject: newFilename forKey: newIdent];
	[filenamesToIdents setObject: newIdent forKey: newFilename];
	
	[storyLock unlock];
	[self organiserChanged];
}

// = Progress =
- (void) startedActing {
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryOrganiserProgressNotification
														object: self
													  userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
														  [NSNumber numberWithBool: YES], @"ActionStarting",
														  nil]];
}

- (void) endedActing {
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryOrganiserProgressNotification
														object: self
													  userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
														  [NSNumber numberWithBool: NO], @"ActionStarting",
														  nil]];
}

// = Retrieving story information =

- (NSString*) filenameForIdent: (ZoomStoryID*) ident {
	NSString* res;
	
	[storyLock lock];
	res = [[[identsToFilenames objectForKey: ident] retain] autorelease];
	[storyLock unlock];
	
	return res;
}

- (ZoomStoryID*) identForFilename: (NSString*) filename {
	ZoomStoryID* res;
		
	[storyLock lock];
	res = [[[filenamesToIdents objectForKey: filename] retain] autorelease];
	[storyLock unlock];
	
	return res;
}

- (NSArray*) storyFilenames {
	return [[storyFilenames copy] autorelease];
}

- (NSArray*) storyIdents {
	return [[storyIdents copy] autorelease];
}

// = Story-specific data =

- (NSString*) preferredDirectoryForIdent: (ZoomStoryID*) ident {
	// The preferred directory is defined by the story group and title
	// (Ungrouped/untitled if there is no story group/title)

	// TESTME: what does stringByAppendingPathComponent do in the case where the group/title
	// contains a '/' or other evil character?
	NSString* confDir = [[NSUserDefaults standardUserDefaults] objectForKey: ZoomGameStorageDirectory];
	ZoomStory* theStory = [[NSApp delegate] findStory: ident];
	
	confDir = [confDir stringByAppendingPathComponent: [theStory group]];
	confDir = [confDir stringByAppendingPathComponent: [theStory title]];
	
	return confDir;
}

- (BOOL) directory: (NSString*) dir
		 isForGame: (ZoomStoryID*) ident {
	// If the preferences get corrupted or something similarily silly happens,
	// we want to avoid having games point to the wrong directories. This
	// routine checks that a directory belongs to a particular game.
	BOOL isDir;
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: dir
											  isDirectory: &isDir]) {
		// Corner case
		return YES;
	}
	
	if (!isDir) // Files belong to no game
		return NO;
	
	NSString* idFile = [dir stringByAppendingPathComponent: ZoomIdentityFilename];
	if (![[NSFileManager defaultManager] fileExistsAtPath: idFile
											  isDirectory: &isDir]) {
		// Directory has no identification
		return NO;
	}
	
	if (isDir) // Identification must be a file
		return NO;
	
	ZoomStoryID* owner = [NSUnarchiver unarchiveObjectWithFile: idFile];
	
	if (owner && [owner isKindOfClass: [ZoomStoryID class]] && [owner isEqual: ident])
		return YES;
	
	// Directory belongs to some other game
	return NO;
}

- (NSString*) findDirectoryForIdent: (ZoomStoryID*) ident
					  createGameDir: (BOOL) createGame
					 createGroupDir: (BOOL) createGroup {
	// Assuming a story doesn't already have a directory, find (and possibly create)
	// a directory for it
	BOOL isDir;
	
	ZoomStory* theStory = [[NSApp delegate] findStory: ident];
	NSString* group = [theStory group];
	NSString* title = [theStory title];
	
	if (group == nil || [group isEqualToString: @""])
		group = @"Ungrouped";
	if (title == nil || [title isEqualToString: @""])
		title = @"Untitled";
	
	// Find the root directory
	NSString* rootDir = [[NSUserDefaults standardUserDefaults] objectForKey: ZoomGameStorageDirectory];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: rootDir
											  isDirectory: &isDir]) {
		if (createGroup) {
			[[NSFileManager defaultManager] createDirectoryAtPath: rootDir
													   attributes: nil];
			isDir = YES;
		} else {
			return nil;
		}
	}
	
	if (!isDir) {
		static BOOL warned = NO;
		
		if (!warned)
			NSRunAlertPanel([NSString stringWithFormat: @"Game library not found"],
							[NSString stringWithFormat: @"Warning: %@ is a file", rootDir], 
							@"OK", nil, nil);
		warned = YES;
		return nil;
	}
	
	// Find the group directory
	NSString* groupDir = [rootDir stringByAppendingPathComponent: group];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: groupDir
											  isDirectory: &isDir]) {
		if (createGroup) {
			[[NSFileManager defaultManager] createDirectoryAtPath: groupDir
													   attributes: nil];
			isDir = YES;
		} else {
			return nil;
		}
	}
	
	if (!isDir) {
		static BOOL warned = NO;
		
		if (!warned)
			NSRunAlertPanel([NSString stringWithFormat: @"Group directory not found"],
							[NSString stringWithFormat: @"Warning: %@ is a file", groupDir], 
							@"OK", nil, nil);
		warned = YES;
		return nil;
	}
	
	// Now the game directory
	NSString* gameDir = [groupDir stringByAppendingPathComponent: title];
	int number = 0;
	const int maxNumber = 20;
	
	while (![self directory: gameDir 
				  isForGame: ident] &&
		   number < maxNumber) {
		number++;
		gameDir = [groupDir stringByAppendingPathComponent: [NSString stringWithFormat: @"%@ %i", title, number]];
	}
	
	if (number >= maxNumber) {
		static BOOL warned = NO;
		
		if (!warned)
			NSRunAlertPanel([NSString stringWithFormat: @"Game directory not found"],
							[NSString stringWithFormat: @"Zoom was unable to locate a directory for the game '%@'", title], 
							@"OK", nil, nil);
		warned = YES;
		return nil;
	}
	
	// Create the directory if necessary
	if (![[NSFileManager defaultManager] fileExistsAtPath: gameDir
											  isDirectory: &isDir]) {
		if (createGame) {
			[[NSFileManager defaultManager] createDirectoryAtPath: gameDir
													   attributes: nil];
		} else {
			if (createGroup) {
				// Special case, really. Sometimes we need to know where we're going to move the game to
				return gameDir;
			} else {
				return nil;
			}
		}
	}
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: gameDir
											  isDirectory: &isDir] || !isDir) {
		// Chances of reaching here should have been eliminated previously
		return nil;
	}
	
	// Create the identifier file
	NSString* identityFile = [gameDir stringByAppendingPathComponent: ZoomIdentityFilename];
	[NSArchiver archiveRootObject: ident
						   toFile: identityFile];
	
	/* -- Not used here
	// Store this directory as the dir for this game
	NSMutableDictionary* newGameDirs = [gameDirs mutableCopy];
	
	if (newGameDirs == nil) {
		newGameDirs = [[NSMutableDictionary alloc] init];
	}
	
	[newGameDirs setObject: gameDir
					forKey: [ident description]];
	[defaults setObject: [newGameDirs autorelease]
				 forKey: ZoomGameDirectories];
	 */
	
	return gameDir;
}

- (NSString*) directoryForIdent: (ZoomStoryID*) ident
						 create: (BOOL) create {
	NSString* confDir = nil;
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		
	// If there is a directory in the preferences, then that's the directory to use
	NSDictionary* gameDirs = [defaults objectForKey: ZoomGameDirectories];
	
	if (gameDirs)
		confDir = [gameDirs objectForKey: [ident description]];

	BOOL isDir;
	if (![[NSFileManager defaultManager] fileExistsAtPath: confDir
											  isDirectory: &isDir]) {
		confDir = nil;
	}
	
	if (!isDir)
		confDir = nil;
	
	if (confDir && [self directory: confDir isForGame: ident])
		return confDir;
	
	confDir = nil;
	
	NSString* gameDir = [self findDirectoryForIdent: ident
									  createGameDir: create
									 createGroupDir: create];
	
	if (gameDir == nil) return nil;
		
	// Store this directory as the dir for this game
	NSMutableDictionary* newGameDirs = [gameDirs mutableCopy];

	if (newGameDirs == nil) {
		newGameDirs = [[NSMutableDictionary alloc] init];
	}

	[newGameDirs setObject: gameDir
					forKey: [ident description]];
	[defaults setObject: [newGameDirs autorelease]
				 forKey: ZoomGameDirectories];
	
	return gameDir;
}

- (BOOL) moveStoryToPreferredDirectoryWithIdent: (ZoomStoryID*) ident {
	// Get the current directory
	NSString* currentDir = [self directoryForIdent: ident 
											create: NO];
	currentDir = [currentDir stringByStandardizingPath];
	
	if (currentDir == nil) return NO;
	
	// Get the 'ideal' directory
	NSString* idealDir = [self findDirectoryForIdent: ident
									   createGameDir: NO
									  createGroupDir: YES];
	idealDir = [idealDir stringByStandardizingPath];
	
	// See if they already match
	if ([idealDir isEqualToString: currentDir]) 
		return YES;
	
	// If they don't match, then idealDir should be new (or something weird has just occured)
	if ([[NSFileManager defaultManager] fileExistsAtPath: idealDir]) {
		// Doh!
		NSLog(@"Wanted to move game from '%@' to '%@', but '%@' already exists", currentDir, idealDir, idealDir);
		return NO;
	}
	
	// Move the old directory to the new directory
	
	// Vague possibilities of this failing: in particular, currentDir may be not write-accessible or
	// something might appear there between our check and actually moving the directory	
	if (![[NSFileManager defaultManager] movePath: currentDir
										  toPath: idealDir
										 handler: nil]) {
		NSLog(@"Failed to move '%@' to '%@'", currentDir, idealDir);
		return NO;
	}
	
	// Success: store the new directory in the defaults
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
	NSDictionary* gameDirs = [defaults objectForKey: ZoomGameDirectories];
	if (gameDirs == nil) gameDirs = [NSDictionary dictionary];
	NSMutableDictionary* newGameDirs = [gameDirs mutableCopy];
	
	if (newGameDirs == nil) {
		newGameDirs = [[NSMutableDictionary alloc] init];
	}
	
	[newGameDirs setObject: idealDir
					forKey: [ident description]];
	[defaults setObject: [newGameDirs autorelease]
				 forKey: ZoomGameDirectories];	
	
	return YES;
}

- (void) someStoryHasChanged: (NSNotification*) not {
	ZoomStory* story = [not object];
	
	if (![story isKindOfClass: [ZoomStory class]]) {
		NSLog(@"someStoryHasChanged: called with a non-story object (too many spoons?)");
		return; // Unlikely but possible. If I'm a spoon, that is.
	}
	
	// De and requeue this to be done next time through the run loop
	// (stops this from being performed multiple times when many story parameters are updated together)
	[[NSRunLoop currentRunLoop] cancelPerformSelector: @selector(finishChangingStory:)
											   target: self
											 argument: story];
	[[NSRunLoop currentRunLoop] performSelector: @selector(finishChangingStory:)
										 target: self
									   argument: story
										  order: 128
										  modes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
}

- (void) finishChangingStory: (ZoomStory*) story {
	// For our pre-arranged stories, several IDs are possible, but more usually one
	NSEnumerator* identEnum = [[story storyIDs] objectEnumerator];
	ZoomStoryID* ident;
	BOOL changed = NO;
	
	while (ident = [identEnum nextObject]) {
		int identID = [storyIdents indexOfObject: ident];
		
		if (identID != NSNotFound) {
			// Get the old location of the game
			ZoomStoryID* realID = [storyIdents objectAtIndex: identID];
			
			NSString* oldGameFile = [self directoryForIdent: ident create: NO];
			oldGameFile = [oldGameFile stringByAppendingPathComponent: @"game.z5"];
			NSString* oldGameLoc = [storyFilenames objectAtIndex: identID];
			
			oldGameFile = [oldGameFile stringByStandardizingPath];
			oldGameLoc = [oldGameLoc stringByStandardizingPath];

			// Actually perform the move
			if ([self moveStoryToPreferredDirectoryWithIdent: [storyIdents objectAtIndex: identID]]) {
				changed = YES;
			
				// Store the new location of the game, if necessary
				if ([oldGameLoc isEqualToString: oldGameFile]) {
					NSString* newGameFile = [[self directoryForIdent: ident create: NO] stringByAppendingPathComponent: @"game.z5"];
					newGameFile = [newGameFile stringByStandardizingPath];

					if (![oldGameFile isEqualToString: newGameFile]) {
						[filenamesToIdents removeObjectForKey: oldGameFile];
						
						[filenamesToIdents setObject: realID
											  forKey: newGameFile];
						[identsToFilenames setObject: newGameFile
											  forKey: realID];
						
						[storyFilenames replaceObjectAtIndex: identID
												  withObject: newGameFile];
					}
				}
			}
		}
	}
	
	if (changed)
		[self organiserChanged];
}

// = Reorganising stories =

- (void) organiseStory: (ZoomStory*) story
			 withIdent: (ZoomStoryID*) ident {
	NSString* filename = [self filenameForIdent: ident];
	
	if (filename == nil) {
		NSLog(@"WARNING: Attempted to organise a story with no filename");
		return;
	}
		
	NSString* oldFilename = [[filename retain] autorelease];
	
	// Copy to a standard directory, change the filename we're using
	filename = [filename stringByStandardizingPath];
		
	NSString* fileDir = [self directoryForIdent: ident create: YES];
	NSString* destFile = [fileDir stringByAppendingPathComponent: @"game.z5"];
	destFile = [destFile stringByStandardizingPath];
		
	if (![filename isEqualToString: destFile]) {
		[[NSFileManager defaultManager] removeFileAtPath: destFile handler: nil];
		if ([[NSFileManager defaultManager] copyPath: filename
											  toPath: destFile
											 handler: nil]) {
			filename = destFile;
		} else {
			NSLog(@"Warning: couldn't copy '%@' to '%@'", filename, destFile);
		}
	}
	
	// Update the indexes
	[identsToFilenames setObject: filename
						  forKey: ident];
	[filenamesToIdents removeObjectForKey: oldFilename];
	[filenamesToIdents setObject: ident
						  forKey: filename];
	
	// Organise the story's resources
	NSString* resources = [story objectForKey: @"ResourceFilename"];
	if (resources != nil && [[NSFileManager defaultManager] fileExistsAtPath: resources]) {
		NSString* dir = [self directoryForIdent: ident
										 create: NO];
		BOOL exists, isDir;
		NSFileManager* fm = [NSFileManager defaultManager];
		
		if (dir == nil) {
			NSLog(@"No organised directory for game: cannot store resources");
			return;
		}
		
		exists = [fm fileExistsAtPath: dir
						  isDirectory: &isDir];
		if (!exists || !isDir) {
			NSLog(@"Organised directory for game does not exist");
			return;
		}
		
		NSString* newFile = [dir stringByAppendingPathComponent: @"resource.blb"];
		
		if (![fm copyPath: resources
				   toPath: newFile
				  handler: nil]) {
			NSLog(@"Unable to copy resource file to new location");
		} else {
			resources = newFile;
		}
		
		[story setObject: resources
				  forKey: @"ResourceFilename"];
	} else {
		[story setObject: nil
				  forKey: @"ResourceFilename"];
	}
}

- (void) organiseStory: (ZoomStory*) story {
	NSEnumerator* idEnum = [[story storyIDs] objectEnumerator];
	ZoomStoryID* thisID;
	BOOL organised = NO;
	
	while (thisID = [idEnum nextObject]) {
		NSString* filename = [self filenameForIdent: thisID];
		
		if (filename != nil) {
			[self organiseStory: story
					  withIdent: thisID];
			organised = YES;
		}
	}
	
	if (!organised) {
		NSLog(@"WARNING: attempted to organise story with no IDs");
	}
}

- (void) organiseAllStories {
	// Forces an organisation of all the stories stored in the database.
	// This is useful if, for example, the 'keep games organised' option is switched on/off
	
	// Create the ports for the thread
	NSPort* threadPort1 = [NSMachPort port];
	NSPort* threadPort2 = [NSMachPort port];
	
	[[NSRunLoop currentRunLoop] addPort: threadPort1
								forMode: NSDefaultRunLoopMode];
	
	// Create the information dictionary
	NSDictionary* threadDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
		threadPort1, @"threadPort1",
		threadPort2, @"threadPort2",
		nil];
	
	[storyLock lock];
	if (alreadyOrganising) {
		NSLog(@"ZoomStoryOrganiser: organiseAllStories called while Zoom was already in the process of organising");
		[storyLock unlock];
		return;
	}
	
	alreadyOrganising = YES;
	
	// Run a separate thread to do (some of) the work
	[self retain]; // Released by the thread when it finishes
	[NSThread detachNewThreadSelector: @selector(organiserThread:)
							 toTarget: self
						   withObject: threadDictionary];
	[storyLock unlock];
}

- (void) reorganiseStoriesTo: (NSString*) newStoryDirectory {
	// Changes the story organisation directory
	// Meh. Can just rename the directory, perhaps?
}

- (void) reorganiseStoryWithFilename: (NSString*) filename {
	ZoomStoryID* ident = [filenamesToIdents objectForKey: filename];
	ZoomStory*   story = [[NSApp delegate] findStory: ident];
	
	if (ident == nil) {
		// Story has disappeared in the meantime
		return;
	}
	
	if (story == nil) {
		// Uh, something weird has happened... The story is missing from the metadata database
		NSLog(@"Unable to find metadata for %@", filename);
		return;
	}
	
	[self organiseStory: story
			  withIdent: ident];
}

- (void) organiserThread: (NSDictionary*) dict {
	NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
	
	// Retrieve the info from the dictionary
	NSPort* threadPort1 = [dict objectForKey: @"threadPort1"];
	NSPort* threadPort2 = [dict objectForKey: @"threadPort2"];
	
	// Connect to the main thread
	[[NSRunLoop currentRunLoop] addPort: threadPort2
                                forMode: NSDefaultRunLoopMode];
	subThread = [[NSConnection allocWithZone: [self zone]]
        initWithReceivePort: threadPort2
                   sendPort: threadPort1];
	[subThread setRootObject: self];
	
	// Start things rolling
	[(ZoomStoryOrganiser*)[subThread rootProxy] startedActing];
	
	// Get the list of stories we need to update
	// It is assumed any new stories at this point will be organised correctly
	[storyLock lock];
	NSArray* filenames = [[filenamesToIdents allKeys] copy];
	[storyLock unlock];
	
	NSEnumerator* filenameEnum = [filenames objectEnumerator];
	NSString* filename;
	
	while (filename = [filenameEnum nextObject]) {
		// First: check that the file exists
		struct stat sb;
		
		[storyLock lock];
		if (stat([filename UTF8String], &sb) != 0) {
			// The story does not exist: remove from the database and keep moving
			
			ZoomStoryID* oldID = [filenamesToIdents objectForKey: filename];
			
			if (oldID != nil) {
				// Is actually still in the database as that filename
				[filenamesToIdents removeObjectForKey: filename];
				[identsToFilenames removeObjectForKey: oldID];
				
				[(ZoomStoryOrganiser*)[subThread rootProxy] organiserChanged];
			}
			
			[storyLock unlock];
			continue;
		}		
		[storyLock unlock];
		
		// OK, the story still exists with that filename. Pass this off to the main thread
		// for organisation
		[(ZoomStoryOrganiser*)[subThread rootProxy] reorganiseStoryWithFilename: filename];
	}
	
	// Not organising any more
	[storyLock lock];
	alreadyOrganising = NO;
	[storyLock unlock];
	
	// Tidy up
	[self release];
	
	[(ZoomStoryOrganiser*)[subThread rootProxy] endedActing];
	[subThread release];
	[p release];
}

@end

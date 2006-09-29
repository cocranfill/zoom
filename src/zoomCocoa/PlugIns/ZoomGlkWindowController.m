//
//  ZoomGlkWindowController.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on 24/11/2005.
//  Copyright 2005 Andrew Hunter. All rights reserved.
//

#import "ZoomGlkWindowController.h"
#import "ZoomPreferences.h"

#import <GlkView/GlkHub.h>


@implementation ZoomGlkWindowController

+ (void) initialize {
	// Set up the Glk hub
	[[GlkHub sharedGlkHub] useProcessHubName];
	[[GlkHub sharedGlkHub] setRandomHubCookie];
}

// = Preferences =

+ (GlkPreferences*) glkPreferencesFromZoomPreferences {
	GlkPreferences* prefs = [[GlkPreferences alloc] init];
	ZoomPreferences* zPrefs = [ZoomPreferences globalPreferences];
	
	// Set the fonts according to the Zoom preferences object
	[prefs setProportionalFont: [[zPrefs fonts] objectAtIndex: 0]];
	[prefs setFixedFont: [[zPrefs fonts] objectAtIndex: 4]];
	
	// Set the foreground/background colours
	NSColor* foreground = [[zPrefs colours] objectAtIndex: 0];
	NSColor* background = [[zPrefs colours] objectAtIndex: 7];
	
	NSEnumerator* styleEnum = [[prefs styles] keyEnumerator];
	NSMutableDictionary* newStyles = [NSMutableDictionary dictionary];
	NSNumber* styleNum;

	while (styleNum = [styleEnum nextObject]) {
		GlkStyle* thisStyle = [[prefs styles] objectForKey: styleNum];
		
		[thisStyle setTextColour: foreground];
		[thisStyle setBackColour: background];
		
		[newStyles setObject: thisStyle
					  forKey: styleNum];
	}
	
	[prefs setStyles: newStyles];
	
	return [prefs autorelease];
}

// = Initialisation =

- (id) init {
	self = [super initWithWindowNibPath: [[NSBundle bundleForClass: [ZoomGlkWindowController class]] pathForResource: @"GlkWindow"
																											  ofType: @"nib"]
								  owner: self];
	
	if (self) {
		[[NSNotificationCenter defaultCenter] addObserver: self
												selector: @selector(prefsChanged:)
													name: ZoomPreferencesHaveChangedNotification
												  object: nil];
	}
	
	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	
	[clientPath release];
	[inputPath release];
	
	[super dealloc];
}

- (void) maybeStartView {
	// If we're sufficiently configured to start the application, then do so
	if (glkView && clientPath && inputPath) {
		[glkView setPreferences: [ZoomGlkWindowController glkPreferencesFromZoomPreferences]];
		[glkView setInputFilename: inputPath];
		[glkView launchClientApplication: clientPath
						   withArguments: [NSArray array]];
	}
}

- (void) windowDidLoad {
	// Configure the view
	[glkView setRandomViewCookie];
	
	// Start it if we've got enough information
	[self maybeStartView];
}

- (void) prefsChanged: (NSNotification*) not {
	// TODO: actually change the preferences (might need some changes to the way Glk styles work here; styles are traditionally fixed after they are set...)
}

// = Configuring the client =

- (void) setClientPath: (NSString*) newPath {
	// Set the client path
	[clientPath release];
	clientPath = nil;
	clientPath = [newPath copy];
	
	// Start it if we've got enough information
	[self maybeStartView];
}

- (void) setInputFilename: (NSString*) newPath {
	// Set the input path
	[inputPath release];
	inputPath = nil;
	inputPath = [newPath copy];
	
	// Start it if we've got enough information
	[self maybeStartView];
}

@end

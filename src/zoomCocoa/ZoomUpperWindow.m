//
//  ZoomUpperWindow.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on Thu Oct 09 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "ZoomUpperWindow.h"


@implementation ZoomUpperWindow

- (id) initWithZoomView: (ZoomView*) view {
    self = [super init];
    if (self) {
        theView = view;
        lines = [[NSMutableArray allocWithZone: [self zone]] init];
    }
    return self;
}

- (void) dealloc {
    //[theView release];
    [lines release];
    [super dealloc];
}

// Clears the window
- (void) clear {
    [lines release];
    lines = [[NSMutableArray allocWithZone: [self zone]] init];
    xpos = ypos = 0;
}

// Sets the input focus to this window
- (void) setFocus {
}

// Sending data to a window
- (void) writeString: (NSString*) string
           withStyle: (ZStyle*) style {
    [style setFixed: YES];

    // FIXME: \ns in string

    if (ypos >= [lines count]) {
        int x;
        for (x=[lines count]; x<=ypos; x++) {
            [lines addObject: [[[NSMutableAttributedString alloc] init] autorelease]];
        }
    }

    NSMutableAttributedString* thisLine;
    thisLine = [lines objectAtIndex: ypos];

    int strlen = [string length];

    // Make sure there is enough space on this line for the text
    if ([thisLine length] <= xpos+strlen) {
        NSFont* fixedFont = [theView fontWithStyle: ZFixedStyle];
        NSDictionary* clearStyle = [NSDictionary dictionaryWithObjectsAndKeys:
            fixedFont, NSFontAttributeName,
            [NSColor clearColor], NSBackgroundColorAttributeName,
            nil];
        char* spaces = malloc((xpos+strlen)-[thisLine length]);

        int x;
        for (x=0; x<(xpos+strlen)-[thisLine length]; x++) {
            spaces[x] = ' ';
        }

        NSAttributedString* spaceString = [[NSAttributedString alloc]
            initWithString: [NSString stringWithCString: spaces
                                                 length: (xpos+strlen)-[thisLine length]]
                attributes: clearStyle];
        
        [thisLine appendAttributedString: spaceString];

        [spaceString release];
        free(spaces);
    }

    // Replace the appropriate section of the line
    NSAttributedString* thisString = [theView formatZString: string
                                                  withStyle: style];
    [thisLine replaceCharactersInRange: NSMakeRange(xpos, strlen)
                  withAttributedString: thisString];
    xpos += strlen;

    [theView upperWindowNeedsRedrawing];

    // FIXME: things outside the current split point
}

// Size (-1 to indicate an unsplit window)
- (void) startAtLine: (int) line {
    startLine = line;
}

- (void) endAtLine:   (int) line {
    endLine = line;
}

// Cursor positioning
- (void) setCursorPositionX: (int) xp
                          Y: (int) yp {
    xpos = xp; ypos = yp;
}

- (void) cursorPositionX: (int*) xp
                       Y: (int*) yp {
    *xp = xpos; *yp = ypos;
}

// Line erasure
- (void) eraseLine {
}

// Maintainance
- (int) length {
    return (endLine - startLine);
}

- (NSArray*) lines {
    return lines;
}

@end

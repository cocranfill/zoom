/*
 *  A Z-Machine
 *  Copyright (C) 2000 Andrew Hunter
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/*
 * The preferences dialog box
 */

#include "../config.h"

#if WINDOW_SYSTEM == 3

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include <Carbon/Carbon.h>

#include "zmachine.h"
#include "file.h"
#include "display.h"
#include "zoomres.h"
#include "rc.h"
#include "hash.h"
#include "xfont.h"
#include "carbondisplay.h"

static WindowRef prefdlog    = nil;
static rc_font*  font_copy   = NULL;
static int       font_nfonts = 0;
static MenuRef   fontmenu    = nil;
static rc_game*  ourgame     = NULL;

static char*     colour_name[11] = 
  {
    "Black",
    "Red",
    "Green",
    "Yellow",
    "Blue",
    "Magenta",
    "Cyan",
    "White",
    "Light grey",
    "Medium grey",
    "Dark grey"
  };
static RGBColor colour_copy[14];

static void pref_select_tab(ControlRef tab)
{
  ControlRef pane;
  ControlRef selpane;
  ControlID  cid;
  UInt16     i;

  SInt16 index;

  index = GetControlValue(tab);

  cid.signature = CARBON_TABS;

  selpane = nil;

  for (i = 400; i <= 403; i++)
    {
      cid.id = i;
      GetControlByID(GetControlOwner(tab), &cid, &pane);

      if (i-399 == index)
	{
	  selpane = pane;
	}
      else
	{
	  SetControlVisibility(pane, false, false);
	  DisableControl(pane);
	}
    }

  if (selpane != nil)
    {
      EnableControl(selpane);
      SetControlVisibility(selpane, true, true);
    }

  Draw1Control(tab);
}

/* Write a configuration block */
static void pref_write_block(FILE*    f,
			     rc_game* game,
			     char*    section,
			     char*    serial)
{
  int x;

  for (x=0; game->name[x] != '\0'; x++)
    {
      if (game->name[x] == '\"')
	game->name[x] = '\'';
    }

  fprintf(f, "%s \"%s\" %s\n{\n", 
	  section, game->name, (serial!=NULL?serial:""));
  if (game->interpreter != -1)
    fprintf(f, "  interpreter %i\n", game->interpreter);
  if (game->revision != -1)
    fprintf(f, "  revision %c\n", game->revision);

  if (game->fonts != NULL)
    {
      for (x=0; x<game->n_fonts; x++)
	{
	  char str[256];

	  str[0] = '\0';
	  
	  if (game->fonts[x].attributes[0]&1)
	    strcat(str, "bold");
	  if (game->fonts[x].attributes[0]&2)
	    {
	      if (str[0] != '\0')
		strcat(str, "-italic");
	      else
		strcat(str, "italic");
	    }
	  if (game->fonts[x].attributes[0]&4)
	    {
	      if (str[0] != '\0')
		strcat(str, "-fixed");
	      else
		strcat(str, "fixed");
	    }
	  if (game->fonts[x].attributes[0]&8)
	    {
	      if (str[0] != '\0')
		strcat(str, "-symbolic");
	      else
		strcat(str, "symbolic");
	    }
	  
	  if (str[0] == '\0')
	    strcat(str, "roman");

	  fprintf(f, "  font %i \"%s\" %s\n", x, game->fonts[x].name, str);
	}
    }

  if (game->colours != NULL)
    {
      fprintf(f, "  colours ");

      for (x=0; x<game->n_colours; x++)
	{
	  fprintf(f, "(%i,%i,%i)",
		  game->colours[x].r,
		  game->colours[x].g,
		  game->colours[x].b);
	  
	  if (x < game->n_colours-1)
	    fprintf(f, ", ");
	}
      fprintf(f, "\n");
    }

  if (game->xsize > 0)
    {
      fprintf(f, "  size %i,%i\n", game->xsize, game->ysize);
    }
  fprintf(f, "}\n\n");
}

/* Iterator for the games in the hash */
static int pref_write_game(char* key,
			   int   keylen,
			   void* data,
			   void* arg)
{
  char name[256];

  strncpy(name, key, keylen);
  name[keylen] = '\0';

  if (strcmp(name, "default") != 0)
    {
      pref_write_block(arg, data, "game", name);
    }
  
  return 0;
}

/* Write the resource file */
static void pref_write(void)
{
  char* home;
  char* filename;
  FILE* out;

  home = getenv("HOME");
  if (home == NULL)
    {
      carbon_display_message("Can't find home directory", "Dammit");
      return;
    }
  else
    {
      filename = malloc(strlen(home)+9);
      strcpy(filename, home);
      strcat(filename, "/.zoomrc");
    }
  
  out = fopen(filename, "w");
  fprintf(out, 
	  "#\n"
	  "# Zoom configuration file, automatically generated\n"
	  "#\n\n");

  pref_write_block(out, rc_defgame, "default", NULL);
  hash_iterate(rc_hash, pref_write_game, out);

  fclose(out);

  free(filename);
}

/* Update the stored copy of the preferences */
static void pref_store(void)
{
  ControlID  cid;
  ControlRef cntl;

  char str[256];
  Size outsize;

  int  islocal;
  int  x;

  /* Get the general preferences */
  cid.signature = CARBON_DISPWARNS;
  cid.id        = CARBON_DISPWARNSID;
  GetControlByID(prefdlog, &cid, &cntl);
  carbon_prefs.show_warnings = 
    GetControlValue(cntl)==kControlCheckBoxCheckedValue;

  cid.signature = CARBON_FATWARNS;
  cid.id        = CARBON_FATWARNSID;
  GetControlByID(prefdlog, &cid, &cntl);
  carbon_prefs.fatal_warnings =
    GetControlValue(cntl)==kControlCheckBoxCheckedValue;

  cid.signature = CARBON_SPEAK;
  cid.id        = CARBON_SPEAKID;
  GetControlByID(prefdlog, &cid, &cntl);
  carbon_prefs.use_speech = 
    GetControlValue(cntl)==kControlCheckBoxCheckedValue;

  cid.signature = CARBON_RENDER;
  cid.id        = CARBON_RENDERID;
  GetControlByID(prefdlog, &cid, &cntl);
  carbon_prefs.use_quartz = 
    GetControlValue(cntl)==2;

  if (carbon_prefs.show_warnings)
    {
      machine.warning_level = 1;
      if (carbon_prefs.fatal_warnings)
	machine.warning_level = 2;
    }

  /* Get the game title */
  cid.signature = CARBON_TITLE;
  cid.id        = CARBON_TITLEID;  
  GetControlByID(prefdlog, &cid, &cntl);

  GetControlData(cntl, kControlEntireControl, kControlEditTextTextTag,
		 256, str, &outsize);
  str[outsize] = '\0';
  ourgame->name = realloc(ourgame->name, strlen(str)+1);
  strcpy(ourgame->name, str);
  display_set_title(str);

  /* Get the interpreter ID */
  cid.signature = CARBON_INTERPLOC;
  cid.id        = CARBON_INTERPLOCID;
  GetControlByID(prefdlog, &cid, &cntl);

  islocal = GetControlValue(cntl)==kControlCheckBoxCheckedValue;
  
  cid.signature = CARBON_INTERP;
  cid.id        = CARBON_INTERPID;

  GetControlByID(prefdlog, &cid, &cntl);
  GetControlData(cntl, kControlEntireControl, kControlEditTextTextTag,
		 256, str, &outsize);
  str[outsize] = '\0';

  if (islocal)
    {
      ourgame->interpreter = atoi(str);
    }
  else
    {
      ourgame->interpreter = -1;
      rc_defgame->interpreter = atoi(str);
    }

  /* Get the interpreter revision */
  cid.signature = CARBON_REVLOC;
  cid.id        = CARBON_REVLOCID;
  GetControlByID(prefdlog, &cid, &cntl);

  islocal = GetControlValue(cntl)==kControlCheckBoxCheckedValue;
  
  cid.signature = CARBON_REVISION;
  cid.id        = CARBON_REVISIONID;

  GetControlByID(prefdlog, &cid, &cntl);
  GetControlData(cntl, kControlEntireControl, kControlEditTextTextTag,
		 256, str, &outsize);
  str[outsize] = '\0';

  if (outsize != 1)
    {
      carbon_display_message("Bad interpreter revision", "The interpreter revision should be a single upper case letter");
    }
  else
    {
      if (islocal)
	{
	  ourgame->revision = str[0];
	}
      else
	{
	  ourgame->revision = -1;
	  rc_defgame->revision = str[0];
	}
    }

  /* Get the fonts */
  cid.signature = CARBON_FONTLOC;
  cid.id        = CARBON_FONTLOCID;
  GetControlByID(prefdlog, &cid, &cntl);

  islocal = GetControlValue(cntl)==kControlCheckBoxCheckedValue;

  if (!islocal && ourgame->fonts != NULL)
    {
      for (x=0; x<ourgame->n_fonts; x++)
	{
	  free(ourgame->fonts[x].name);
	}

      free(ourgame->fonts);
      ourgame->fonts = NULL;
      ourgame->n_fonts = -1;
    }

  if (islocal)
    {
      if (ourgame->fonts != NULL)
	{
	  for (x=0; x<ourgame->n_fonts; x++)
	    {
	      free(ourgame->fonts[x].name);
	    }
	}

      ourgame->n_fonts = font_nfonts;
      ourgame->fonts = realloc(ourgame->fonts, sizeof(rc_font)*font_nfonts);
      memcpy(ourgame->fonts, font_copy, sizeof(rc_font)*font_nfonts);
    }
  else
    {
      if (rc_defgame->fonts != NULL)
	{
	  for (x=0; x<rc_defgame->n_fonts; x++)
	    {
	      free(rc_defgame->fonts[x].name);
	    }
	}

      rc_defgame->n_fonts = font_nfonts;
      rc_defgame->fonts = realloc(rc_defgame->fonts, sizeof(rc_font)*font_nfonts);
      memcpy(rc_defgame->fonts, font_copy, sizeof(rc_font)*font_nfonts);
    }

  free(font_copy);
  font_copy = NULL;

  /* ...and the colours */
  cid.signature = CARBON_COLLOC;
  cid.id        = CARBON_COLLOCID;
  GetControlByID(prefdlog, &cid, &cntl);
  
  islocal = GetControlValue(cntl)==kControlCheckBoxCheckedValue;
  
  if (!islocal)
    {
      if (ourgame->colours != NULL)
	free(ourgame->colours);

      ourgame->colours = NULL;
      ourgame->n_colours = -1;

      rc_defgame->colours   = realloc(rc_defgame->colours, sizeof(rc_colour)*11);
      rc_defgame->n_colours = 11;

      for (x=0; x<11; x++)
	{
	  rc_defgame->colours[x].r = colour_copy[x].red  >>8;
	  rc_defgame->colours[x].g = colour_copy[x].green>>8;
	  rc_defgame->colours[x].b = colour_copy[x].blue >>8;
	}
    }
  else
    {
      ourgame->colours   = realloc(ourgame->colours, sizeof(rc_colour)*11);
      ourgame->n_colours = 11;

      for (x=0; x<11; x++)
	{
	  ourgame->colours[x].r = colour_copy[x].red  >>8;
	  ourgame->colours[x].g = colour_copy[x].green>>8;
	  ourgame->colours[x].b = colour_copy[x].blue >>8;
	}
     }

  for (x=0; x<11; x++)
    {
      maccolour[x+3] = colour_copy[x];
    }

  /* Reset the display */
  rc_set_game(Address(ZH_serial), Word(ZH_release));
  carbon_display_rejig();

  /* Rewrite the preferences file */
  pref_write();

  /* Store the app preferences */
  {
    CFNumberRef cfnum;

    cfnum = CFNumberCreate(NULL, kCFNumberIntType, &carbon_prefs.use_speech);
    CFPreferencesSetAppValue(CFSTR("useSpeech"),
			     cfnum,
			     kCFPreferencesCurrentApplication);
    CFRelease(cfnum);

    cfnum = CFNumberCreate(NULL, kCFNumberIntType, &carbon_prefs.show_warnings);
    CFPreferencesSetAppValue(CFSTR("showWarnings"),
			     cfnum,
			     kCFPreferencesCurrentApplication);
    CFRelease(cfnum);

    cfnum = CFNumberCreate(NULL, kCFNumberIntType, &carbon_prefs.fatal_warnings);
    CFPreferencesSetAppValue(CFSTR("fatalWarnings"),
			     cfnum,
			     kCFPreferencesCurrentApplication);
    CFRelease(cfnum);

    cfnum = CFNumberCreate(NULL, kCFNumberIntType, &carbon_prefs.use_quartz);
    CFPreferencesSetAppValue(CFSTR("useQuartz"),
			     cfnum,
			     kCFPreferencesCurrentApplication);
    CFRelease(cfnum);

    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
  }
}

/* Deal with events to the window */
static pascal OSStatus pref_wnd_evt(EventHandlerCallRef handler,
				    EventRef event,
				    void*    data)
{
  UInt32    cla;
  UInt32    wha;

  cla = GetEventClass(event);
  wha = GetEventKind(event);

  switch (cla)
    {
    case kEventClassMouse:
      switch (wha)
	{
      	case kEventMouseDown:
	  {
	    short part;
	    WindowPtr ourwindow;
	    HIPoint   argh;
	    Point     point;

	    GetEventParameter(event, kEventParamMouseLocation,
			      typeHIPoint, NULL, sizeof(HIPoint),
			      NULL, &argh);
	    point.h = argh.x;
	    point.v = argh.y;
	    part = FindWindow(point, &ourwindow);

	    switch (part)
	      {
	      case inGoAway:
		if (TrackGoAway(ourwindow, point))
		  {
		    ControlID  cid;
		    ControlRef cntl;
		    
		    int cfonts, ccols;

		    /* 
		     * Check if the font settings have been changed from
		     * local to global
		     */
		    cfonts = 0;

		    cid.signature = CARBON_FONTLOC;
		    cid.id        = CARBON_FONTLOCID;
		    GetControlByID(prefdlog, &cid, &cntl);

		    if (ourgame->fonts != NULL &&
			GetControlValue(cntl) == kControlCheckBoxUncheckedValue)
		      {
			cfonts = 1;
		      }

		    /*
		     * Check if the colour settings have been changed from
		     * local to global
		     */
		    ccols = 0;

		    cid.signature = CARBON_COLLOC;
		    cid.id        = CARBON_COLLOCID;
		    GetControlByID(prefdlog, &cid, &cntl);

		    if (ourgame->colours != NULL &&
			GetControlValue(cntl) == kControlCheckBoxUncheckedValue)
		      {
			ccols = 1;
		      }

		    /*
		     * Get confirmation if necessary
		     */
		    if (cfonts || ccols)
		      {
			AlertStdCFStringAlertParamRec par;
			DialogRef confdlog;

			par.version       = kStdCFStringAlertVersionOne;
			par.movable       = false;
			par.helpButton    = false;
			par.defaultText   = CFSTR("Keep changes");
			par.cancelText    = CFSTR("Cancel");
			par.otherText     = CFSTR("Discard changes");
			par.defaultButton = kAlertStdAlertOKButton;
			par.cancelButton  = kAlertStdAlertCancelButton;
			par.position      = kWindowDefaultPosition;
			par.flags         = 0;

			CreateStandardSheet(kAlertCautionAlert,
					    CFSTR("Are you sure you want the changes to apply globally?"),
					    CFSTR("You have changed the font and/or colour settings from applying only to the current game to applying to all games - if you choose to keep these changes, they will apply to all games, not just the current one"),
					    &par,
					    GetWindowEventTarget(prefdlog),
					    &confdlog);
			ShowSheetWindow(GetDialogWindow(confdlog), prefdlog);
		      }
		    else
		      {
			pref_store();

			DisposeWindow(prefdlog);
			prefdlog = nil;
		      }
		  }
		return noErr;
		
	      default:
		return eventNotHandledErr;
	      }
	  }
	  break;
	}
      break;

    case kEventClassCommand:
      switch (wha)
	{
	case kEventProcessCommand:
	  {
	    HICommand cmd;

	    GetEventParameter(event, kEventParamDirectObject,
			      typeHICommand, NULL, sizeof(HICommand),
			      NULL, &cmd);

	    switch (cmd.commandID)
	      {
	      case kHICommandOK:
		pref_store();

		DisposeWindow(prefdlog);
		prefdlog = nil;
		break;
		
	      case kHICommandOther:
		DisposeWindow(prefdlog);
		prefdlog = nil;
		break;
	      }
	  }
	  break;
	}
      break;
    }

  return eventNotHandledErr;
}

static pascal OSStatus pref_tab_evt(EventHandlerCallRef handler,
				    EventRef event,
				    void*    data)
{
  OSStatus result = eventNotHandledErr;

  ControlRef control;
  ControlID  cid;

  GetEventParameter(event, kEventParamDirectObject, typeControlRef, NULL,
		    sizeof(ControlRef), NULL, &control);
  GetControlID(control, &cid);

  if (cid.id == CARBON_TABSID)
    {
      pref_select_tab(control);
    }

  return result;
}

/* Sets up the font menu to show font examples */
static void style_font_menu(void)
{
  char family[257];
  int x;
  int nitems;
  
  nitems = CountMenuItems(fontmenu);
  for (x=2; x<=nitems; x++)
    {
      GetMenuItemText(fontmenu, x, family);
      family[family[0]+1] = '\0';
      SetMenuItemFontID(fontmenu, x, FMGetFontFamilyFromName(family));
    }
}

/* Data event handler for the colour list view */
static pascal OSStatus colour_data_cb(ControlRef browser,
				      DataBrowserItemID item,
				      DataBrowserPropertyID property,
				      DataBrowserItemDataRef itemref,
				      Boolean setvalue)
{
  switch (property)
    {
    case 'Desc':
      SetDataBrowserItemDataText(itemref,
				 CFStringCreateWithCString(NULL, colour_name[item-1], kCFStringEncodingMacRoman));
      break;
    }

  return noErr;
}

/* Function to draw the preview of a colour */
static pascal void colour_draw_cb(ControlRef            browser,
				  DataBrowserItemID     item,
				  DataBrowserPropertyID prop,
				  DataBrowserItemState  state,
				  const Rect*           rct,
				  SInt16                gdDepth,
				  Boolean               colorDevice)
{
  Rect prct;

  prct = *rct;
  RGBForeColor(&colour_copy[item-1]);
  prct.left   += 2;
  prct.right  -= 2;
  prct.top    += 2;
  prct.bottom -= 2;
  PaintRect(&prct);
}

/* Test to see if the click was in the colour's clickable area */
static pascal Boolean colour_hit_cb(ControlRef browser,
				    DataBrowserItemID item,
				    DataBrowserPropertyID prop,
				    const Rect* theRect,
				    const Rect* mouseRect)
{
  Rect r;
  Boolean res;

  r = *theRect;
  r.top += 2;
  r.bottom -= 2;
  r.left += 2;
  r.right -= 2;

  if (mouseRect->left == mouseRect->right)
    {
      res = (mouseRect->top > r.top && mouseRect->top < r.bottom) &&
	(mouseRect->left > r.left && mouseRect->left < r.right);
    }
  else
    {
      res = SectRect(mouseRect, &r, NULL);
    }

  return res;
}

/* Notification handler for the colour list view */
static pascal void colour_data_notify(ControlRef browser,
				      DataBrowserItemID item,
				      DataBrowserItemNotification msg)
{
  Point pt;
  RGBColor res;
  DataBrowserItemID id[1];

  switch (msg)
    {
    case kDataBrowserItemSelected:
    case kDataBrowserItemDoubleClicked:
      GetGlobalMouse(&pt);
      pt.v -= 10;
      pt.h -= 10;

      if (GetColor(pt, "\016Choose colour", &colour_copy[item-1], &res))
	colour_copy[item-1] = res;

      id[0] = item;
      UpdateDataBrowserItems(browser, kDataBrowserNoItem, 1, id, 0, 'Samp');
      break;
    }
       
}

/* Data event handler for the font list view */
static pascal OSStatus font_data_cb(ControlRef browser,
				    DataBrowserItemID item,
				    DataBrowserPropertyID property,
				    DataBrowserItemDataRef itemref,
				    Boolean setvalue)
{
  carbon_font* fnt;
  char str[256];
  int x;

  fnt = carbon_parse_font(font_copy[item-1].name);

  switch (property)
    {
    case 'Styl':
      str[0] = '\0';

      if (font_copy[item-1].attributes[0]&1)
	strcat(str, "bold");
      if (font_copy[item-1].attributes[0]&2)
	{
	  if (str[0] != '\0')
	    strcat(str, "-italic");
	  else
	    strcat(str, "italic");
	}
      if (font_copy[item-1].attributes[0]&4)
	{
	  if (str[0] != '\0')
	    strcat(str, "-fixed");
	  else
	    strcat(str, "fixed");
	}
      if (font_copy[item-1].attributes[0]&8)
	{
	  if (str[0] != '\0')
	    strcat(str, "-symbolic");
	  else
	    strcat(str, "symbolic");
	}
      
      if (str[0] == '\0')
	strcat(str, "roman");

      SetDataBrowserItemDataText(itemref,
				 CFStringCreateWithCString(NULL, str, kCFStringEncodingMacRoman));
      break;

    case 'Size':
      if (!setvalue)
	{
	  sprintf(str, "%i", fnt->size);
	  SetDataBrowserItemDataText(itemref,
				     CFStringCreateWithCString(NULL, str, kCFStringEncodingMacRoman));
	}
      else
	{
	  CFStringRef cfstr;
	  char buf[64];
	  int sz;

	  GetDataBrowserItemDataText(itemref,
				     &cfstr);
	  CFStringGetCString(cfstr, buf, 64, kCFStringEncodingMacRoman);
	  sz = atoi(buf);
	  if (sz > 0 && sz < 200)
	    fnt->size = sz;
	  CFRelease(cfstr);
	}
      break;

    case 'Bold':
      if (!setvalue)
	{
	  SetDataBrowserItemDataButtonValue(itemref,
					    fnt->isbold?kControlCheckBoxCheckedValue:kControlCheckBoxUncheckedValue);
	}
      else
	{
	  ThemeButtonValue val;

	  GetDataBrowserItemDataButtonValue(itemref, &val);
	  fnt->isbold = val == kControlCheckBoxCheckedValue;
	}
      break;

    case 'Ital':
      if (!setvalue)
	{
	  SetDataBrowserItemDataButtonValue(itemref,
					    fnt->isitalic?kControlCheckBoxCheckedValue:kControlCheckBoxUncheckedValue);
	}
      else
	{
	  ThemeButtonValue val;

	  GetDataBrowserItemDataButtonValue(itemref, &val);
	  fnt->isitalic = val == kControlCheckBoxCheckedValue;
	}
      break;

    case 'Undl':
      if (!setvalue)
	{
	  SetDataBrowserItemDataButtonValue(itemref,
					    fnt->isunderlined?kControlCheckBoxCheckedValue:kControlCheckBoxUncheckedValue);
	}
      else
	{
	  ThemeButtonValue val;

	  GetDataBrowserItemDataButtonValue(itemref, &val);
	  fnt->isunderlined = val == kControlCheckBoxCheckedValue;
	}
      break;

    case 'Desc':
      if (!setvalue)
	{
	  char family[257];
	  int nitems, ouritem;

	  nitems = CountMenuItems(fontmenu);
	  ouritem = 1;
	  if (fnt->isfont3)
	    {
	      ouritem = 1;
	    }
	  else
	    {
	      for (x=2; x<=nitems; x++)
		{
		  GetMenuItemText(fontmenu, x, family);
		  family[family[0]+1] = '\0';
		  if (strcmp(family+1, fnt->face_name) == 0)
		    {
		      ouritem = x;
		    }
		}
	    }

	  SetDataBrowserItemDataMenuRef(itemref, fontmenu);
	  SetDataBrowserItemDataValue(itemref, ouritem);
	}
      else
	{
	  SInt32 ouritem;
	  OSStatus stat;
	  char hum[257];

	  stat = GetDataBrowserItemDataValue(itemref, &ouritem);
	  if (ouritem > 0)
	    {
	      if (ouritem == 1)
		fnt->isfont3 = 1;
	      else
		{
		  fnt->isfont3 = 0;
		  
		  GetMenuItemText(fontmenu, ouritem, hum);
		  
		  hum[hum[0]+1] = '\0';
		  strcpy(fnt->face_name, hum+1);
		}
	    }
	}
      break;

    case kDataBrowserItemIsEditableProperty:
      SetDataBrowserItemDataBooleanValue(itemref, true);
      break;
    }

  if (setvalue)
    {
      char str[256];
      DataBrowserItemID id[1];
      
      id[0] = item;
      
      if (fnt->isfont3)
	strcpy(str, "font3");
      else
	sprintf(str, "'%s' %i %c%c%c", 
		fnt->face_name,
		fnt->size,
		fnt->isbold?'b':' ',
		fnt->isitalic?'i':' ',
		fnt->isunderlined?'u':' ');
      font_copy[item-1].name = realloc(font_copy[item-1].name,
				       strlen(str)+1);
      strcpy(font_copy[item-1].name, str);

      UpdateDataBrowserItems(browser, kDataBrowserNoItem, 1, id, 0, 'Samp');
    }

  return noErr;
}

/* Function to draw the preview of a font */
static pascal void font_draw_cb(ControlRef            browser,
				DataBrowserItemID     item,
				DataBrowserPropertyID prop,
				DataBrowserItemState  state,
				const Rect*           rct,
				SInt16                gdDepth,
				Boolean               colorDevice)
{
  char   name[256];
  carbon_font* fnt;
  xfont* xfnt;
  int string[] = 
    { 'T', 'h', 'e', ' ', 'Q', 'u', 'i', 'c', 'k', ' ', 
      'B', 'r', 'o', 'w', 'n', ' ', 'F', 'o', 'x', ' ', 
      'J', 'u', 'm', 'p', 'e', 'd', ' ', 'O', 'v', 'e', 'r', ' ', 
      't', 'h', 'e', ' ', 'L', 'a', 'z', 'y', ' ', 'D', 'o', 'g' };
  int offset;

  RgnHandle oldclip;
  RgnHandle newclip;

  /* 
   * The docs say we shouldn't alter the clip region, but we need to clip 
   * the example, sooo... we, er, bend the rules a bit 
   */
  oldclip = NewRgn();
  newclip = NewRgn();
  RectRgn(newclip, rct);
  GetClip(oldclip);

  SectRgn(oldclip, newclip, newclip);

  SetClip(newclip);

#ifdef USE_QUARTZ
  carbon_set_quartz(0);
#endif

  /* Create a 14-point version of this font */
  fnt = carbon_parse_font(font_copy[item-1].name);
  if (fnt->isfont3)
    strcpy(name, "font3");
  else
    sprintf(name, "'%s' 14 %c%c%c", 
	    fnt->face_name,
	    fnt->isbold?'b':' ',
	    fnt->isitalic?'i':' ',
	    fnt->isunderlined?'u':' ');

  /* Load it, display it, release it */
  xfnt = xfont_load_font(name);
  xfont_set_colours(3, 10);

  offset = (rct->bottom - rct->top)/2 + xfont_get_ascent(xfnt)/2;

  xfont_plot_string(xfnt,
		    rct->left,
		    -rct->top - offset,
		    string,
		    44);
  xfont_release_font(xfnt);

  /* Reset the clipping region */
  SetClip(oldclip);
  DisposeRgn(oldclip);

#ifdef USE_QUARTZ
  carbon_set_quartz(carbon_prefs.use_quartz);
#endif
}

/* Function to set up the contents of the preferences dialog */
static void pref_setup(void)
{
  ControlID  cid;
  ControlRef cntl;

  char str[40];
  int val,x;

  rc_game* game;

  DataBrowserItemID items[40];

  rc_font* fonts;
  int      n_fonts;

  /* Set up the general preferences */
  cid.signature = CARBON_DISPWARNS;
  cid.id        = CARBON_DISPWARNSID;
  GetControlByID(prefdlog, &cid, &cntl);
  SetControlValue(cntl, carbon_prefs.show_warnings?
		  kControlCheckBoxCheckedValue:kControlCheckBoxUncheckedValue);

  cid.signature = CARBON_FATWARNS;
  cid.id        = CARBON_FATWARNSID;
  GetControlByID(prefdlog, &cid, &cntl);
  SetControlValue(cntl, carbon_prefs.fatal_warnings?
		  kControlCheckBoxCheckedValue:kControlCheckBoxUncheckedValue);

  cid.signature = CARBON_SPEAK;
  cid.id        = CARBON_SPEAKID;
  GetControlByID(prefdlog, &cid, &cntl);
  SetControlValue(cntl, carbon_prefs.use_speech?
		  kControlCheckBoxCheckedValue:kControlCheckBoxUncheckedValue);

  cid.signature = CARBON_RENDER;
  cid.id        = CARBON_RENDERID;
  GetControlByID(prefdlog, &cid, &cntl);
  SetControlValue(cntl, carbon_prefs.use_quartz?
		  2:1);

  /* Try to get the game hash entry */
  sprintf(str, "%i.%.6s", Word(ZH_release), Address(ZH_serial));
  game = hash_get(rc_hash, str, strlen(str));

  if (game == NULL)
    {
      /* Create a new, blank entry */
      game = malloc(sizeof(rc_game));
      game->name = malloc(strlen(carbon_title)+1);
      strcpy(game->name, carbon_title);
      
      game->interpreter = -1;
      game->revision    = -1;
      game->fonts       = NULL;
      game->n_fonts     = -1;
      game->colours     = NULL;
      game->n_colours   = -1;
      game->gamedir     = NULL;
      game->savedir     = NULL;
      game->sounds      = NULL;
      game->graphics    = NULL;
      game->xsize       = -1;
      game->ysize       = -1;

      hash_store(rc_hash, str, strlen(str), game);
    }

  /* Set up the 'serial #' field */
  cid.signature = CARBON_SERIAL;
  cid.id        = CARBON_SERIALID;
  
  GetControlByID(prefdlog, &cid, &cntl);
  sprintf(str, "%.6s", Address(ZH_serial));
  SetControlData(cntl, kControlEntireControl, kControlStaticTextTextTag,
		 strlen(str), str);

  /* Set up the 'Release #' field */
  cid.signature = CARBON_RELEASE;
  cid.id        = CARBON_RELEASEID;
  
  GetControlByID(prefdlog, &cid, &cntl);
  sprintf(str, "%i", Word(ZH_release));
  SetControlData(cntl, kControlEntireControl, kControlStaticTextTextTag,
		 strlen(str), str);

  /* Set up the 'Game title' field */
  cid.signature = CARBON_TITLE;
  cid.id        = CARBON_TITLEID;
  
  GetControlByID(prefdlog, &cid, &cntl);
  SetControlData(cntl, kControlEntireControl, kControlEditTextTextTag,
		 strlen(game->name), game->name);

  /* Set up the 'Interpreter' field */
  cid.signature = CARBON_INTERPLOC;
  cid.id        = CARBON_INTERPLOCID;
  GetControlByID(prefdlog, &cid, &cntl);

  if (game->interpreter == -1)
    {
      val = rc_defgame->interpreter;
      SetControlValue(cntl, kControlCheckBoxUncheckedValue);
    }
  else
    {
      val = game->interpreter;
      SetControlValue(cntl, kControlCheckBoxCheckedValue);
    }

  cid.signature = CARBON_INTERP;
  cid.id        = CARBON_INTERPID;
  GetControlByID(prefdlog, &cid, &cntl);

  sprintf(str, "%i", val);
  SetControlData(cntl, kControlEntireControl, kControlEditTextTextTag,
		 strlen(str), str);

  /* Set up the 'Interpreter revision' field */
  cid.signature = CARBON_REVLOC;
  cid.id        = CARBON_REVLOCID;
  GetControlByID(prefdlog, &cid, &cntl);

  if (game->revision == -1)
    {
      val = rc_defgame->revision;
      SetControlValue(cntl, kControlCheckBoxUncheckedValue);
    }
  else
    {
      val = game->revision;
      SetControlValue(cntl, kControlCheckBoxCheckedValue);
    }

  cid.signature = CARBON_REVISION;
  cid.id        = CARBON_REVISIONID;
  GetControlByID(prefdlog, &cid, &cntl);

  sprintf(str, "%c", val);
  SetControlData(cntl, kControlEntireControl, kControlEditTextTextTag,
		 strlen(str), str);

  /* Set up the font list */
  cid.signature = CARBON_FONTLOC;
  cid.id        = CARBON_FONTLOCID;
  GetControlByID(prefdlog, &cid, &cntl);

  if (game->fonts != NULL)
    {
      SetControlValue(cntl, kControlCheckBoxCheckedValue);
      fonts = game->fonts;
      n_fonts = game->n_fonts;
    }
  else
    {
      SetControlValue(cntl, kControlCheckBoxUncheckedValue);
      fonts = rc_defgame->fonts;
      n_fonts = rc_defgame->n_fonts;
    }

  cid.signature = CARBON_FONTLIST;
  cid.id        = CARBON_FONTLISTID;
  GetControlByID(prefdlog, &cid, &cntl);

  font_copy = realloc(font_copy, sizeof(rc_font)*n_fonts);
  memcpy(font_copy, fonts, sizeof(rc_font)*n_fonts);
  font_nfonts = n_fonts;

  for (x=0; x < n_fonts; x++)
    {
      font_copy[x].name = malloc(strlen(fonts[x].name)+1);
      strcpy(font_copy[x].name, fonts[x].name);
      items[x] = x+1;
    }
  AddDataBrowserItems(cntl, kDataBrowserNoItem, n_fonts, items, 0);

  /* Set up the colour list */
  cid.signature = CARBON_COLLIST;
  cid.id        = CARBON_COLLISTID;
  GetControlByID(prefdlog, &cid, &cntl);

  for (x=0; x < 11; x++)
    {
      items[x] = x+1;
      colour_copy[x] = maccolour[x+3];
    }
  AddDataBrowserItems(cntl, kDataBrowserNoItem, 11, items, 0);

  ourgame = game;
}

void carbon_show_prefs(void)
{
  IBNibRef nib;
  
  if (fontmenu == nil)
    {
      fontmenu = NewMenu(20, "\005Fonts");
      AppendMenuItemText(fontmenu, "\017Built-in font 3");
      CreateStandardFontMenu(fontmenu, 1, 0, kNilOptions, NULL);      
      style_font_menu();
      InsertMenu(fontmenu, -1);
    }

  if (prefdlog == nil)
    {
      ControlID tab;
      ControlRef tabcontrol;

      ControlID cid;
      ControlRef cntl;

      EventTypeSpec winspec[] = 
	{ 
	  { kEventClassMouse,   kEventMouseDown },
	  { kEventClassCommand, kEventProcessCommand }
	};
      EventTypeSpec tabspec = { kEventClassControl, kEventControlHit };
      static EventHandlerUPP evhandle = nil;
      static EventHandlerUPP prefhandle = nil;

      DataBrowserCallbacks dbcb;
      DataBrowserCustomCallbacks dbcustom;

      /* Create the window */
      CreateNibReference(CFSTR("zoom"), &nib);
      CreateWindowFromNib(nib, CFSTR("Preferences"), &prefdlog);
      DisposeNibReference(nib);

      /* Install a handler to deal with adjustments to the window */
      if (prefhandle == nil)
	prefhandle = NewEventHandlerUPP(pref_wnd_evt);

      InstallEventHandler(GetWindowEventTarget(prefdlog),
			  prefhandle, 2, winspec, 0, NULL);

      /* Install a handler to change the tab panes */
      tab.signature = CARBON_TABS;
      tab.id        = CARBON_TABSID;
      GetControlByID(prefdlog, &tab, &tabcontrol);

      if (evhandle == nil)
	evhandle = NewEventHandlerUPP(pref_tab_evt);

      InstallEventHandler(GetControlEventTarget(tabcontrol),
			  evhandle, 1, &tabspec, 0, NULL);

      pref_setup();
      pref_select_tab(tabcontrol);

      /* Install handlers for the font list box */
      cid.signature = CARBON_FONTLIST;
      cid.id        = CARBON_FONTLISTID;
      GetControlByID(prefdlog, &cid, &cntl);
      
      dbcb.version = kDataBrowserLatestCallbacks;
      InitDataBrowserCallbacks(&dbcb);

      dbcb.u.v1.itemDataCallback = NewDataBrowserItemDataUPP(font_data_cb);
      
      SetDataBrowserCallbacks(cntl, &dbcb);

      dbcustom.version = kDataBrowserLatestCustomCallbacks;
      InitDataBrowserCustomCallbacks(&dbcustom);
      
      dbcustom.u.v1.drawItemCallback = NewDataBrowserDrawItemUPP(font_draw_cb);
      SetDataBrowserCustomCallbacks(cntl, &dbcustom);

      /* Set the editable fields */
      SetDataBrowserPropertyFlags(cntl, 'Desc', kDataBrowserPropertyIsEditable);
      SetDataBrowserPropertyFlags(cntl, 'Size', kDataBrowserPropertyIsEditable);
      SetDataBrowserPropertyFlags(cntl, 'Bold', kDataBrowserPropertyIsEditable);
      SetDataBrowserPropertyFlags(cntl, 'Ital', kDataBrowserPropertyIsEditable);
      SetDataBrowserPropertyFlags(cntl, 'Undl', kDataBrowserPropertyIsEditable);
      
      /* Set up the colour list box */
      cid.signature = CARBON_COLLIST;
      cid.id        = CARBON_COLLISTID;
      GetControlByID(prefdlog, &cid, &cntl);
      
      SetDataBrowserPropertyFlags(cntl, 'Samp', kDataBrowserPropertyIsEditable);
      
      dbcb.version = kDataBrowserLatestCallbacks;
      InitDataBrowserCallbacks(&dbcb);

      dbcb.u.v1.itemDataCallback = NewDataBrowserItemDataUPP(colour_data_cb);
      dbcb.u.v1.itemNotificationCallback = NewDataBrowserItemNotificationUPP(colour_data_notify);
      
      SetDataBrowserCallbacks(cntl, &dbcb);

      dbcustom.version = kDataBrowserLatestCustomCallbacks;
      InitDataBrowserCustomCallbacks(&dbcustom);
      
      dbcustom.u.v1.drawItemCallback = NewDataBrowserDrawItemUPP(colour_draw_cb);
      dbcustom.u.v1.hitTestCallback = NewDataBrowserHitTestUPP(colour_hit_cb);

      SetDataBrowserCustomCallbacks(cntl, &dbcustom);
    }

  ShowWindow(prefdlog);
  BringToFront(prefdlog);
}

#endif

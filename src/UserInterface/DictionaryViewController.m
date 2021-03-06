//
//  DictionaryViewController.m
//  Eloquent
//
//  Created by Manfred Bergmann on 25.08.08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "HostableViewController.h"
#import <ObjCSword/SwordManager.h>
#import <ObjCSword/SwordDictionary.h>
#import "ContentDisplayingViewController.h"
#import "ModuleCommonsViewController.h"
#import "DictionaryViewController.h"
#import "WindowHostController.h"
#import "ScrollSynchronizableView.h"
#import "MBPreferenceController.h"
#import "SearchResultEntry.h"
#import "Highlighter.h"
#import "globals.h"
#import "LeftSideBarAccessoryUIController.h"
#import "ModulesUIController.h"
#import "NSUserDefaults+Additions.h"
#import "SearchTextFieldOptions.h"
#import "CacheObject.h"

@interface DictionaryViewController (/* class continuation */)

@property (strong, readwrite) NSMutableArray *selection;
@property (strong, readwrite) NSArray *dictKeys;

- (void)commonInit;
- (NSIndexSet *)selectedIndexes;
- (void)selectTableViewEntriesFromSelection;

@end

@implementation DictionaryViewController

@synthesize selection;
@synthesize dictKeys;

- (id)init {
    self = [super init];
    if(self) {
        self.searchType = ReferenceSearchType;
        self.module = nil;
        self.delegate = nil;
        self.dictKeys = [NSArray array];
        self.selection = [NSMutableArray array];        
    }
    
    return self;
}

- (id)initWithModule:(SwordDictionary *)aModule {
    return [self initWithModule:aModule delegate:nil];
}

- (id)initWithDelegate:(id)aDelegate {
    return [self initWithModule:nil delegate:aDelegate];
}

- (id)initWithModule:(SwordDictionary *)aModule delegate:(id)aDelegate {
    self = [self init];
    if(self) {
        self.module = aModule;
        self.delegate = aDelegate;
        [self commonInit];
    } else {
        CocoLog(LEVEL_ERR, @"unable init!");
    }
    
    return self;
}

- (void)commonInit {
    [super commonInit];
    if(module != nil) {
        self.dictKeys = [(SwordDictionary *)module allKeys];
    }
    
    BOOL stat = [[NSBundle mainBundle] loadNibNamed:DICTIONARYVIEW_NIBNAME owner:self topLevelObjects:nil];
    if(!stat) {
        CocoLog(LEVEL_ERR, @"unable to load nib!");
    }
}

- (void)awakeFromNib {
    [super awakeFromNib];
    
    if([(HostableViewController *) contentDisplayController myIsViewLoaded]) {
        [(ScrollSynchronizableView *)[self view] setSyncScrollView:[(id<TextContentProviding>)contentDisplayController scrollView]];
        [(ScrollSynchronizableView *)[self view] setTextView:[(id<TextContentProviding>)contentDisplayController textView]];
        
        [placeHolderView setContentView:[contentDisplayController view]];
        [self reportLoadingComplete];        
    }
        
    [self displayTextForReference:@""];

    myIsViewLoaded = YES;
}



- (void)selectTableViewEntriesFromSelection {
    if(selection != nil) {
        [entriesTableView selectRowIndexes:[self selectedIndexes] byExtendingSelection:NO];
    }    
}

- (NSIndexSet *)selectedIndexes {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];

    for(NSString *key in selection) {
        NSUInteger index = [dictKeys indexOfObject:key];
        if(index > -1) {
            [indexes addIndex:index];
        }
    }
    
    return indexes;
}
         
         
#pragma mark - Methods

- (void)populateModulesMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    [[self modulesUIController] generateModuleMenu:menu 
                                     forModuletype:Dictionary
                                    withMenuTarget:self 
                                    withMenuAction:@selector(moduleSelectionChanged:)];
    [modulePopBtn setMenu:menu];
    
    // select module
    if(module != nil) {
        // on change, still exists?
        if(![[SwordManager defaultManager] moduleWithName:[module name]]) {
            // select the first one found
            NSArray *modArray = [[SwordManager defaultManager] modulesForType:Dictionary];
            if([modArray count] > 0) {
                [self setModule:modArray[0]];
                // and redisplay if needed
                [self displayTextForReference:searchString searchType:searchType];
            }
        }
        
        [modulePopBtn selectItemWithTitle:[module name]];
    }
}

- (void)setStatusText:(NSString *)aText {
    [statusLine setStringValue:aText];
}

/*
- (void)moduleChanged {
    [super moduleChanged];

    [selection removeAllObjects];
    if(module != nil) {
        self.dictKeys = [(SwordDictionary *)module allKeys];
    }
}
 */

- (NSAttributedString *)displayableHTMLForIndexedSearchResults:(NSArray *)searchResults {
    NSMutableAttributedString *ret = [[NSMutableAttributedString alloc] initWithString:@""];
    
    if(searchResults) {
        // strip searchQuery
        NSAttributedString *newLine = [[NSAttributedString alloc] initWithString:@"\n"];
        
        NSFont *normalDisplayFont = [[MBPreferenceController defaultPrefsController] normalDisplayFontForModuleName:[module name]];
        NSFont *boldDisplayFont = [[MBPreferenceController defaultPrefsController] boldDisplayFontForModuleName:[module name]];
        
        NSFont *keyFont = [NSFont fontWithName:[boldDisplayFont familyName]
                                          size:[self customFontSize]];
        NSFont *contentFont = [NSFont fontWithName:[normalDisplayFont familyName] 
                                              size:[self customFontSize]];

        NSDictionary *keyAttributes = @{NSFontAttributeName: keyFont};
        NSMutableDictionary *contentAttributes = [@{NSFontAttributeName: contentFont} mutableCopy];
        contentAttributes[NSForegroundColorAttributeName] = [UserDefaults colorForKey:DefaultsTextForegroundColor];
        
        // strip binary search tokens
        NSString *searchQuery = [NSString stringWithString:[Highlighter stripSearchQuery:searchString]];
        
        // build search string
        for(SearchResultEntry *entry in searchResults) {
            NSAttributedString *keyString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: ", [entry keyString]] attributes:keyAttributes];
            
            NSString *contentStr = @"";
            if([entry keyString] != nil) {
                contentStr = [(SwordDictionary *)module entryForKey:[entry keyString]];
            }
            
            NSAttributedString *contentString = [Highlighter highlightText:contentStr forTokens:searchQuery attributes:contentAttributes];
            [ret appendAttributedString:keyString];
            [ret appendAttributedString:newLine];
            [ret appendAttributedString:contentString];
            [ret appendAttributedString:newLine];
            [ret appendAttributedString:newLine];
        }
    }
    
    return ret;
}

- (NSAttributedString *)displayableHTMLForReferenceLookup {
    NSArray *keyArray = selection;
    [contentCache setCount:[keyArray count]];
    if([keyArray count] > 0) {        
        // generate html string for verses
        NSMutableString *htmlString = [NSMutableString string];
        for(NSString *key in keyArray) {
            NSArray *result = [module renderedTextEntriesForReference:key];
            NSString *text = @"";
            if([result count] > 0) {
                text = [result[0] text];
            }
            [htmlString appendFormat:@"<b>%@:</b><br />", key];
            [htmlString appendFormat:@"%@<br /><br />\n", text];
        }
        
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        options[NSCharacterEncodingDocumentOption] = @(NSUTF8StringEncoding);
        WebPreferences *webPrefs = [[MBPreferenceController defaultPrefsController] defaultWebPreferencesForModuleName:[[self module] name]];
        [webPrefs setDefaultFontSize:(int)customFontSize];
        options[NSWebPreferencesDocumentOption] = webPrefs;

        NSFont *normalDisplayFont = [[MBPreferenceController defaultPrefsController] normalDisplayFontForModuleName:[[self module] name]];
        NSFont *font = [NSFont fontWithName:[normalDisplayFont familyName] 
                                       size:(int)customFontSize];
        [[(id<TextContentProviding>)contentDisplayController scrollView] setLineScroll:[[[(id<TextContentProviding>)contentDisplayController textView] layoutManager] defaultLineHeightForFont:font]];

        NSData *data = [htmlString dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithHTML:data
                                                                                        options:options
                                                                             documentAttributes:nil];

        // set custom fore ground color
        [attrString addAttribute:NSForegroundColorAttributeName value:[UserDefaults colorForKey:DefaultsTextForegroundColor]
                                  range:NSMakeRange(0, [attrString length])];
        
        // add pointing hand cursor to all links
        CocoLog(LEVEL_DEBUG, @"setting pointing hand cursor...");
        NSRange effectiveRange;
        NSUInteger	i = 0;
        while (i < [attrString length]) {
            NSDictionary *attrs = [attrString attributesAtIndex:i effectiveRange:&effectiveRange];
            if(attrs[NSLinkAttributeName] != nil) {
                // add pointing hand cursor
                attrs = [attrs mutableCopy];
                ((NSMutableDictionary *) attrs)[NSCursorAttributeName] = [NSCursor pointingHandCursor];
                [attrString setAttributes:attrs range:effectiveRange];
            }
            i += effectiveRange.length;
        }
        CocoLog(LEVEL_DEBUG, @"setting pointing hand cursor...done");
        
        return attrString;
        
    } else {
        return [[NSMutableAttributedString alloc] init];
    }
}

#pragma mark - TextDisplayable protocol

- (BOOL)hasValidCacheObject {
    return searchType == IndexSearchType && [[searchContentCache reference] isEqualToString:searchString];
}

- (void)handleDisplayForReference {
    if([searchString length] > 0) {
        NSMutableArray *sel = [NSMutableArray array];
        Regex *regex = [Regex regexWithPattern:searchString];
        [regex setCaseSensitive:NO];
        for(NSString *key in [(SwordDictionary *)module allKeys]) {
            if([regex matchIn:key matchResult:nil] == RegexMatch) {
                [sel addObject:key];
            }
        }
        self.dictKeys = sel;
    } else {
        self.dictKeys = [(SwordDictionary *)module allKeys];
    }
    
    [entriesTableView reloadData];
    if([self.dictKeys count] == 1) {
        [entriesTableView selectAll:self];
    }    

    [contentCache setContent:[self displayableHTMLForReferenceLookup]];
}

- (void)handleDisplayStatusText {
    NSString *text;
    if(searchType == ReferenceSearchType) {
        text = [NSString stringWithFormat:@"Showing %ld entries out of %ld", [dictKeys count], [[(SwordDictionary *)module allKeys] count]];
    } else {
        NSInteger length = [searchContentCache count];
        text = [NSString stringWithFormat:@"Found %ld entries", length];
    }
    
    [self setStatusText:text];
}

#pragma mark - HostViewDelegate protocol

- (void)prepareContentForHost:(WindowHostController *)aHostController {
    [super prepareContentForHost:aHostController];
    [self displayTextForReference:searchString];
//    [self selectTableViewEntriesFromSelection];
}

- (NSString *)title {
    if(module != nil) {
        return [module name];
    }
    
    return @"DictView";
}

- (NSView *)rightAccessoryView {
    return sideBarView;
}

- (BOOL)showsRightSideBar {
    return YES;
}

- (SearchTextFieldOptions *)searchFieldOptions {
    SearchTextFieldOptions *options = [[SearchTextFieldOptions alloc] init];
    if(searchType == ReferenceSearchType) {
        [options setContinuous:YES];
        [options setSendsSearchStringImmediately:YES];
        [options setSendsWholeSearchString:NO];
    } else {
        [options setContinuous:NO];
        [options setSendsSearchStringImmediately:NO];
        [options setSendsWholeSearchString:YES];        
    }
    return options;
}

#pragma mark - SubviewHosting

- (void)removeSubview:(HostableViewController *)aViewController {
    // does nothing
}

- (void)contentViewInitFinished:(HostableViewController *)aView {
    if(myIsViewLoaded) {
        // set sync scroll view
        [(ScrollSynchronizableView *)[self view] setSyncScrollView:[(id<TextContentProviding>)contentDisplayController scrollView]];
        [(ScrollSynchronizableView *)[self view] setTextView:[(id<TextContentProviding>)contentDisplayController textView]];
        
        // add the web view as content view to the placeholder
        [placeHolderView setContentView:[aView view]];
        [self reportLoadingComplete];
    }
    
    [self adaptUIToHost];
}

#pragma mark - Actions

- (void)moduleSelectionChanged:(NSMenuItem *)sender {
    NSString *modName = @"";
    if([self module] != nil) {
        modName = [[self module] name];
    }
    if([sender isKindOfClass:[NSMenuItem class]]) {
        modName = [sender title];
    }
    if((module == nil) || (![modName isEqualToString:[module name]])) {
        self.module = [[SwordManager defaultManager] moduleWithName:modName];
        
        [selection removeAllObjects];
        [entriesTableView reloadData];
        
        if(self.searchString != nil) {
            forceRedisplay = YES;
            [self displayTextForReference:searchString searchType:searchType];
        }
    }
}

#pragma mark - NSTableView delegate methods

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	if(aNotification != nil) {
		NSTableView *oview = [aNotification object];
		if(oview != nil) {
            
			NSIndexSet *selectedRows = [oview selectedRowIndexes];
			NSUInteger len = [selectedRows count];
			NSMutableArray *sel = [NSMutableArray arrayWithCapacity:len];
            NSString *item;
			if(len > 0) {
				NSUInteger indexes[len];
				[selectedRows getIndexes:indexes maxCount:len inIndexRange:nil];
				
				for(int i = 0;i < len;i++) {
                    item = dictKeys[indexes[i]];
                    [sel addObject:item];
				}
            }
            
            self.selection = sel;
            [self displayTextForReference:searchString];
		} else {
			CocoLog(LEVEL_WARN,@"have a nil notification object!");
		}
	} else {
		CocoLog(LEVEL_WARN,@"have a nil notification!");
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return self.module == nil ? 0 : [dictKeys count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    return self.module == nil ? @"" : dictKeys[(NSUInteger) rowIndex];
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	// display call with std font
	NSFont *font = FontStd;
	[aCell setFont:font];
	// set row height according to used font
	// get font height
	//float imageHeight = [[(CombinedImageTextCell *)cell image] size].height; 
	CGFloat pointSize = [font pointSize];
	[aTableView setRowHeight:pointSize+4];
}

#pragma mark - NSCoding protocol

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if(self) {
        self.dictKeys = [(SwordDictionary *)module allKeys];

        NSArray *selectedKeys = (NSArray *)[decoder decodeObjectForKey:@"SelectedDictionaryKeys"];
        if(selectedKeys != nil) {
            [self setSelection:[NSMutableArray arrayWithArray:selectedKeys]];
        }
        
        [self commonInit];
    }
        
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {    
    [encoder encodeObject:selection forKey:@"SelectedDictionaryKeys"];
    
    [super encodeWithCoder:encoder];
}

@end

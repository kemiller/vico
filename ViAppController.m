#import "ViAppController.h"
#import "ViThemeStore.h"
#import "ViLanguageStore.h"
#import "ViDocument.h"
#import "ViDocumentView.h"
#import "ViDocumentController.h"
#import "ViPreferencesController.h"
#import "TMFileURLProtocol.h"
#import "TxmtURLProtocol.h"
#import "jscocoa/JSCocoa.h"
#import "json/JSON.h"

@implementation ViAppController

@synthesize lastSearchPattern;
@synthesize encodingMenu;

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSString *s = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];

	NSURL *url = [NSURL URLWithString:s];
	NSError *error = nil;
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES error:&error];
	if (error)
		[NSApp presentError:error];
}

- (id)init
{
	self = [super init];
	if (self) {
		[NSApp setDelegate:self];
		sharedBuffers = [[NSMutableDictionary alloc] init];

		[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
							  andSelector:@selector(getUrl:withReplyEvent:)
							forEventClass:kInternetEventClass
							   andEventID:kAEGetURL];
	}
	return self;
}

// Application Delegate method
// stops the application from creating an untitled document on load
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	return YES;
}

- (void)newBundleLoaded:(NSNotification *)notification
{
	/* Check if any open documents got a better language available. */
	ViDocument *doc;
	for (doc in [[NSDocumentController sharedDocumentController] documents])
		if ([doc respondsToSelector:@selector(configureSyntax)])
			[doc configureSyntax];
}

+ (NSString *)supportDirectory
{
	static NSString *supportDirectory = nil;
	if (supportDirectory == nil)
		supportDirectory = [@"~/Library/Application Support/Vibrant" stringByExpandingTildeInPath];
	return supportDirectory;
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	[[JSCocoa sharedController] setDelegate:self];

	[[NSFileManager defaultManager] createDirectoryAtPath:[ViAppController supportDirectory]
				  withIntermediateDirectories:YES
						   attributes:nil
							error:nil];

	NSUserDefaults *userDefs = [NSUserDefaults standardUserDefaults];

	/* initialize default defaults */
	[userDefs registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
	    [NSNumber numberWithInt:8], @"shiftwidth",
	    [NSNumber numberWithInt:8], @"tabstop",
	    [NSNumber numberWithBool:YES], @"autoindent",
	    [NSNumber numberWithBool:YES], @"ignorecase",
	    [NSNumber numberWithBool:NO], @"expandtabs",
	    [NSNumber numberWithBool:YES], @"number",
	    [NSNumber numberWithBool:YES], @"autocollapse",
	    [NSNumber numberWithBool:NO], @"hidetab",
	    [NSNumber numberWithBool:YES], @"searchincr",
	    [NSNumber numberWithBool:NO], @"showguide",
	    [NSNumber numberWithBool:NO], @"wrap",
	    [NSNumber numberWithBool:YES], @"antialias",
	    [NSNumber numberWithInt:80], @"guidecolumn",
	    [NSNumber numberWithFloat:11.0], @"fontsize",
	    @"vim", @"undostyle",
	    @"Menlo Regular", @"fontname",
	    @"Sunset", @"theme",
	    @"(CVS|_darcs|.svn|.git|~$|\\.bak$|\\.o$)", @"skipPattern",
	    [NSArray arrayWithObject:[NSDictionary dictionaryWithObject:@"textmate" forKey:@"username"]], @"bundleRepositoryUsers",
	    [NSNumber numberWithBool:YES], @"explorecaseignore",
	    [NSNumber numberWithBool:NO], @"exploresortfolders",
	    nil]];

	/* Initialize languages and themes. */
	[ViLanguageStore defaultStore];
	[ViThemeStore defaultStore];

	NSArray *opts = [NSArray arrayWithObjects:
	    @"theme", @"showguide", @"guidecolumn", @"undostyle", nil];
	for (NSString *opt in opts)
		[userDefs addObserver:self
			   forKeyPath:opt
			      options:NSKeyValueObservingOptionNew
			      context:NULL];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(newBundleLoaded:)
	                                             name:ViLanguageStoreBundleLoadedNotification
	                                           object:nil];

	const NSStringEncoding *encoding = [NSString availableStringEncodings];
	NSMutableArray *array = [NSMutableArray array];
	NSMenuItem *item;
	while (*encoding) {
		NSString *title = [NSString localizedNameOfStringEncoding:*encoding];
		item = [[NSMenuItem alloc] initWithTitle:title
						  action:@selector(setEncoding:)
					   keyEquivalent:@""];
		[item setRepresentedObject:[NSNumber numberWithUnsignedLong:*encoding]];
		[array addObject:item];
		encoding++;
	}

	NSSortDescriptor *sdesc = [[NSSortDescriptor alloc] initWithKey:@"title"
	                                                      ascending:YES];
	[array sortUsingDescriptors:[NSArray arrayWithObject:sdesc]];
	for (item in array)
		[encodingMenu addItem:item];

	[TMFileURLProtocol registerProtocol];
	[TxmtURLProtocol registerProtocol];

	shellConn = [NSConnection new];
	[shellConn setRootObject:self];
	[shellConn registerName:@"chunky bacon"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	ViDocument *doc;

	if ([keyPath isEqualToString:@"theme"]) {
		for (doc in [[NSDocumentController sharedDocumentController] documents])
			if ([doc respondsToSelector:@selector(changeTheme:)])
				[doc changeTheme:[[ViThemeStore defaultStore] themeWithName:[change objectForKey:NSKeyValueChangeNewKey]]];
	} else if ([keyPath isEqualToString:@"showguide"] || [keyPath isEqualToString:@"guidecolumn"]) {
		for (doc in [[NSDocumentController sharedDocumentController] documents])
			if ([doc respondsToSelector:@selector(updatePageGuide)])
				[doc updatePageGuide];
	} else if ([keyPath isEqualToString:@"undostyle"]) {
		NSString *undostyle = [change objectForKey:NSKeyValueChangeNewKey];
		INFO(@"got undo style %@", undostyle);
		if (![undostyle isEqualToString:@"vim"] && ![undostyle isEqualToString:@"nvi"])
			[[NSUserDefaults standardUserDefaults] setObject:@"vim" forKey:@"undostyle"];
	}
}

- (IBAction)showPreferences:(id)sender
{
	[[ViPreferencesController sharedPreferences] show];
}

- (NSMutableDictionary *)sharedBuffers
{
	return sharedBuffers;
}

extern BOOL makeNewWindowInsteadOfTab;

- (IBAction)newProject:(id)sender
{
#if 0
	NSError *error = nil;
	NSDocument *proj = [[NSDocumentController sharedDocumentController] makeUntitledDocumentOfType:@"Project" error:&error];
	if (proj) {
		[[NSDocumentController sharedDocumentController] addDocument:proj];
		[proj makeWindowControllers];
		[proj showWindows];
	}
	else {
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert runModal];
	}
#else
	makeNewWindowInsteadOfTab = YES;
	[[ViDocumentController sharedDocumentController] newDocument:sender];
#endif
}


#pragma mark -
#pragma mark Scripting console

- (void)consoleOutput:(NSString *)text
{
	NSTextStorage *ts = [scriptOutput textStorage];
	[ts replaceCharactersInRange:NSMakeRange([ts length], 0) withString:text];
	[scriptOutput scrollRangeToVisible:NSMakeRange([ts length], 0)];
}

- (void)JSCocoa:(JSCocoaController *)controller
       hadError:(NSString *)error
   onLineNumber:(NSInteger)lineNumber
    atSourceURL:(id)url
{
	if (evalFromShell) {
		if (url)
			lastEvalError = [NSString stringWithFormat:@"%@:%li: %@", url, lineNumber, error];
		else
			lastEvalError = [NSString stringWithFormat:@"%li: %@", lineNumber, error];
	} else
		[self consoleOutput:[NSString stringWithFormat:@"Error on line %li: %@\n", lineNumber, error]];
}

- (IBAction)evalScript:(id)sender
{
	JSCocoa *jsc = [JSCocoa sharedController];

	/* Set some convenient global objects. */
	ViWindowController *winCon = [ViWindowController currentWindowController];
	if (winCon) {
		[jsc setObject:winCon withName:@"window"];
		id<ViViewController> view = [winCon currentView];
		[jsc setObject:view withName:@"view"];
		if ([view isKindOfClass:[ViDocumentView class]]) {
			ViTextView *textView = [(ViDocumentView *)view textView];
			[jsc setObject:textView.proxy withName:@"text"];
		} else
			[jsc removeObjectWithName:@"text"];
		ViDocument *doc = [winCon currentDocument];
		[jsc setObject:doc withName:@"document"];
	} else {
		[jsc removeObjectWithName:@"window"];
		[jsc removeObjectWithName:@"view"];
		[jsc removeObjectWithName:@"text"];
		[jsc removeObjectWithName:@"document"];
	}

	JSValueRef result = [jsc evalJSString:[scriptInput stringValue]];
	if (result != NULL) {
		id obj = [jsc toObject:result];
		[self consoleOutput:[NSString stringWithFormat:@"%@\n", [obj JSONRepresentation]]];
	}
}

- (IBAction)clearConsole:(id)sender
{
	NSTextStorage *ts = [scriptOutput textStorage];
	[ts replaceCharactersInRange:NSMakeRange(0, [ts length]) withString:@""];
}

#pragma mark -
#pragma mark Shell commands

- (NSString *)eval:(NSString *)script
    withScriptPath:(NSString *)path
       errorString:(NSString **)errorString
{
	JSCocoa *jsc = [JSCocoa sharedController];

	evalFromShell = YES;
	JSValueRef result = [jsc evalJSString:script withScriptPath:path];
	evalFromShell = NO;
	if (result != NULL) {
		id obj = [jsc toObject:result];
		return [obj JSONRepresentation];
	} else if (errorString)
		*errorString = lastEvalError;
	lastEvalError = nil;
	return nil;
}

- (NSError *)openURL:(NSURL *)anURL
{
	/* Must make a complete copy of the URL, as it's not really
	 * a URL but a Distant Object proxy thingy. The document
	 * controller crashes otherwise.
	 */
	NSURL *url = [NSURL URLWithString:[anURL absoluteString]];

	NSError *error = nil;
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES error:&error];
	if (error == nil)
		[NSApp activateIgnoringOtherApps:YES];

	return error;
}

@end


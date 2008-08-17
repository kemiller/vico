#import "ViTextView.h"
#import "ViLanguageStore.h"

//#define DEBUG(...)
#define DEBUG NSLog

@interface ViSyntaxMatch : NSObject
{
	OGRegularExpressionMatch *beginMatch;
	OGRegularExpressionMatch *endMatch;
	NSMutableDictionary *pattern;
	int patternIndex;
	NSUInteger beginLocation;
	NSUInteger beginLength;
}
- (id)initWithMatch:(OGRegularExpressionMatch *)aMatch andPattern:(NSMutableDictionary *)aPattern atIndex:(int)i;
- (NSComparisonResult)sortByLocation:(ViSyntaxMatch *)match;
- (OGRegularExpression *)endRegexp;
- (NSUInteger)beginLocation;
- (NSUInteger)beginLength;
- (void)setBeginLocation:(NSUInteger)aLocation;
- (NSUInteger)endLocation;
- (void)setEndMatch:(OGRegularExpressionMatch *)aMatch;
- (NSString *)scope;
- (NSRange)matchedRange;
- (NSRange)matchedRangeExclusive;
- (NSMutableDictionary *)pattern;
- (OGRegularExpressionMatch *)beginMatch;
- (OGRegularExpressionMatch *)endMatch;
- (int)patternIndex;
- (BOOL)isSingleLineMatch;
@end

@implementation ViSyntaxMatch
- (id)initWithMatch:(OGRegularExpressionMatch *)aMatch andPattern:(NSMutableDictionary *)aPattern atIndex:(int)i
{
	self = [super init];
	if(self)
	{
		beginMatch = aMatch;
		pattern = aPattern;
		patternIndex = i;
		if(aMatch)
		{
			beginLocation = [aMatch rangeOfMatchedString].location;
			beginLength = [aMatch rangeOfMatchedString].length;
		}
	}
	return self;
}
- (NSComparisonResult)sortByLocation:(ViSyntaxMatch *)anotherMatch
{
	if([self beginLocation] < [anotherMatch beginLocation])
		return NSOrderedAscending;
	if([self beginLocation] > [anotherMatch beginLocation])
		return NSOrderedDescending;
	if([self patternIndex] < [anotherMatch patternIndex])
		return NSOrderedAscending;
	if([self patternIndex] > [anotherMatch patternIndex])
		return NSOrderedDescending;
	return NSOrderedSame;
}
- (OGRegularExpression *)endRegexp
{
	return [pattern objectForKey:@"endRegexp"];
}
- (NSUInteger)beginLocation
{
	return beginLocation;
}
- (NSUInteger)beginLength
{
	return beginLength;
}
- (void)setBeginLocation:(NSUInteger)aLocation
{
	// used for continued multi-line matches
	beginLocation = aLocation;
	beginLength = 0;
}
- (NSUInteger)endLocation
{
	if(endMatch)
		return NSMaxRange([endMatch rangeOfMatchedString]);
	else
		return NSMaxRange([beginMatch rangeOfMatchedString]); // FIXME: ???
}
- (void)setEndMatch:(OGRegularExpressionMatch *)aMatch
{
	endMatch = aMatch;
}
- (NSString *)scope
{
	return [pattern objectForKey:@"name"];
}
- (NSRange)matchedRange
{
	NSRange range = NSMakeRange([self beginLocation], [self endLocation] - [self beginLocation]);
	if(range.length < 0)
	{
		NSLog(@"negative length, beginLocation = %u, endLocation = %u", [self beginLocation], [self endLocation]);
		range.length = 0;
	}
	return range;
}
- (NSRange)matchedRangeExclusive
{
	NSRange range;
	range.location = [self beginLocation] + [self beginLength];
	range.length = [[self endMatch] rangeOfMatchedString].location - range.location;
	return range;
}
- (NSMutableDictionary *)pattern;
{
	return pattern;
}
- (OGRegularExpressionMatch *)beginMatch
{
	return beginMatch;
}
- (OGRegularExpressionMatch *)endMatch
{
	return endMatch;
}
- (int)patternIndex
{
	return patternIndex;
}
- (BOOL)isSingleLineMatch
{
	return [pattern objectForKey:@"begin"] == nil;
}
@end



@interface ViTextView (syntax_private)
- (ViSyntaxMatch *)highlightLineInRange:(NSRange)aRange continueWithMatch:(ViSyntaxMatch *)continuedMatch inScope:(NSArray *)patterns;
@end

@implementation ViTextView (syntax)

- (void)initHighlighting
{
	if(!syntax_initialized)
	{
		syntax_initialized = YES;
		DEBUG(@"ViLanguage = %@", language);
	}
}

- (void)applyScope:(NSString *)aScope inRange:(NSRange)aRange
{
	if(aScope == nil)
		return;

	NSUInteger l = aRange.location;
	while(l < NSMaxRange(aRange))
	{
		NSRange scopeRange;
		NSMutableArray *oldScopes = [[self layoutManager] temporaryAttribute:ViScopeAttributeName
								 atCharacterIndex:l
							    longestEffectiveRange:&scopeRange
									  inRange:NSMakeRange(l, NSMaxRange(aRange) - l)];
		NSMutableArray *scopes = [[NSMutableArray alloc] init];
		if(oldScopes)
		{
			[scopes addObjectsFromArray:oldScopes];
		}
		// append the new scope selector
		[scopes addObject:aScope];
		
		// apply (merge) the scope selector in the maximum range
		if(scopeRange.location < l)
		{
			scopeRange.length -= l - scopeRange.location;
			scopeRange.location = l;
		}
		if(NSMaxRange(scopeRange) > NSMaxRange(aRange))
			scopeRange.length = NSMaxRange(aRange) - l;

		DEBUG(@"   applying scopes [%@] to range %u + %u", [scopes componentsJoinedByString:@" "], scopeRange.location, scopeRange.length);		
		[[self layoutManager] addTemporaryAttribute:ViScopeAttributeName value:scopes forCharacterRange:scopeRange];

		// get the theme attributes for this collection of scopes
		NSDictionary *attributes = [theme attributesForScopes:scopes];
		[[self layoutManager] addTemporaryAttributes:attributes forCharacterRange:scopeRange];

		l = NSMaxRange(scopeRange);
	}
}

- (void)highlightMatch:(ViSyntaxMatch *)aMatch inRange:(NSRange)aRange
{
	[self applyScope:[aMatch scope] inRange:aRange];
}

- (void)highlightMatch:(ViSyntaxMatch *)aMatch
{
	[self highlightMatch:aMatch inRange:[aMatch matchedRange]];
}

- (void)highlightCaptures:(NSString *)captureType inPattern:(NSDictionary *)pattern withMatch:(OGRegularExpressionMatch *)aMatch
{
	NSDictionary *captures = [pattern objectForKey:captureType];
	if(captures == nil)
		captures = [pattern objectForKey:@"captures"];
	if(captures == nil)
		return;

	NSString *key;
	for(key in [captures allKeys])
	{
		NSDictionary *capture = [captures objectForKey:key];
		NSRange r = [aMatch rangeOfSubstringAtIndex:[key intValue]];
		if(r.length > 0)
		{
			[self applyScope:[capture objectForKey:@"name"] inRange:r];
		}
	}
}

- (void)highlightBeginCapturesInMatch:(ViSyntaxMatch *)aMatch
{
	[self highlightCaptures:@"beginCaptures" inPattern:[aMatch pattern] withMatch:[aMatch beginMatch]];
}

- (void)highlightEndCapturesInMatch:(ViSyntaxMatch *)aMatch
{
	[self highlightCaptures:@"endCaptures" inPattern:[aMatch pattern] withMatch:[aMatch endMatch]];
}

- (void)highlightCapturesInMatch:(ViSyntaxMatch *)aMatch
{
	[self highlightCaptures:@"captures" inPattern:[aMatch pattern] withMatch:[aMatch beginMatch]];
}

- (ViSyntaxMatch *)highlightSubpatternsForPattern:(NSMutableDictionary *)pattern inRange:(NSRange)range
{
	if(range.length == 0)
		return nil;
	NSArray *subPatterns = [language expandedPatternsForPattern:pattern];
	if(subPatterns)
	{
		DEBUG(@"  higlighting (%i) subpatterns inside [%@] in range %u + %u",
		      [subPatterns count], [pattern objectForKey:@"name"], range.location, range.length);
		return [self highlightLineInRange:range continueWithMatch:nil inScope:subPatterns];
	}
	return nil;
}

/* returns a continuation match if matches to EOL (ie, incomplete multi-line match)
 */
- (ViSyntaxMatch *)searchEndForMatch:(ViSyntaxMatch *)viMatch inRange:(NSRange)aRange
{
	DEBUG(@"searching for end match to [%@] in range %u + %u", [viMatch scope], aRange.location, aRange.length);
	OGRegularExpression *endRegexp = [viMatch endRegexp];
	if(endRegexp == nil)
	{
		NSLog(@"************* => compiling pattern with back references for scope [%@]", [viMatch scope]);
		endRegexp = [language compileRegexp:[[viMatch pattern] objectForKey:@"end"]
			 withBackreferencesToRegexp:[viMatch beginMatch]];
	}

	if(endRegexp)
	{
		// just get the first match
		OGRegularExpressionMatch *endMatch = [endRegexp matchInString:[storage string] range:aRange];
		[viMatch setEndMatch:endMatch];
		if(endMatch == nil)
		{
			NSRange range;
			range.location = [viMatch beginLocation];
			range.length = NSMaxRange(aRange) - range.location;
			DEBUG(@"got end match on [%@] from %u to EOL (%u)",
			      [[viMatch pattern] objectForKey:@"name"], [viMatch beginLocation], NSMaxRange(aRange));
			[self highlightMatch:viMatch inRange:range];

			// adjust aRange to be exclusive to a begin match
			range.location = [viMatch beginLocation] + [viMatch beginLength];
			range.length = NSMaxRange(aRange) - range.location;
			ViSyntaxMatch *cMatch = [self highlightSubpatternsForPattern:[viMatch pattern] inRange:range];
			if(cMatch)
				return cMatch;
			return viMatch;
		}
		else
		{
			DEBUG(@"got end match on [%@] at %u + %u    (prematch range = %u + %u)",
			      [[viMatch pattern] objectForKey:@"name"],
			      [[viMatch endMatch] rangeOfMatchedString].location,
			      [[viMatch endMatch] rangeOfMatchedString].length,
			      [[viMatch endMatch] rangeOfPrematchString].location,
			      [[viMatch endMatch] rangeOfPrematchString].length
			);
			if([[viMatch endMatch] rangeOfMatchedString].length == 0)
			{
				DEBUG(@"    FIXME: got zero-width match for pattern [%@]", [[viMatch pattern] objectForKey:@"end"]);
			}
			[self highlightMatch:viMatch];
			[self highlightEndCapturesInMatch:viMatch];
			
			// highlight sub-patterns within this match
			[self highlightSubpatternsForPattern:[viMatch pattern] inRange:[viMatch matchedRangeExclusive]];
		}
	}

	return nil;
}

- (ViSyntaxMatch *)highlightLineInRange:(NSRange)aRange continueWithMatch:(ViSyntaxMatch *)continuedMatch inScope:(NSArray *)patterns
{
	DEBUG(@"-----> line range = %u + %u", aRange.location, aRange.length);
	NSUInteger lastLocation = aRange.location;

	// should we continue on a multi-line match?
	if(continuedMatch)
	{
		DEBUG(@"continuing with match [%@]", [continuedMatch scope]);
		ViSyntaxMatch *cMatch = nil;
		cMatch = [self searchEndForMatch:continuedMatch inRange:aRange];
		if(cMatch)
			return cMatch;
		lastLocation = [continuedMatch endLocation];

		// adjust the line range
		if(lastLocation >= NSMaxRange(aRange))
			return nil;
		aRange.length = NSMaxRange(aRange) - lastLocation;
		aRange.location = lastLocation;
	}

	// keep an array of matches so we can sort it in order to skip matches embedded in other matches
	NSMutableArray *matchingPatterns = [[NSMutableArray alloc] init];
	NSMutableDictionary *pattern;
	if(patterns == nil)
	{
		// default to top-level patterns
		patterns = [language patterns];
	}
	int i = 0; // seems the patterns in textmate bundles are ordered
	for(pattern in patterns)
	{
		/* Match all patterns against this line. We can probably do something smarter here,
		 * like limiting the range after a match.
		 */

		OGRegularExpression *regexp = [pattern objectForKey:@"matchRegexp"];
		if(regexp == nil)
			regexp = [pattern objectForKey:@"beginRegexp"];
		if(regexp == nil)
			continue;
		NSArray *matches = [regexp allMatchesInString:[storage string] range:aRange];
		OGRegularExpressionMatch *match;
		for(match in matches)
		{
			ViSyntaxMatch *viMatch = [[ViSyntaxMatch alloc] initWithMatch:match andPattern:pattern atIndex:i];
			[matchingPatterns addObject:viMatch];
		}
		++i;
	}
	[matchingPatterns sortUsingSelector:@selector(sortByLocation:)];

	// highlight non-overlapping matches on this line
	// if we have a multi-line match, search for the end match
	ViSyntaxMatch *viMatch;
	for(viMatch in matchingPatterns)
	{
		// skip overlapping matches
		if([viMatch beginLocation] < lastLocation)
			continue;

		if([viMatch isSingleLineMatch])
		{
			[self highlightMatch:viMatch];
			[self highlightCapturesInMatch:viMatch];
		}
		else
		{
			DEBUG(@"got begin match on [%@] at %u + %u", [viMatch scope], [viMatch beginLocation], [viMatch beginLength]);
			NSRange range = aRange;
			range.location = NSMaxRange([[viMatch beginMatch] rangeOfMatchedString]);
			range.length = NSMaxRange(aRange) - range.location;
			ViSyntaxMatch *cMatch = [self searchEndForMatch:viMatch inRange:range];
			[self highlightBeginCapturesInMatch:viMatch];				
			if(cMatch)
				return cMatch;
		}
		lastLocation = [viMatch endLocation];
		// just return if we passed our line range
		if(lastLocation >= NSMaxRange(aRange))
			return nil;
	}

	return nil;
}

- (ViSyntaxMatch *)continuedMatchForLocation:(NSUInteger)location
{
	ViSyntaxMatch *continuedMatch = [[self layoutManager] temporaryAttribute:ViContinuationAttributeName
								atCharacterIndex:IMAX(0, location - 1)
								  effectiveRange:NULL];
	if(continuedMatch)
	{
		[continuedMatch setBeginLocation:location];
		DEBUG(@"detected previous scope [%@] at location %u", [continuedMatch scope], location);
	}
	return continuedMatch;
}

- (void)resetAttributesInRange:(NSRange)aRange
{
	NSDictionary *defaultAttributes = nil;
	if(language)
		defaultAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
					  [theme foregroundColor], NSForegroundColorAttributeName,
					  [NSArray arrayWithObject:[language name]], ViScopeAttributeName,
					  nil];
	else
		defaultAttributes = [NSDictionary dictionaryWithObject:[theme foregroundColor] forKey:NSForegroundColorAttributeName];
	[[self layoutManager] setTemporaryAttributes:defaultAttributes forCharacterRange:aRange];
}

- (void)highlightInRange:(NSRange)aRange restarting:(BOOL)isRestarting
{
	//DEBUG(@"%s range = %u + %u", _cmd, aRange.location, aRange.length);

	if(!syntax_initialized)
		[self initHighlighting];

	// if we're restarting, detect the previous scope so we can continue on a multi-line pattern, if any
	ViSyntaxMatch *continuedMatch = nil;
	if(isRestarting && aRange.location > 0)
	{
		continuedMatch = [self continuedMatchForLocation:aRange.location];
	}

	// reset attributes in the affected range
	[self resetAttributesInRange:aRange];

	// highlight each line separately
	NSUInteger nextRange = aRange.location;
	while(nextRange < NSMaxRange(aRange))
	{
		NSUInteger end;
		[self getLineStart:NULL end:&end contentsEnd:NULL forLocation:nextRange];
		if(end == nextRange || end == NSNotFound)
			break;
		NSRange line = NSMakeRange(nextRange, end - nextRange);
		// force begin location to start of line for continued matches
		[continuedMatch setBeginLocation:nextRange];
		continuedMatch = [self highlightLineInRange:line continueWithMatch:continuedMatch inScope:nil];
		nextRange = end;

		if(continuedMatch)
		{
			/* Mark the EOL character with the continuation pattern */
			// FIXME: maybe just store the pattern (pointer) instead?
			[[self layoutManager] addTemporaryAttribute:ViContinuationAttributeName value:continuedMatch forCharacterRange:NSMakeRange(end - 1, 1)];
		}
	}
}

- (void)highlightInWrappedRange:(NSValue *)wrappedRange
{
	[self highlightInRange:[wrappedRange rangeValue] restarting:YES];
}

/*
 * Update syntax colors.
 */
- (void)textStorageDidProcessEditing:(NSNotification *)notification
{
	if(language == nil)
		return;

	NSRange area = [storage editedRange];

	// extend our range along line boundaries.
	NSUInteger bol, eol;
	[[storage string] getLineStart:&bol end:&eol contentsEnd:NULL forRange:area];
	area.location = bol;
	area.length = eol - bol;

	if(area.length == 0)
		return;

	// temporary attributes don't work right when called from a notification
	[self performSelector:@selector(highlightInWrappedRange:) withObject:[NSValue valueWithRange:area] afterDelay:0];
}

- (void)highlightEverything
{
	if(language == nil)
	{
		[self resetAttributesInRange:NSMakeRange(0, [[storage string] length])];
		return;
	}
	DEBUG(@"%s begin highlighting", _cmd);
	[storage beginEditing];
	[self highlightInRange:NSMakeRange(0, [[storage string] length]) restarting:NO];
	[storage endEditing];
	DEBUG(@"%s end highlighting", _cmd);
}

@end

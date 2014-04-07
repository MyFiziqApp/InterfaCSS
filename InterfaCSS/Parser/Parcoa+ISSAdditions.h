//
//  Parcoa+ISSAdditions.h
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Created by Tobias Löfstrand on 2013-06-14.
//  Copyright (c) 2013 Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

#import "Parcoa.h"

typedef NSUInteger (^MatcherBlock)(NSString* input);

@interface Parcoa (ISSAdditions)

+ (ParcoaParser*) iss_quickUnichar:(unichar)c skipSpace:(BOOL)skipSpace;

+ (ParcoaParser*) iss_quickUnichar:(unichar)c;

+ (ParcoaParser*) iss_stringIgnoringCase:(NSString*)string;

+ (ParcoaParser*) iss_takeUntil:(MatcherBlock)block minCount:(NSUInteger)minCount;

+ (ParcoaParser*) iss_takeUntilInSet:(NSCharacterSet*)characterSet minCount:(NSUInteger)minCount;

+ (ParcoaParser*) iss_takeUntilChar:(unichar)character;

+ (ParcoaParser*) iss_anythingButBasicControlChars:(NSUInteger)minCount;

+ (ParcoaParser*) iss_anythingButWhiteSpaceAndControlChars:(NSUInteger)minCount;

+ (NSCharacterSet*) iss_validIdentifierCharsSet;

+ (ParcoaParser*) iss_validIdentifierChars:(NSUInteger)minCount;

+ (ParcoaParser*) iss_safeDictionary:(ParcoaParser*)parser;

+ (ParcoaResult*) iss_partialParserForPrefix:(NSString*)prefix input:(NSString*)input startIndex:(NSUInteger)i;

+ (ParcoaParser*) iss_parameterStringWithPrefixes:(NSArray*)prefixes;

+ (ParcoaParser*) iss_parameterStringWithPrefix:(NSString*)prefix;

+ (ParcoaParser*) iss_twoParameterFunctionParserWithName:(NSString*)name leftParameterParser:(ParcoaParser*)left rightParameterParser:(ParcoaParser*)right;

+ (ParcoaParser*) iss_nameValueSeparator;

+ (ParcoaParser*) iss_parseLineUpToInvalidCharactersInString:(NSString*)invalid;

+ (ParcoaParser*) iss_commentParser;

@end
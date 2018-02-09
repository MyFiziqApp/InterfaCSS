//
//  ISSStyleSheetParser.m
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT - http://www.github.com/tolo/InterfaCSS/blob/master/LICENSE
//

#import "ISSStyleSheetParser+Protected.h"
#import "ISSStyleSheetParser+Support.h"

#import "ISSMacros.h"

#import "ISSStyleSheetManager.h"
#import "ISSStylingManager.h"
#import "ISSPropertyManager.h"

#import "ISSParser.h"
#import "ISSStyleSheetPropertyParser.h"

#import "ISSSelector.h"
#import "ISSSelectorChain.h"
#import "ISSPropertyDeclaration.h"
#import "ISSRuleset.h"
#import "ISSNestedElementSelector.h"
#import "ISSPseudoClass.h"

#import "NSString+ISSAdditions.h"


#pragma mark - Helper functions

NSArray* iss_nonNullElementArray(NSArray* array) {
    if( [array indexOfObject:[NSNull null]] != NSNotFound ) {
        NSMutableArray* cleanArray = [NSMutableArray array];
        for(id entry in array) {
            if( entry != [NSNull null] ) [cleanArray addObject:entry];
        }
        return cleanArray;
    }
    return array;
}

id iss_elementOrNil(NSArray* array, NSUInteger index) {
    if( index < array.count ) {
        id element = array[index];
        if( element != [NSNull null] ) {
            if( [element isKindOfClass:NSArray.class] ) return iss_nonNullElementArray(element);
            return element;
        }
    }
    return nil;
}

id iss_elementOfTypeOrNil(NSArray* array, NSUInteger index, Class clazz) {
    id element = iss_elementOrNil(array, index);
    if ( [element isKindOfClass:clazz] ) {
        return element;
    } else {
        return nil;
    }
}

float iss_floatAt(NSArray* array, NSUInteger index) {
    return [array[index] floatValue];
}



#pragma mark - ISSStyleSheetParserBadData

@implementation ISSStyleSheetParserBadData

+ (instancetype) badDataWithDescription:(NSString*)badDataDescription {
    ISSStyleSheetParserBadData* styleSheetParserBadData = [[self alloc] init];
    styleSheetParserBadData.badDataDescription = badDataDescription;
    return styleSheetParserBadData;
}

- (NSString*) description {
    return self.badDataDescription;
}

@end


#pragma mark - ISSRulesetDeclaration

@implementation ISSRulesetDeclaration

+ (instancetype) rulesetWithSelectorChains:(NSMutableArray*)chains {
    return [ISSRulesetDeclaration rulesetWithSelectorChains:chains nestedElementKeyPath:nil];
}

+ (instancetype) rulesetWithSelectorChains:(NSMutableArray*)chains nestedElementKeyPath:(NSString*)nestedElementKeyPath {
    ISSRulesetDeclaration* rulesetDeclaration = [[ISSRulesetDeclaration alloc] init];
    rulesetDeclaration->_chains = chains;
    rulesetDeclaration->_nestedElementKeyPath = nestedElementKeyPath;
    return rulesetDeclaration;
}

- (instancetype) copyWithZone:(NSZone*)zone {
    ISSRulesetDeclaration* rulesetDeclaration = [[ISSRulesetDeclaration alloc] init];
    rulesetDeclaration->_chains = self.chains;
    rulesetDeclaration->_nestedElementKeyPath = self.nestedElementKeyPath;
    return rulesetDeclaration;
}

- (NSString*) description {
    return [NSString stringWithFormat:@"[%@ - %@]", self.chains, self.properties];
}

- (NSString*) displayDescription {
    return [[[ISSRuleset alloc] initWithSelectorChains:self.chains andProperties:nil] displayDescription:NO];
}

- (BOOL) isEqual:(id)object {
    if( object == self ) return YES;
    else if( [object isKindOfClass:ISSRulesetDeclaration.class] ) {
        if( ISS_ISEQUAL(self.chains, [object chains]) && ISS_ISEQUAL(self.properties, [(ISSRulesetDeclaration*)object properties]) ) return YES;
    }
    return NO;
}

@end


#pragma mark - ISSDeclarationExtension

@implementation ISSDeclarationExtension

+ (instancetype) extensionOfDeclaration:(ISSSelectorChain*)extendedDeclaration {
    ISSDeclarationExtension* extensionOfDeclaration = [[ISSDeclarationExtension alloc] init];
    extensionOfDeclaration->_extendedDeclaration = extendedDeclaration;
    return extensionOfDeclaration;
}

@end


#pragma mark - ISSCSSParser

@implementation ISSStyleSheetParser {
    NSCharacterSet* validVariableNameSet;
    ISSParser* cssParser;
}


#pragma mark - Property declarations and value transform

- (ISSPropertyDeclaration*) parsePropertyDeclaration:(NSString*)propertyNameString {
    // Parse parameters
    NSArray* parameters = nil;
    NSRange parentRange = [propertyNameString rangeOfString:@"("];
    if( parentRange.location != NSNotFound ) {
        NSRange endParentRange = [propertyNameString rangeOfString:@")"];
        if( endParentRange.location != NSNotFound ) {
            NSString* paramString = [propertyNameString substringWithRange:NSMakeRange(parentRange.location+1, endParentRange.location - parentRange.location - 1)];
            paramString = [self replaceVariableReferences:paramString didReplace:nil]; // Replace any variable references in parameter list
            parameters = [paramString componentsSeparatedByString:@","];
        }
        propertyNameString = [propertyNameString substringToIndex:parentRange.location];
    }
    
    // Remove any dashes from string and convert to lowercase string, before attempting to find matching ISSPropertyDeclaration
    propertyNameString = [[[propertyNameString iss_trim] stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    
    // Check for any key path in the property name
    NSString* prefixKeyPath = nil;
    NSRange dotRange = [propertyNameString rangeOfString:@"." options:NSBackwardsSearch];
    if( dotRange.location != NSNotFound && (dotRange.location+1) < propertyNameString.length ) {
        prefixKeyPath = [propertyNameString substringToIndex:dotRange.location];
        propertyNameString = [propertyNameString substringFromIndex:dotRange.location+1];
    }
    
    return [[ISSPropertyDeclaration alloc] initWithPropertyName:propertyNameString parameters:parameters nestedElementKeyPath:prefixKeyPath];
}

- (NSString*) replaceVariableReferences:(NSString*)propertyValue didReplace:(BOOL*)didReplace {
    NSUInteger location = 0;
    
    while( location < propertyValue.length ) {
        // Replace any variable references
        NSRange atRange = [propertyValue rangeOfString:@"@" options:0 range:NSMakeRange(location, propertyValue.length - location)];
        if( atRange.location != NSNotFound ) {
            location = atRange.location + atRange.length;
            
            // @ found, get variable name
            NSRange variableNameRange = NSMakeRange(location, 0);
            for(NSUInteger i=location; i<propertyValue.length; i++) {
                if( [validVariableNameSet characterIsMember:[propertyValue characterAtIndex:i]] ) {
                    variableNameRange.length++;
                } else break;
            }
            
            id variableValue = nil;
            id variableName = nil;
            if( variableNameRange.length > 0 ) {
                variableName = [propertyValue substringWithRange:variableNameRange];
                variableValue = [self.styleSheetManager valueOfStyleSheetVariableWithName:variableName];
            }
            if( variableValue ) {
                variableValue = [variableValue iss_trimQuotes];
                variableValue = [self replaceVariableReferences:variableValue didReplace:nil]; // Resolve nested variables
                
                // Replace variable occurrence in propertyValue string with variableValue string
                propertyValue = [propertyValue stringByReplacingCharactersInRange:NSMakeRange(atRange.location, variableNameRange.length+1)
                                                                       withString:variableValue];
                location += [variableValue length];
                
                if( didReplace ) *didReplace = YES;
            } else {
                ISSLogWarning(@"Unrecognized property variable: %@ (property value: %@)", variableName, propertyValue);
                location += variableNameRange.length;
            }
        } else break;
    }
    
    return propertyValue;
}


- (nullable id) parsePropertyValue:(NSString*)value asType:(ISSPropertyType)type {
    return [self parsePropertyValue:value asType:type replaceVariableReferences:YES didReplaceReplaceVariableReferences:nil];
}

- (nullable id) parsePropertyValue:(NSString*)value asType:(ISSPropertyType)type replaceVariableReferences:(BOOL)replaceVariableReferences {
    return [self parsePropertyValue:value asType:type replaceVariableReferences:replaceVariableReferences didReplaceReplaceVariableReferences:nil];
}

- (nullable id) parsePropertyValue:(NSString*)value asType:(ISSPropertyType)type replaceVariableReferences:(BOOL)replaceVariableReferences didReplaceReplaceVariableReferences:(BOOL*)didReplace {
    if( replaceVariableReferences ) {
        value = [self replaceVariableReferences:value didReplace:didReplace];
    }
    return [self.propertyParser parsePropertyValue:value ofType:type];
}


- (ISSPropertyDeclaration*) transformPropertyPair:(NSArray*)propertyPair {
    //    if( propertyPair[1] && [propertyPair[1] isKindOfClass:NSString.class] ) {
    NSString* propertyValue = [propertyPair[1] iss_trim];
    
    // Parse property declaration
    ISSPropertyDeclaration* decl = [self parsePropertyDeclaration:propertyPair[0]];
    
    // Check for special `current` keyword
    BOOL useCurrentValue = [[propertyValue iss_trim] iss_isEqualIgnoreCase:@"current"];
    
    // Perform lazy transformation of property value
    if( useCurrentValue ) {
        decl.rawValue = ISSPropertyDeclarationUseCurrentValue;
    } else {
        decl.valueTransformationBlock = ^id(ISSPropertyDeclaration* propertyDeclaration, ISSPropertyType propertyType, BOOL* containsVariables) {
            return [self parsePropertyValue:propertyValue asType:propertyType replaceVariableReferences:YES didReplaceReplaceVariableReferences:containsVariables];
        };
        decl.rawValue = propertyValue; // Raw value
    }
    
    return decl;
}


#pragma mark - Additional parser setup

- (ISSParser*) unrecognizedLineParser {
    return [self parseLineUpToInvalidCharactersInString:@"{}"];
}

- (ISSParser*) rulesetParserWithContentParser:(ISSParser*)rulesetContentParser selectorsChainsDeclarations:(ISSParser*)selectorsChainsDeclarations {
    return [[selectorsChainsDeclarations then:[rulesetContentParser between:self.openBraceSkipSpace and:self.closeBraceSkipSpace]] transform:^id(id value) {
        ISSRulesetDeclaration* rulesetDeclaration = value[0];
        rulesetDeclaration.properties = value[1];
        return rulesetDeclaration;
    } name:@"rulesetParser"];
}

- (ISSParser*) propertyParser:(ISSParser*)selectorsChainsDeclarations commentParser:(ISSParser*)commentParser selectorChainParser:(ISSParser*)selectorChainParser {
    __weak ISSStyleSheetParser* blockSelf = self;
    
    /** -- Unrecognized line -- **/
    ISSParser* unrecognizedLine = [[self unrecognizedLineParser] transform:^id(id value) {
        if( [value iss_hasData] ) return [ISSStyleSheetParserBadData badDataWithDescription:[NSString stringWithFormat:@"Unrecognized property line: '%@'", [value iss_trim]]];
        else return [NSNull null];
    } name:@"unrecognizedLine"];
    
    
    /** -- Property pair -- **/
    ISSParser* propertyPairParser = [[self propertyPairParser:NO] transform:^id(id value) {
        ISSPropertyDeclaration* declaration = [blockSelf transformPropertyPair:value];
        // If this declaration contains a reference to a nested element - return a nested ruleset declaration containing the property declaration, instead of the property declaration itself
        if( declaration.nestedElementKeyPath ) {
            ISSSelector* nestedElementSelector = [ISSNestedElementSelector selectorWithNestedElementKeyPath:declaration.nestedElementKeyPath];
            ISSSelectorChain* chain = [ISSSelectorChain selectorChainWithComponents:@[nestedElementSelector]];
            ISSRulesetDeclaration* ruleset = [ISSRulesetDeclaration rulesetWithSelectorChains:[@[chain] mutableCopy]];
            ruleset.properties = [@[declaration] mutableCopy];
            
            return @[[[ISSPropertyDeclaration alloc] initWithNestedElementKeyPathToRegister:declaration.nestedElementKeyPath], ruleset];
        } else {
            return declaration;
        }
    } name:@"propertyPair"];
    
    
    ISSParser* optional_s = [ISSParser optional:[ISSParser unichar:'s']];
    ISSParser* optionalColon = [ISSParser optional:[ISSParser sequential:@[[ISSParser optional: [ISSParser spaces]], [ISSParser unichar:':']]]];
    
    /** -- Extension/Inheritance -- **/
    ISSParser* extendDeclarationParser = [[ISSParser sequential:@[[ISSParser stringEQIgnoringCase:@"@extend"], optional_s, optionalColon, [ISSParser spaces], selectorChainParser, [ISSParser unichar:';' skipSpaces:YES]]] transform:^id(id value) {
        ISSSelectorChain* selectorChain = iss_elementOrNil(value, 4);
        return [ISSDeclarationExtension extensionOfDeclaration:selectorChain];
    } name:@"pseudoClassParameterParser"];
    
    
    
    // Create parser for unsupported nested declarations, to prevent those to interfere with current declarations
    NSCharacterSet* bracesSet = [NSCharacterSet characterSetWithCharactersInString:@"{}"];
    ISSParser* anythingButBraces = [ISSParser takeUntilInSet:bracesSet minCount:1];
    ISSParser* unsupportedNestedRulesetParser = [[anythingButBraces then:[anythingButBraces between:self.openBraceSkipSpace and:self.closeBraceSkipSpace]] transform:^id(id value) {
        return [ISSStyleSheetParserBadData badDataWithDescription:[NSString stringWithFormat:@"Unsupported nested ruleset: '%@'", value]];
    } name:@"unsupportedNestedRuleset"];
    
    
    // Create forward declaration for nested ruleset/declarations parser
    ISSParserWrapper* nestedRulesetParserProxy = [[ISSParserWrapper alloc] init];
    
    // Property declarations
    ISSParser* propertyParser = [ISSParser choice:@[commentParser, propertyPairParser, nestedRulesetParserProxy, extendDeclarationParser, unsupportedNestedRulesetParser, unrecognizedLine]];
    propertyParser = [propertyParser manyActualValuesFlat]; // Flattening since propertyPairParser may yield arrays...
    
    // Create parser for nested declarations
    ISSParser* nestedRulesetParser = [self rulesetParserWithContentParser:propertyParser selectorsChainsDeclarations:selectorsChainsDeclarations];
    
    nestedRulesetParserProxy.wrappedParser = nestedRulesetParser;
    
    return propertyParser;
}


#pragma mark - Parser setup

- (instancetype) init {
    return [self initWithPropertyParser:nil];
}

- (instancetype) initWithPropertyParser:(nullable id<ISSStyleSheetPropertyParsingDelegate>)propertyParser {
    if ( (self = [super init]) ) {
        __weak ISSStyleSheetParser* weakSelf = self;
        
        NSMutableCharacterSet* characterSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"_"];
        [characterSet formUnionWithCharacterSet:[NSCharacterSet letterCharacterSet]];
        _validInitialIdentifierCharacterCharsSet = [characterSet copy];
        
        characterSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"_"];
        [characterSet formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
        _validIdentifierExcludingMinusCharsSet = [characterSet copy];
        
        characterSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"-_"];
        [characterSet formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
        _validIdentifierCharsSet = [characterSet copy];
        
        characterSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"+-*/%^=≠<>≤≥|&!()."];
        [characterSet formUnionWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]];
        [characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
        _mathExpressionCharsSet = [characterSet copy];
        
        
        /** Common parsers setup **/
        _dot = [ISSParser unichar:'.'];
        _hashSymbol = [ISSParser unichar:'#'];
        _comma = [ISSParser unichar:','];
        _openBraceSkipSpace = [ISSParser unichar:'{' skipSpaces:YES];
        _closeBraceSkipSpace = [ISSParser unichar:'}' skipSpaces:YES];
        
        _identifier = [self validIdentifierChars:1];
        _anyName = [self anythingButWhiteSpaceAndExtendedControlChars:1];
        _anythingButControlChars = [self anythingButBasicControlChars:1];
        
        _plainNumber = [[ISSParser digit] concatMany1];
        ISSParser* fraction = [[_dot then:_plainNumber] concat];
        _plainNumber = [[_plainNumber then:[ISSParser optional:fraction defaultValue:@""]] concat];
        
        ISSParser* plus = [ISSParser unichar:'+' skipSpaces:YES];
        ISSParser* minus = [ISSParser unichar:'-' skipSpaces:YES];
        ISSParser* negativeNumber = [[minus keepRight:_plainNumber] transform:^id(id value) {
            return @(-[value doubleValue]);
        } name:@"negativeNumber"];
        ISSParser* positiveNumber = [plus keepRight:_plainNumber];
        positiveNumber = [[ISSParser choice:@[positiveNumber, _plainNumber]] transform:^id(id value) {
            return @([value doubleValue]);
        } name:@"positiveNumber"];
        _numberValue = [ISSParser choice:@[negativeNumber, positiveNumber]];
        
        _numberOrExpressionValue = [self mathExpressionParser];
        
        ISSParser* singleQuote = [ISSParser unichar:'\''];
        ISSParser* notSingleQuote = [ISSParser stringWithEscapesUpToUnichar:'\''];
        ISSParser* singleQuotedString = [[[singleQuote keepRight:notSingleQuote] keepLeft:singleQuote] transform:^id(id value) {
            return [NSString stringWithFormat:@"\'%@\'", value];
        } name:@"singleQuotedString"];
        
        ISSParser* doubleQuote = [ISSParser unichar:'\"'];
        ISSParser* notDoubleQuote = [ISSParser stringWithEscapesUpToUnichar:'\"'];
        ISSParser* doubleQuotedString = [[[doubleQuote keepRight:notDoubleQuote] keepLeft:doubleQuote] transform:^id(id value) {
            return [NSString stringWithFormat:@"\"%@\"", value];
        } name:@"doubleQuotedString"];
        
        _quotedString = [ISSParser choice:@[singleQuotedString, doubleQuotedString]];
        _quotedIdentifier = [[[singleQuote keepRight:_identifier] keepLeft:singleQuote] parserOr:[[doubleQuote keepRight:_identifier] keepLeft:doubleQuote]];
        
        
        /** Ruleset parser setup **/
        ISSParser* colon = [ISSParser unichar:':'];
        ISSParser* openParen = [ISSParser unichar:'('];
        ISSParser* closeParen = [ISSParser unichar:')'];


        /** Comments **/
        ISSParser* commentParser = [[self commentParser] transform:^id(id value) {
            ISSLogTrace(@"Comment: %@", [value iss_trim]);
            return [NSNull null];
        } name:@"commentParser"];


        /** Variables **/
        validVariableNameSet = [self validIdentifierCharsSet];
        ISSParser* variableParser = [[self propertyPairParser:YES] transform:^id(id value) {
            [weakSelf.styleSheetManager setValue:value[1] forStyleSheetVariableWithName:value[0]];
            return [NSNull null];
        } name:@"variableParser"];


        /** Selectors **/
        // Basic selector fragment parsers:
        ISSParser* typeName = [ISSParser choice:@[self.identifier, [ISSParser unichar:'*']]];
        ISSParser* classNamesSelector = [[self.dot keepRight:self.identifier] many1];
        ISSParser* elementIdSelector = [self.hashSymbol keepRight:self.identifier];

        // Pseudo class parsers:
        ISSParser* plusOrMinus = [ISSParser choice:@[ [ISSParser unichar:'+'], [ISSParser unichar:'-']]];
        ISSParser* pseudoClassParameterParserFull = [[ISSParser sequential:@[
                openParen, [ISSParser spaces], [ISSParser optional:plusOrMinus], [ISSParser optional:self.plainNumber], [ISSParser unichar:'n'], [ISSParser spaces],
                plusOrMinus, [ISSParser spaces], self.plainNumber, [ISSParser spaces], closeParen]]
        transform:^id(id value) {
            NSString* aModifier = iss_elementOrNil(value, 2) ?: @"";
            NSString* aValue = iss_elementOrNil(value, 3) ?: @"1";
            NSInteger a = [[aModifier stringByAppendingString:aValue] integerValue];
            NSString* bModifier = iss_elementOrNil(value, 6) ?: @"";
            NSString* bValue = iss_elementOrNil(value, 8);
            NSInteger b = [[bModifier stringByAppendingString:bValue] integerValue];
            return @[@(a), @(b)];
        } name:@"pseudoClassParameterFull"];
        ISSParser* pseudoClassParameterParserAN = [[ISSParser sequential:@[
                openParen, [ISSParser spaces], [ISSParser optional:plusOrMinus], [ISSParser optional:self.plainNumber], [ISSParser unichar:'n'], [ISSParser spaces], closeParen]]
        transform:^id(id value) {
            NSString* aModifier = iss_elementOrNil(value, 2) ?: @"";
            NSString* aValue = iss_elementOrNil(value, 3) ?: @"1";
            NSInteger a = [[aModifier stringByAppendingString:aValue] integerValue];
            return @[@(a), @0];
        } name:@"pseudoClassParameterAN"];
        ISSParser* pseudoClassParameterParserEven = [[ISSParser sequential:@[
                openParen, [ISSParser spaces], [ISSParser stringEQIgnoringCase:@"even"], [ISSParser spaces], closeParen]]
        transform:^id(id value) {
            return @[@2, @0];
        } name:@"pseudoClassParameterEven"];
        ISSParser* pseudoClassParameterParserOdd = [[ISSParser sequential:@[
                openParen, [ISSParser spaces], [ISSParser stringEQIgnoringCase:@"odd"], [ISSParser spaces], closeParen]]
        transform:^id(id value) {
            return @[@2, @1];
        } name:@"pseudoClassParameterOdd"];
        
        ISSParser* structuralPseudoClassParameterParsers = [ISSParser choice:@[pseudoClassParameterParserFull, pseudoClassParameterParserAN, pseudoClassParameterParserEven, pseudoClassParameterParserOdd]];
        ISSParser* pseudoClassParameterParser = [[ISSParser sequential:@[openParen, [ISSParser spaces], [ISSParser choice:@[self.quotedString, self.anyName]], [ISSParser spaces], closeParen]] transform:^id(id value) {
            return [iss_elementOrNil(value, 2) iss_trimQuotes];
        } name:@"pseudoClassParameterParser"];

        ISSParser* parameterizedPseudoClassSelector = [[ISSParser sequential:@[colon, self.identifier, [ISSParser choice:@[structuralPseudoClassParameterParsers, pseudoClassParameterParser]]]] transform:^id(id value) {
            NSString* pseudoClassName = iss_elementOrNil(value, 1) ?: @"";
            id pseudoClassParameters = iss_elementOrNil(value, 2);
            
            ISSPseudoClass* pseudoClass = nil;
            ISSPseudoClassType pseudoClassType = [weakSelf.styleSheetManager pseudoClassTypeFromString:pseudoClassName];
            
            if( [pseudoClassParameters isKindOfClass:NSArray.class] ) {
                NSArray* p = pseudoClassParameters;
                NSInteger a = [p[0] integerValue];
                NSInteger b = [p[1] integerValue];
                if ( pseudoClassType != ISSPseudoClassTypeUnknown ) {
                    pseudoClass = [[ISSPseudoClass alloc] initStructuralPseudoClassWithA:a b:b type:pseudoClassType];
                }
            } else if( [pseudoClassParameters isKindOfClass:NSString.class] ) {
                pseudoClass = [weakSelf.styleSheetManager createPseudoClassWithParameter:pseudoClassParameters type:pseudoClassType];
            }
            
            if( pseudoClass ) {
                return pseudoClass;
            } else {
                ISSLogWarning(@"Invalid pseudo class: %@", pseudoClassName);
                return [NSNull null];
            }
        } name:@"parameterizedPseudoClassSelector"];

        ISSParser* simplePseudoClassSelector = [[colon keepRight:self.identifier] transform:^id(id value) {
            NSString* pseudoClassName = value;
            ISSPseudoClassType pseudoClassType = [weakSelf.styleSheetManager pseudoClassTypeFromString:pseudoClassName];
            return [weakSelf.styleSheetManager createPseudoClassWithParameter:nil type:pseudoClassType];
        } name:@"simplePseudoClassSelector"];

        ISSParser* pseudoClassSelector = [[ISSParser choice:@[ parameterizedPseudoClassSelector, simplePseudoClassSelector ]] many];


        /* Actual selectors parsers: */

        // type #id .class [:pseudo]
        ISSParser* typeSelector1 = [[ISSParser sequential:@[ typeName, elementIdSelector, classNamesSelector, [ISSParser optional:pseudoClassSelector] ]] transform:^id(id value) {
            ISSSelector* selector = [weakSelf.styleSheetManager createSelectorWithType:iss_elementOrNil(value, 0) elementId:iss_elementOrNil(value, 1) styleClasses:iss_elementOrNil(value, 2) pseudoClasses:iss_elementOrNil(value, 3)];
            return selector ?: [NSNull null];
        } name:@"typeSelector1"];

        // type #id [:pseudo]
        ISSParser* typeSelector2 = [[ISSParser sequential:@[ typeName, elementIdSelector, [ISSParser optional:pseudoClassSelector] ]] transform:^id(id value) {
            ISSSelector* selector = [weakSelf.styleSheetManager createSelectorWithType:iss_elementOrNil(value, 0) elementId:iss_elementOrNil(value, 1) styleClasses:nil pseudoClasses:iss_elementOrNil(value, 2)];
            return selector ?: [NSNull null];
        } name:@"typeSelector2"];

        // type .class [:pseudo]
        ISSParser* typeSelector3 = [[ISSParser sequential:@[ typeName, classNamesSelector, [ISSParser optional:pseudoClassSelector] ]] transform:^id(id value) {
            ISSSelector* selector = [weakSelf.styleSheetManager createSelectorWithType:iss_elementOrNil(value, 0) elementId:nil styleClasses:iss_elementOrNil(value, 1) pseudoClasses:iss_elementOrNil(value, 2)];
            return selector ?: [NSNull null];
        } name:@"typeSelector3"];

        // type [:pseudo]
        ISSParser* typeSelector4 = [[ISSParser sequential:@[ typeName, [ISSParser optional:pseudoClassSelector] ]] transform:^id(id value) {
            ISSSelector* selector = [weakSelf.styleSheetManager createSelectorWithType:iss_elementOrNil(value, 0) elementId:nil styleClasses:nil pseudoClasses:iss_elementOrNil(value, 1)];
            return selector ?: [NSNull null];
        } name:@"typeSelector4"];

        // #id .class [:pseudo]
        ISSParser* elementSelector1 = [[ISSParser sequential:@[ elementIdSelector, classNamesSelector, [ISSParser optional:pseudoClassSelector] ]] transform:^id(id value) {
            ISSSelector* selector = [weakSelf.styleSheetManager createSelectorWithType:nil elementId:iss_elementOrNil(value, 0) styleClasses:iss_elementOrNil(value, 1) pseudoClasses:iss_elementOrNil(value, 2)];
            return selector ?: [NSNull null];
        } name:@"elementSelector1"];

        // #id [:pseudo]
        ISSParser* elementSelector2 = [[ISSParser sequential:@[ elementIdSelector, [ISSParser optional:pseudoClassSelector] ]] transform:^id(id value) {
            ISSSelector* selector = [weakSelf.styleSheetManager createSelectorWithType:nil elementId:iss_elementOrNil(value, 0) styleClasses:nil pseudoClasses:iss_elementOrNil(value, 1)];
            return selector ?: [NSNull null];
        } name:@"elementSelector2"];

        // .class [:pseudo]
        ISSParser* classSelector = [[ISSParser sequential:@[ classNamesSelector, [ISSParser optional:pseudoClassSelector] ]] transform:^id(id value) {
            ISSSelector* selector = [weakSelf.styleSheetManager createSelectorWithType:nil elementId:nil styleClasses:iss_elementOrNil(value, 0) pseudoClasses:iss_elementOrNil(value, 1)];
            return selector ?: [NSNull null];
        } name:@"classSelector"];

        ISSParser* simpleSelector = [ISSParser choice:@[typeSelector1, typeSelector2, typeSelector3, typeSelector4, elementSelector1, elementSelector2, classSelector]];


        // Selector combinator parsers:
        ISSParser* descendantCombinator = [[[ISSParser space] many1] transform:^id(id value) {
            return @(ISSSelectorCombinatorDescendant);
        } name:@"descendantCombinator"];
        ISSParser* childCombinator = [[ISSParser unichar:'>' skipSpaces:YES] transform:^id(id value) {
            return @(ISSSelectorCombinatorChild);
        } name:@"childCombinator"];
        ISSParser* adjacentSiblingCombinator = [[ISSParser unichar:'+' skipSpaces:YES] transform:^id(id value) {
            return @(ISSSelectorCombinatorAdjacentSibling);
        } name:@"adjacentSiblingCombinator"];
        ISSParser* generalSiblingCombinator = [[ISSParser unichar:'~' skipSpaces:YES] transform:^id(id value) {
            return @(ISSSelectorCombinatorGeneralSibling);
        } name:@"generalSiblingCombinator"];
        ISSParser* combinators = [ISSParser choice:@[generalSiblingCombinator, adjacentSiblingCombinator, childCombinator, descendantCombinator]];

        
        // Selector chain parsers:
        ISSParser* selectorChain = [[simpleSelector sepBy1Keep:combinators] transform:^id(NSArray* value) {
            id result = [ISSSelectorChain selectorChainWithComponents:value];
            if( !result ) {
                return [ISSStyleSheetParserBadData badDataWithDescription:[NSString stringWithFormat:@"Invalid selector chain: %@", [value componentsJoinedByString:@" "]]];
            }
            else return result;
        } name:@"selectorChain"];
        
        ISSParser* selectorsChainsDeclarations = [[[selectorChain skipSurroundingSpaces] sepBy1:self.comma] transform:^id(id value) {
            if( ![value isKindOfClass:NSArray.class] ) value = @[value];
            return [ISSRulesetDeclaration rulesetWithSelectorChains:value];
        } name:@"selectorsChainsDeclaration"];
        

        /** Properties **/
        ISSParser* propertyDeclarations = [self propertyParser:selectorsChainsDeclarations commentParser:commentParser selectorChainParser:selectorChain];
        
        /** Ruleset **/
        ISSParser* rulesetParser = [self rulesetParserWithContentParser:propertyDeclarations selectorsChainsDeclarations:selectorsChainsDeclarations];


        /** Unrecognized content **/
        ISSParser* unrecognizedContent = [[self unrecognizedLineParser] transform:^id(id value) {
            if( [value iss_hasData] ) return [ISSStyleSheetParserBadData badDataWithDescription:[NSString stringWithFormat:@"Unrecognized content: '%@'", [value iss_trim]]];
            else return [NSNull null];
        } name:@"unrecognizedContent"];

        cssParser = [[ISSParser choice:@[commentParser, variableParser, rulesetParser, unrecognizedContent]] manyActualValues];
        
        
        // Finally - create property parser, if needed
        _propertyParser = propertyParser ?: [[ISSStyleSheetPropertyParser alloc] init];
        [_propertyParser setupPropertyParsersWith:self];
    }
    return self;
}


#pragma mark - Property declaration processing (setup of nested declarations)

- (void) processProperties:(NSMutableArray*)properties withSelectorChains:(NSArray*)_selectorChains andAddToDeclarations:(NSMutableArray*)declarations {
    NSMutableArray* nestedDeclarations = [[NSMutableArray alloc] init];
    // Make sure selector chains are valid
    NSArray* selectorChains = [_selectorChains filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary* bindings) {
        return [evaluatedObject isKindOfClass:ISSSelectorChain.class];
    }]];
    
    if( selectorChains.count ) {
        NSMutableArray* propertyDeclarations = [[NSMutableArray alloc] init];
        ISSSelectorChain* extendedDeclarationSelectorChain = nil;

        for(id entry in properties) {
            ISSRulesetDeclaration* rulesetDeclaration = [entry isKindOfClass:ISSRulesetDeclaration.class] ? entry : nil;

            // Bad data:
            if( [entry isKindOfClass:ISSStyleSheetParserBadData.class] ) {
                ISSLogWarning(@"Warning! %@ - in declaration: %@", entry, [[[ISSRuleset alloc] initWithSelectorChains:selectorChains andProperties:nil] displayDescription:NO]);
            }
            // Nested property declaration (ISSSelectorChainsDeclaration):
            else if( rulesetDeclaration ) {
                // Construct new selector chains by appending selector to parent selector chains
                NSMutableArray* nestedSelectorChains = [[NSMutableArray alloc] init];
                for(ISSSelectorChain* selectorChain in rulesetDeclaration.chains) {
                    for(ISSSelectorChain* parentChain in selectorChains) {
                        if( [selectorChain isKindOfClass:ISSSelectorChain.class] ) {
                            [nestedSelectorChains addObject:[parentChain selectorChainByAddingDescendantSelectorChain:selectorChain]];
                        }
                    }
                }

                [nestedDeclarations addObject:@[rulesetDeclaration.properties, nestedSelectorChains]];
                
                // Add placeholder property definition for registration of nested element key path:
                if( rulesetDeclaration.nestedElementKeyPath ) {
                    [propertyDeclarations addObject:[[ISSPropertyDeclaration alloc] initWithNestedElementKeyPathToRegister:rulesetDeclaration.nestedElementKeyPath]];
                }
            }
            // ISSDeclarationExtension
            else if( [entry isKindOfClass:ISSDeclarationExtension.class] ) {
                extendedDeclarationSelectorChain = ((ISSDeclarationExtension*)entry).extendedDeclaration;
            }
            // ISSPropertyDeclaration
            else {
                [propertyDeclarations addObject:entry];
            }
        }

        // Add declaration
        [declarations addObject:[[ISSRuleset alloc] initWithSelectorChains:selectorChains andProperties:propertyDeclarations extendedDeclarationSelectorChain:extendedDeclarationSelectorChain]];

        // Process nested declarations
        for(NSArray* declarationPair in nestedDeclarations) {
            [self processProperties:declarationPair[0] withSelectorChains:declarationPair[1] andAddToDeclarations:declarations];
        }
    } else {
        ISSLogWarning(@"No valid selector chains in declaration (count before validation: %d) - properties: %@", _selectorChains.count, properties);
    }
}


#pragma mark - Parse stylesheet

- (NSMutableArray*) parse:(NSString*)styleSheetData {
    ISSParserStatus status = {};
    id result = [styleSheetData iss_hasData] ? [cssParser parse:styleSheetData status:&status] : nil;
    if( status.match ) {
        NSMutableArray* declarations = [NSMutableArray array];
        ISSRulesetDeclaration* lastElement = nil;
        
        for(id element in result) {
            // Valid declaration:
            if( [element isKindOfClass:[ISSRulesetDeclaration class]] ) {
                ISSRulesetDeclaration* rulesetDeclaration = element;
                [self processProperties:rulesetDeclaration.properties withSelectorChains:rulesetDeclaration.chains andAddToDeclarations:declarations];
                lastElement = element;
            }
            // Bad data:
            else if( [element isKindOfClass:ISSStyleSheetParserBadData.class] ) {
                if( lastElement ) {
                    ISSLogWarning(@"Warning! %@ - near %@", element, [lastElement displayDescription]);
                } else {
                    ISSLogWarning(@"Warning! %@ - near beginning of file", element);
                }
            }
        }
        
        ISSLogTrace(@"Parse result: \n%@", declarations);
        return declarations;
    } else {
        if( [styleSheetData iss_hasData] ) ISSLogWarning(@"Error parsing stylesheet: %@", result);
        else ISSLogWarning(@"Empty/nil stylesheet data!");
        return nil;
    }
}

@end


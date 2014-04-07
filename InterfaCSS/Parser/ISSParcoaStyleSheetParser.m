//
//  ISSParcoaStyleSheetParser.m
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Created by Tobias Löfstrand on 2013-06-14.
//  Copyright (c) 2013 Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

#import "ISSParcoaStyleSheetParser.h"

#import <objc/runtime.h>
#import "Parcoa.h"

#import "Parcoa+ISSAdditions.h"
#import "ISSSelector.h"
#import "ISSSelectorChain.h"
#import "ISSPropertyDeclarations.h"
#import "ISSPropertyDeclaration.h"
#import "NSObject+ISSLogSupport.h"
#import "NSString+ISSStringAdditions.h"
#import "UIColor+ISSColorAdditions.h"
#import "ISSRectValue.h"
#import "ISSPointValue.h"
#import "ISSLazyValue.h"
#import "ISSPseudoClass.h"
#import "InterfaCSS.h"


typedef void (^RectInsetBlock)(ISSRectValue* rectValue);


@implementation ISSParcoaStyleSheetParser {
    // Common parsers
    ParcoaParser *dot, *semiColonSkipSpace, *comma, *openBraceSkipSpace, *closeBraceSkipSpace,
            *untilSemiColon, *propertyNameValueSeparator, *anyName, *anythingButControlChars,
            *identifier, *number, *anyValue, *quotedString, *commentParser;

    NSCharacterSet* validVariableNameSet;

    NSMutableDictionary* propertyNameToProperty;
    NSMutableDictionary* typeToParser;
    ParcoaParser* enumValueParser;
    ParcoaParser* enumBitMaskValueParser;
    NSMutableDictionary* transformedValueCache;

    ParcoaParser* cssParser;
}


#pragma mark - Utils


- (BOOL) isRelativeValue:(NSString*)value {
    NSRange r = [value rangeOfString:@"%"];
    return r.location != NSNotFound && r.location > 0;
}

- (ParcoaParser*) unrecognizedLineParser {
    return [Parcoa iss_parseLineUpToInvalidCharactersInString:@"{}"];
}

- (id) elementOrNil:(NSArray*)array index:(NSUInteger)index {
    if( index < array.count ) {
        id element = array[index];
        if( element != [NSNull null] ) return element;
    }
    return nil;
}

#pragma mark - Property parsing

- (id) transformEnumValue:(NSString*)enumValue forProperty:(ISSPropertyDefinition*)p {
    id result = p.enumValues[[enumValue lowercaseString]];
    if( !result ) [self iss_logWarning:@"Warning! Unrecognized enum value: '%@'", enumValue];
    return result;
}

- (id) transformEnumBitMaskValues:(NSArray*)enumValues forProperty:(ISSPropertyDefinition*)p {
    NSNumber* result = nil;
    for(NSString* value in enumValues) {
        id enumValue = p.enumValues[[value lowercaseString]];
        if( enumValue ) {
            NSUInteger constVal = [enumValue unsignedIntegerValue];
            if( result ) result = @([result unsignedIntegerValue] | constVal);
            else result = @(constVal);
        } else [self iss_logWarning:@"Warning! Unrecognized enum value: '%@'", value];
    }
    return result;
}

- (NSArray*) basicColorValueParsers:(BOOL)cgColor {
    ParcoaParser* rgb = [[Parcoa iss_parameterStringWithPrefix:@"rgb"] transform:^id(id value) {
        NSArray* cc = [(NSString*) value iss_trimmedSplit:@","];
        UIColor* color;
        if( cc.count == 3 ) {
            color = [UIColor iss_colorWithR:[cc[0] intValue] G:[cc[1] intValue] B:[cc[2] intValue]];
        } else color = [UIColor magentaColor];
        if( cgColor ) return (id)color.CGColor;
        else return color;
    } name:@"rgb"];

    ParcoaParser* rgba = [[Parcoa iss_parameterStringWithPrefix:@"rgba"] transform:^id(id value) {
        NSArray* cc = [(NSString*) value iss_trimmedSplit:@","];
        UIColor* color;
        if( cc.count == 4 ) {
            color = [UIColor iss_colorWithR:[cc[0] intValue] G:[cc[1] intValue] B:[cc[2] intValue] A:[cc[3] floatValue]];
        } else color = [UIColor magentaColor];
        if( cgColor ) return (id)color.CGColor;
        else return color;
    } name:@"rgba"];

    NSMutableCharacterSet* hexDigitsSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"aAbBcCdDeEfF"];
    [hexDigitsSet formUnionWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]];

    ParcoaParser* hexColor = [[[Parcoa string:@"#"] keepRight:[Parcoa iss_takeUntilInSet:[hexDigitsSet invertedSet] minCount:6]] transform:^id(id value) {
        UIColor* color = [UIColor iss_colorWithHexString:value];
        if( cgColor ) return (id)color.CGColor;
        else return color;
    } name:@"hex"];

    ParcoaParser* preDefColor = [[Parcoa iss_takeUntilInSet:[[NSCharacterSet letterCharacterSet] invertedSet] minCount:1] transform:^id(id value) {
        UIColor* color = [UIColor magentaColor];
        NSString* colorString = [value lowercaseString];
        if( ![colorString hasSuffix:@"color"] ) colorString = [colorString stringByAppendingString:@"color"];

        unsigned int c = 0;
        Method* methods = class_copyMethodList(object_getClass([UIColor class]), &c);
        for(int i=0; i<c; i++) {
            NSString* selectorName = [[NSString alloc] initWithCString:sel_getName(method_getName(methods[i])) encoding:NSUTF8StringEncoding];
            if( [colorString iss_isEqualIgnoreCase:selectorName] ) {
                color = [UIColor performSelector:NSSelectorFromString(selectorName)];
                break;
            }
        }

        if( cgColor ) return (id)color.CGColor;
        else return color;
    } name:@"preDefColor"];

    return @[rgb, rgba, hexColor, preDefColor];
}

- (ParcoaParser*) colorParser:(BOOL)cgColor colorValueParsers:(NSArray*)colorValueParsers imageParser:(ParcoaParser*)imageParser {
    ParcoaParser* patternImageParser = [imageParser transform:^id(id value) {
        if( [value isKindOfClass:UIImage.class] ) return [UIColor colorWithPatternImage:value];
        else return [UIColor magentaColor];
    } name:@"patternImage"];

    ParcoaParser* gradientParser = [[Parcoa iss_twoParameterFunctionParserWithName:@"gradient" leftParameterParser:[Parcoa choice:colorValueParsers] rightParameterParser:[Parcoa choice:colorValueParsers]] transform:^id(id value) {
        return [[ISSLazyValue alloc] initWithLazyEvaluationBlock:^id(id uiObject) {
            if( [uiObject isKindOfClass:UIView.class] ) {
                CGRect frame = [uiObject frame];
                if( frame.size.height > 0 ) {
                    UIColor* color1 = value[0];
                    UIColor* color2 = value[1];
                    return [color1 iss_topDownLinearGradientToColor:color2 height:frame.size.height];
                } else return [UIColor clearColor];
            } else return [UIColor magentaColor];
        }];
    } name:@"gradient"];

    ParcoaParserForward* colorFunctionParserProxy = [ParcoaParserForward forwardWithName:@"colorFunctionParserProxy" summary:@""];

    colorValueParsers = [@[patternImageParser, gradientParser, colorFunctionParserProxy] arrayByAddingObjectsFromArray:colorValueParsers];

    ParcoaParser* colorFunctionParser = [[Parcoa sequential:@[identifier, [Parcoa iss_quickUnichar:'(' skipSpace:YES],
        [Parcoa choice:colorValueParsers], [Parcoa iss_quickUnichar:',' skipSpace:YES], anyName, [Parcoa iss_quickUnichar:')' skipSpace:YES]]] transform:^id(id value) {
            if( [value[2] isKindOfClass:UIColor.class] ) {
                if( [@"lighten" iss_isEqualIgnoreCase:value[0]] ) return [value[2] iss_colorByIncreasingBrightnessBy:[value[4] floatValue]];
                else if( [@"darken" iss_isEqualIgnoreCase:value[0]] ) return [value[2] iss_colorByIncreasingBrightnessBy:-[value[4] floatValue]];
                else if( [@"saturate" iss_isEqualIgnoreCase:value[0]] ) return [value[2] iss_colorByIncreasingSaturationBy:[value[4] floatValue]];
                else if( [@"desaturate" iss_isEqualIgnoreCase:value[0]] ) return [value[2] iss_colorByIncreasingSaturationBy:-[value[4] floatValue]];
                else if( [@"fadein" iss_isEqualIgnoreCase:value[0]] ) return [value[2] iss_colorByIncreasingAlphaBy:[value[4] floatValue]];
                else if( [@"fadeout" iss_isEqualIgnoreCase:value[0]] ) return [value[2] iss_colorByIncreasingAlphaBy:-[value[4] floatValue]];
                else return value[2];
            }
            return [UIColor magentaColor];
    } name:@"colorFunctionParser"];
    [colorFunctionParserProxy setImplementation:colorFunctionParser];

    return [Parcoa choice:colorValueParsers];
}

- (ISSPropertyDeclaration*) parsePropertyDeclaration:(NSString*)propertyNameString {
    // Parse parameters
    NSArray* parameters = nil;
    NSRange parentRange = [propertyNameString rangeOfString:@"("];
    if( parentRange.location != NSNotFound ) {
        NSRange endParentRange = [propertyNameString rangeOfString:@")"];
        if( endParentRange.location != NSNotFound ) {
            NSString* paramString = [propertyNameString substringWithRange:NSMakeRange(parentRange.location+1, endParentRange.location - parentRange.location - 1)];
            parameters = [paramString componentsSeparatedByString:@","];
        }
        propertyNameString = [propertyNameString substringToIndex:parentRange.location];
    }

    // Remove any dashes from string, before attempting to find matching ISSPropertyDeclaration
    propertyNameString = [[[propertyNameString iss_trim] stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];

    // Parse prefix
    NSString* prefix = nil;
    NSRange dotRange = [propertyNameString rangeOfString:@"." options:NSBackwardsSearch];
    if( dotRange.location != NSNotFound && (dotRange.location+1) < propertyNameString.length ) {
        prefix = [propertyNameString substringToIndex:dotRange.location];
        propertyNameString = [propertyNameString substringFromIndex:dotRange.location+1];
    }

    ISSPropertyDefinition* property = propertyNameToProperty[propertyNameString];
    if( !property && prefix ) property = propertyNameToProperty[[NSString stringWithFormat:@"%@.%@", prefix, propertyNameString]];

    // Transform parameters
    if( property && parameters ) {
        NSMutableArray* transformedParameters = [[NSMutableArray alloc] init];
        for(NSUInteger i=0; i<parameters.count; i++) { // Transform parameters to enum values
            NSString* param = [[parameters[i] iss_trim] lowercaseString];
            if( [param iss_hasData] ) {
                id paramValue = property.parameterEnumValues[param];
                if( paramValue ) [transformedParameters addObject:paramValue];
            }
        }
        parameters = transformedParameters;
    }

    if( property ) return [[ISSPropertyDeclaration alloc] initWithProperty:property parameters:parameters prefix:prefix];
    else return nil;
}

- (NSString*) replaceVariableReferences:(NSString*)propertyValue {
    NSUInteger location = 0;

    while( location < propertyValue.length ) {
        // Replace any variable references
        NSRange atRange = [propertyValue rangeOfString:@"@" options:0 range:NSMakeRange(location, propertyValue.length - location)];
        if( atRange.location != NSNotFound ) {
            location += atRange.location + atRange.length;

            // @ found, get variable name
            NSRange variableNameRange = NSMakeRange(location, 0);
            for(NSUInteger i=location; i<propertyValue.length; i++) {
                if( [validVariableNameSet characterIsMember:[propertyValue characterAtIndex:i]] ) {
                    variableNameRange.length++;
                } else break;
            }

            id variableValue = nil;
            if( variableNameRange.length > 0 ) {
                id variableName = [propertyValue substringWithRange:variableNameRange];
                variableValue = [[InterfaCSS interfaCSS] valueOfStyleSheetVariableWithName:variableName];
            }
            if( variableValue ) {
                // Replace variable occurrence in propertyValue string with variableValue string
                propertyValue = [propertyValue stringByReplacingCharactersInRange:NSMakeRange(atRange.location, variableNameRange.length+1)
                                                                       withString:variableValue];
                location += [variableValue length];
            } else {
                ISSLogWarning(@"Unrecognized property variable: %@", propertyValue);
                location += variableNameRange.length;
            }
        } else break;
    }

    return propertyValue;
}

- (UIFont*) fontWithSize:(UIFont*)font size:(CGFloat)size {
    if( [UIFont.class respondsToSelector:@selector(fontWithDescriptor:size:)] ) {
        return [UIFont fontWithDescriptor:font.fontDescriptor size:size];
    } else {
        return [font fontWithSize:size]; // Doesn't seem to work right in iOS7 (for some fonts anyway...)
    }
}

- (id) doTransformValue:(NSString*)propertyValue forProperty:(ISSPropertyDefinition*)p {
    // Enum property
    if( p.type == ISSPropertyTypeEnumType ) {
        ParcoaParser* parser;
        if( p.enumBitMaskType ) parser = enumBitMaskValueParser;
        else parser = enumValueParser;
        ParcoaResult* result = [parser parse:propertyValue];
        if( result.isOK ) {
            if( p.enumBitMaskType ) return [self transformEnumBitMaskValues:result.value forProperty:p];
            else return [self transformEnumValue:result.value forProperty:p];
        }
    }
    // Other properties
    else {
        ParcoaParser* valueParser = typeToParser[@(p.type)];
        ParcoaResult* result = [valueParser parse:propertyValue];
        if( result.isOK && result.value ) {
            return result.value;
        }
    }
    return nil;
}

- (NSArray*) transformPropertyPair:(NSArray*)propertyPair {
    if( propertyPair[1] && [propertyPair[1] isKindOfClass:NSString.class] ) {
        NSString* propertyValue = [propertyPair[1] iss_trim];

        propertyValue = [self replaceVariableReferences:propertyValue];

        // Parse property value
        ISSPropertyDeclaration* decl = [self parsePropertyDeclaration:propertyPair[0]];
        if( decl ) {
            ISSPropertyDefinition* p = decl.property;
            NSMutableDictionary* cache = transformedValueCache[p.uniqueTypeDescription];
            id transformedValue = cache[propertyValue];
            if( !cache ) {
                cache = [[NSMutableDictionary alloc] init];
                transformedValueCache[p.uniqueTypeDescription] = cache;
            }

            // Already transformed value
            if( transformedValue ) {
                return @[decl, transformedValue];
            } else {
                transformedValue = [self doTransformValue:propertyValue forProperty:p];
                if( transformedValue ) { // Update cache with transformed value
                    cache[propertyValue] = transformedValue;
                    return @[decl, transformedValue];
                }
            }
        }
    }

    ISSPropertyDeclaration* unrecognized = [[ISSPropertyDeclaration alloc] initWithUnrecognizedProperty:propertyPair[0]];
    ISSLogWarning(@"Unrecognized property '%@' with value: '%@'", propertyPair[0], propertyPair[1]);
    return @[unrecognized, propertyPair[1]];
}

- (UIImage*) imageNamed:(NSString*)name { // For testing purposes...
    return [UIImage imageNamed:name];
}

- (ParcoaParser*) propertyParsers:(ParcoaParser*)selectorsParser {
    propertyNameToProperty = [[NSMutableDictionary alloc] init];
    typeToParser = [[NSMutableDictionary alloc] init];

    // Build dictionary of all known property names mapped to ISSPropertyDefinitions
    NSSet* allProperties = [ISSPropertyDefinition propertyDefinitions];
    for(ISSPropertyDefinition* p in allProperties) {
        for(NSString* alias in p.allNames) {
            propertyNameToProperty[[alias lowercaseString]] = p;
        }
    }


    // String
    ParcoaParser* stringValueParser = [Parcoa choice:@[quotedString, anyName]];
    typeToParser[@(ISSPropertyTypeString)] = stringValueParser;


    // BOOL
    ParcoaParser* boolValueParser = [identifier transform:^id(id value) {
        return [NSNumber numberWithBool:[value boolValue]];
    } name:@"bool"];
    typeToParser[@(ISSPropertyTypeBool)] = boolValueParser;


    // Number
    ParcoaParser* numberValueParser = [number transform:^id(id value) {
        return [NSNumber numberWithFloat:[value floatValue]];
    } name:@"number"];
    typeToParser[@(ISSPropertyTypeNumber)] = numberValueParser;


    // CGRect
    // Ex: rect(0, 0, 320, 480)
    // Ex: size(320, 480)
    // Ex: size(50%, 70).right(5).top(5)     // TODO: min(50, *).max(500, *)
    // Ex: parent (=parent(0,0))
    // Ex: parent(10, 10) // dx, dy - CGRectInset
    // Ex: window (=window(0,0))
    // Ex: window(10, 10) // dx, dy - CGRectInset
    ParcoaParser* parentRectValueParser = [[[Parcoa iss_stringIgnoringCase:@"parent"] or:[Parcoa iss_stringIgnoringCase:@"superview"]] transform:^id(id value) {
        return [ISSRectValue parentRect];
    } name:@"parentRect"];

    ParcoaValueTransform parentInsetTransform = ^id(id value) {
        NSArray* c = [value iss_trimmedSplit:@","];
        if( c.count == 2 ) return [ISSRectValue parentInsetRectWithSize:CGSizeMake([c[0] floatValue], [c[1] floatValue])];
        else if( c.count == 4 ) return [ISSRectValue parentInsetRectWithInsets:UIEdgeInsetsMake([c[0] floatValue], [c[1] floatValue], [c[2] floatValue], [c[3] floatValue])];
        else return [ISSRectValue zeroRect];
    };
    ParcoaParser* parentInsetValueParser = [[Parcoa iss_parameterStringWithPrefixes:@[ @"parent", @"superview" ]] transform:parentInsetTransform name:@"parentRect.inset"];

    ParcoaParser* windowRectValueParser = [[Parcoa iss_stringIgnoringCase:@"window"] transform:^id(id value) {
        return [ISSRectValue windowRect];
    } name:@"windowRect"];

    ParcoaValueTransform windowInsetTransform = ^id(id value) {
        NSArray* c = [value iss_trimmedSplit:@","];
        if( c.count == 2 ) return [ISSRectValue windowInsetRectWithSize:CGSizeMake([c[0] floatValue], [c[1] floatValue])];
        else if( c.count == 4 ) return [ISSRectValue windowInsetRectWithInsets:UIEdgeInsetsMake([c[0] floatValue], [c[1] floatValue], [c[2] floatValue], [c[3] floatValue])];
        else return [ISSRectValue zeroRect];
    };
    ParcoaParser* windowInsetValueParser = [[Parcoa iss_parameterStringWithPrefix:@"window"] transform:windowInsetTransform name:@"windowRect.inset"];

    ParcoaParser* rectValueParser = [[Parcoa iss_parameterStringWithPrefix:@"rect"] transform:^id(id value) {
        NSArray* c = [value iss_trimmedSplit:@","];
        if( c.count == 4 ) return [ISSRectValue rectWithRect:CGRectMake([c[0] floatValue], [c[1] floatValue], [c[2] floatValue], [c[3] floatValue])];
        else return [ISSRectValue zeroRect];
    } name:@"rect"];

    ParcoaParser* rectSizeValueParser = [[Parcoa iss_parameterStringWithPrefix:@"size"] transform:^id(id value) {
        NSArray* c = [value iss_trimmedSplit:@","];
        if( c.count == 2 ) {
            BOOL autoWidth = [@"auto" iss_isEqualIgnoreCase:c[0]] || [@"*" isEqualToString:c[0]];
            CGFloat width = autoWidth ? ISSRectValueAuto : [c[0] floatValue];
            BOOL relativeWidth = autoWidth ? YES : [self isRelativeValue:c[0]];
            BOOL autoHeight = [@"auto" iss_isEqualIgnoreCase:c[1]] || [@"*" isEqualToString:c[1]];
            CGFloat height = autoHeight ? ISSRectValueAuto : [c[1] floatValue];
            BOOL relativeHeight = autoHeight ? YES : [self isRelativeValue:c[1]];
            return [ISSRectValue parentRelativeRectWithSize:CGSizeMake(width, height) relativeWidth:relativeWidth relativeHeight:relativeHeight];
        } else {
            return [ISSRectValue zeroRect];
        }
    } name:@"rectSize"];

    ParcoaParser* insetParser = [[Parcoa sequential:@[identifier, [Parcoa iss_quickUnichar:'(' skipSpace:YES], anyName, [Parcoa iss_quickUnichar:')' skipSpace:YES]]] transform:^id(id value) {
        return ^(ISSRectValue* rectValue) {
            if( [@"left" iss_isEqualIgnoreCase:value[0]] ) [rectValue setLeftInset:[value[2] floatValue] relative:[self isRelativeValue:value[2]]];
            else if( [@"right" iss_isEqualIgnoreCase:value[0]] ) [rectValue setRightInset:[value[2] floatValue] relative:[self isRelativeValue:value[2]]];
            else if( [@"top" iss_isEqualIgnoreCase:value[0]] ) [rectValue setTopInset:[value[2] floatValue] relative:[self isRelativeValue:value[2]]];
            else if( [@"bottom" iss_isEqualIgnoreCase:value[0]] ) [rectValue setBottomInset:[value[2] floatValue] relative:[self isRelativeValue:value[2]]];
            else ISSLogWarning(@"Unknown inset: %@", value[0]);
        };
    } name:@"insetParser"];

    ParcoaParser* partSeparator = [[Parcoa choice:@[[Parcoa space], dot]] many1];
    ParcoaParser* relativeRectParser = [[[Parcoa choice:@[rectSizeValueParser, insetParser]] sepBy:partSeparator] transform:^id(id value) {
        ISSRectValue* rectValue = [ISSRectValue zeroRect];
        if( [value isKindOfClass:[NSArray class]] ) {
            ISSRectValue* sizeValue = [ISSRectValue parentRelativeRectWithSize:CGSizeMake(ISSRectValueAuto, ISSRectValueAuto) relativeWidth:YES relativeHeight:YES];
            for(id element in value) {
                if( [element isKindOfClass:ISSRectValue.class] ) {
                    sizeValue = element;
                    break;
                }
            }
            for(id element in value) {
                if( ![element isKindOfClass:ISSRectValue.class] ) { // i.e. RectInsetBlock // TODO: Improve this "type" check
                    RectInsetBlock block = element;
                    block(sizeValue);
                }
            }
            return sizeValue;
        }
        return rectValue;
    } name:@"relativeRectParser"];

    typeToParser[@(ISSPropertyTypeRect)] = [Parcoa choice:@[rectValueParser,
                parentInsetValueParser, parentRectValueParser,
                windowInsetValueParser, windowRectValueParser,
                relativeRectParser, rectSizeValueParser]];


    // UIOffset
    ParcoaParser* offsetValueParser = [[Parcoa iss_parameterStringWithPrefix:@"offset"] transform:^id(id value) {
        NSArray* c = [(NSString*) value iss_trimmedSplit:@","];
        if( c.count == 2 ) {
            return [NSValue valueWithUIOffset:UIOffsetMake([c[0] floatValue], [c[1] floatValue])];
        } else return [NSValue valueWithUIOffset:UIOffsetZero];
    } name:@"offset"];
    typeToParser[@(ISSPropertyTypeOffset)] = offsetValueParser;


    // CGSize
    ParcoaParser* sizeValueParser = [[Parcoa iss_parameterStringWithPrefix:@"size"] transform:^id(id value) {
        NSArray* c = [(NSString*) value iss_trimmedSplit:@","];
        if( c.count == 2 ) {
            return [NSValue valueWithCGSize:CGSizeMake([c[0] floatValue], [c[1] floatValue])];
        } else return [NSValue valueWithCGSize:CGSizeZero];
    } name:@"size"];
    typeToParser[@(ISSPropertyTypeSize)] = sizeValueParser;


    // CGPoint
    // Ex: point(160, 240)
    // Ex: parent
    // Ex: parent(0, -100)
    // Ex: parent.relative(0, -100)
    ParcoaParser* parentCenterPointValueParser = [[[Parcoa iss_stringIgnoringCase:@"parent"] or:[Parcoa iss_stringIgnoringCase:@"superview"]] transform:^id(id value) {
        return [ISSPointValue parentCenter];
    } name:@"parentCenterPoint"];

    ParcoaValueTransform parentCenterRelativeTransform = ^id(id value) {
        NSArray* c = [value iss_trimmedSplit:@","];
        if( c.count == 2 ) return [ISSPointValue parentRelativeCenterPointWithPoint:CGPointMake([c[0] floatValue], [c[1] floatValue])];
        else return [ISSPointValue zeroPoint];
    };
    ParcoaParser* parentCenterRelativeValueParser = [[Parcoa iss_parameterStringWithPrefixes:@[ @"parent", @"superview" ]] transform:parentCenterRelativeTransform name:@"parentCenter.relative"];

    ParcoaParser* windowCenterPointValueParser = [[Parcoa iss_stringIgnoringCase:@"window"] transform:^id(id value) {
        return [ISSPointValue windowCenter];
    } name:@"windowCenterPoint"];

    ParcoaValueTransform windowCenterRelativeTransform = ^id(id value) {
        NSArray* c = [value iss_trimmedSplit:@","];
        if( c.count == 2 ) return [ISSPointValue windowRelativeCenterPointWithPoint:CGPointMake([c[0] floatValue], [c[1] floatValue])];
        else return [ISSPointValue zeroPoint];
    };
    ParcoaParser* windowCenterRelativeValueParser = [[Parcoa iss_parameterStringWithPrefix:@"window"] transform:windowCenterRelativeTransform name:@"windowCenter.relative"];

    ParcoaParser* pointValueParser = [[Parcoa iss_parameterStringWithPrefix:@"point"] transform:^id(id value) {
        NSArray* c = [(NSString*) value iss_trimmedSplit:@","];
        if( c.count == 2 ) return [ISSPointValue pointWithPoint:CGPointMake([c[0] floatValue], [c[1] floatValue])];
        else return [ISSPointValue zeroPoint];
    } name:@"point"];

    typeToParser[@(ISSPropertyTypePoint)] = [Parcoa choice:@[pointValueParser,
            parentCenterRelativeValueParser, parentCenterPointValueParser,
            windowCenterRelativeValueParser, windowCenterPointValueParser]];


    // UIEdgeInsets
    ParcoaParser* insetsValueParser = [[Parcoa iss_parameterStringWithPrefix:@"insets"] transform:^id(id value) {
        NSArray* c = [(NSString*) value iss_trimmedSplit:@","];
        if( c.count == 4 ) {
            return [NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake([c[0] floatValue], [c[1] floatValue], [c[2] floatValue], [c[3] floatValue])];
        } else return [NSValue valueWithUIEdgeInsets:UIEdgeInsetsZero];
    } name:@"insets"];
    typeToParser[@(ISSPropertyTypeEdgeInsets)] = insetsValueParser;


    // UIImage (1)
    // Ex: image.png
    // Ex: image(image.png);
    // Ex: image(image.png, 1, 2);
    // Ex: image(image.png, 1, 2, 3, 4);
    ParcoaParser* simpleImageParser = [[Parcoa choice:@[quotedString, [Parcoa sequential:@[identifier, dot, identifier]]]] transform:^id(id value) {
        UIImage* img;
        if( [value isKindOfClass:NSArray.class] ) img = [self imageNamed:[value componentsJoinedByString:@""]];
        else img = [self imageNamed:value];
        if( img ) return img;
        else return [NSNull null];
    } name:@"simpleImage"];
    ParcoaParser* imageParser = [[Parcoa iss_parameterStringWithPrefix:@"image"] transform:^id(id value) {
            NSArray* cc = [(NSString*) value iss_trimmedSplit:@","];
            UIImage* img = nil;
            if( cc.count > 0 ) {
                NSString* imageName = [cc[0] iss_trimQuotes];
                img = [self imageNamed:imageName];
                if( cc.count == 5 ) {
                    img = [img resizableImageWithCapInsets:UIEdgeInsetsMake([cc[1] floatValue], [cc[2] floatValue], [cc[3] floatValue], [cc[4] floatValue])];
                } else if( cc.count == 2 ) {
                    img = [img stretchableImageWithLeftCapWidth:[cc[1] intValue] topCapHeight:[cc[2] intValue]];
                }
            }
            if( img ) return img;
            else return [NSNull null];
        } name:@"image"];
    imageParser = [Parcoa choice:@[imageParser, simpleImageParser]];


    // UIColor
    NSArray* uiColorValueParsers = [self basicColorValueParsers:NO];
    ParcoaParser* colorPropertyParser = [self colorParser:NO colorValueParsers:uiColorValueParsers imageParser:imageParser];
    typeToParser[@(ISSPropertyTypeColor)] = colorPropertyParser;

    // CGColor
    NSArray* cgColorValueParsers = [self basicColorValueParsers:YES];
    ParcoaParser* cgColorPropertyParser = [self colorParser:YES colorValueParsers:cgColorValueParsers imageParser:imageParser];
    typeToParser[@(ISSPropertyTypeCGColor)] = cgColorPropertyParser;


    // UIImage (2)
    ParcoaParser* imageWithColorParser = [[Parcoa choice:uiColorValueParsers] transform:^id(id value) {
        return [value iss_asUIImage];
    } name:@"imageWithColor"];
    ParcoaParser* imageParsers = [Parcoa choice:@[imageParser, imageWithColorParser]];
    typeToParser[@(ISSPropertyTypeImage)] = imageParsers;


    // CGAffineTransform
    // Ex: rotate(90) scale(2,2) translate(100,100);
    ParcoaParser* rotateValueParser = [[Parcoa iss_parameterStringWithPrefix:@"rotate"] transform:^id(id value) {
            CGFloat angle = [value floatValue];
            angle = ((CGFloat)M_PI * angle / 180.0f);
            return [NSValue valueWithCGAffineTransform:CGAffineTransformMakeRotation(angle)];
        } name:@"rotate"];
    ParcoaParser* scaleValueParser = [[Parcoa iss_parameterStringWithPrefix:@"scale"] transform:^id(id value) {
            NSArray* c = [(NSString*) value iss_trimmedSplit:@","];
            if( c.count == 2 ) {
                return [NSValue valueWithCGAffineTransform:CGAffineTransformMakeScale([c[0] floatValue], [c[1] floatValue])];
            } else return [NSValue valueWithCGAffineTransform:CGAffineTransformIdentity];
        } name:@"scale"];
    ParcoaParser* translateValueParser = [[Parcoa iss_parameterStringWithPrefix:@"translate"] transform:^id(id value) {
        NSArray* c = [(NSString*) value iss_trimmedSplit:@","];
        if( c.count == 2 ) {
            return [NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation([c[0] floatValue], [c[1] floatValue])];
        } else return [NSValue valueWithCGAffineTransform:CGAffineTransformIdentity];
        } name:@"translate"];
    ParcoaParser* transformValuesParser = [[Parcoa many:[Parcoa choice:@[rotateValueParser, scaleValueParser, translateValueParser]]] transform:^id(id value) {
        CGAffineTransform transform = CGAffineTransformIdentity;
        if( [value isKindOfClass:[NSArray class]] ) {
            if( [value count] == 1 ) transform = [value[0] CGAffineTransformValue];
            else {
                for(NSValue* transformVal in value) {
                    transform = CGAffineTransformConcat(transform, transformVal.CGAffineTransformValue);
                }
            }
        }
        return [NSValue valueWithCGAffineTransform:transform];
    } name:@"transformValues"];
    typeToParser[@(ISSPropertyTypeTransform)] = transformValuesParser;


    // UIFont
    // Ex: Helvetica 12
    // Ex: bigger(@font, 1)
    // Ex: smaller(@font, 1)
    // Ex: fontWithSize(@font, 12)
    ParcoaParser* commaOrSpace = [[Parcoa choice:@[[Parcoa space], comma]] many1];
    ParcoaParser* fontValueParser = [Parcoa choice:@[quotedString, anyName]];
    fontValueParser = [[fontValueParser keepLeft:commaOrSpace] then:fontValueParser];
    fontValueParser = [fontValueParser transform:^id(id value) {
        CGFloat fontSize = [UIFont systemFontSize];
        NSString* fontName = nil;
        if( [value isKindOfClass:[NSArray class]] ) {
            for(NSString* stringVal in value) {
                NSString* lc = [stringVal.lowercaseString iss_trim];
                if( [lc hasSuffix:@"pt"] || [lc hasSuffix:@"px"] ) {
                    lc = [lc substringToIndex:lc.length-2];
                }

                if( lc.length > 0 ) {
                    if( lc.iss_isNumeric ) {
                        fontSize = [lc floatValue];
                    } else { // If not pt, px or comma
                        fontName = stringVal;
                    }
                }
            }
        }

        if( fontName ) return [UIFont fontWithName:fontName size:fontSize];
        else return [UIFont systemFontOfSize:fontSize];
    } name:@"font"];

    ParcoaParser* fontFunctionParser = [[Parcoa sequential:@[identifier, [Parcoa iss_quickUnichar:'(' skipSpace:YES],
        fontValueParser, [Parcoa iss_quickUnichar:',' skipSpace:YES], number, [Parcoa iss_quickUnichar:')' skipSpace:YES]]] transform:^id(id value) {
            if( [value[2] isKindOfClass:UIFont.class] ) {
                if( [@"bigger" iss_isEqualIgnoreCase:value[0]] ) return [self fontWithSize:value[2] size:[(UIFont*)value[2] pointSize] + [value[4] floatValue]];
                else if( [@"smaller" iss_isEqualIgnoreCase:value[0]] ) return [self fontWithSize:value[2] size:[(UIFont*)value[2] pointSize] - [value[4] floatValue]];
                else if( [@"fontWithSize" iss_isEqualIgnoreCase:value[0]] ) return [self fontWithSize:value[2] size:[value[4] floatValue]];
                else return value[2];
            }
            return [UIFont systemFontOfSize:[UIFont systemFontSize]];
    } name:@"fontFunctionParser"];

    typeToParser[@(ISSPropertyTypeFont)] = [Parcoa choice:@[fontFunctionParser, fontValueParser]];


    // Enums
    enumValueParser = identifier;
    enumBitMaskValueParser = [identifier sepBy:commaOrSpace];

    
    // Unrecognized line
    ParcoaParser* unrecognizedLine = [[self unrecognizedLineParser] transform:^id(id value) {
        if( [value iss_hasData] ) ISSLogWarning(@"Unrecognized property line: '%@'", [value iss_trim]);
        return [NSNull null];
    } name:@"unrecognizedLine"];
    

    // Property pair
    ParcoaParser* propertyPairParser = [[[anythingButControlChars keepLeft:propertyNameValueSeparator] then:[anythingButControlChars keepLeft:semiColonSkipSpace]] transform:^id(id value) {
        return [self transformPropertyPair:value];
    } name:@"propertyPair"];


    // Create parser for unsupported nested declarations, to prevent those to interfere with current declarations
    NSMutableCharacterSet* bracesSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"{}"];
    ParcoaParser* anythingButBraces = [Parcoa iss_takeUntilInSet:bracesSet minCount:1];
    ParcoaParser* unsupportedNestedRulesetParser = [[anythingButBraces then:[anythingButBraces between:openBraceSkipSpace and:closeBraceSkipSpace]] transform:^id(id value) {
        ISSLogWarning(@"Unsupported nested ruleset: '%@'", value);
        return [NSNull null];
    } name:@"unsupportedNestedRuleset"];

    // Create forward declaration for nested ruleset/declarations parser
    ParcoaParserForward* nestedRulesetParserProxy = [ParcoaParserForward forwardWithName:@"nestedRulesetParserProxy" summary:@""];

    // Property declarations
    ParcoaParser* propertyParser = [Parcoa choice:@[commentParser, propertyPairParser, nestedRulesetParserProxy, unsupportedNestedRulesetParser, unrecognizedLine]];
    propertyParser = [Parcoa iss_safeDictionary:[propertyParser many]];

    // Create parser for nested declarations (and unsupported nested declarations, to prevent those to interfere with current declarations)
    ParcoaParser* nestedRulesetParser = [selectorsParser then:[propertyParser between:openBraceSkipSpace and:closeBraceSkipSpace]];
    [nestedRulesetParserProxy setImplementation:nestedRulesetParser];

    return propertyParser;
}

#pragma mark - Parser setup

- (id) init {
    if ( (self = [super init]) ) {
        // Common parsers
        dot = [Parcoa iss_quickUnichar:'.'];
        ParcoaParser* colon = [Parcoa iss_quickUnichar:':'];
        semiColonSkipSpace = [Parcoa iss_quickUnichar:';' skipSpace:YES];
        comma = [Parcoa iss_quickUnichar:','];
        ParcoaParser* openParen = [Parcoa iss_quickUnichar:'('];
        ParcoaParser* closeParen = [Parcoa iss_quickUnichar:')'];
        openBraceSkipSpace = [Parcoa iss_quickUnichar:'{' skipSpace:YES];
        closeBraceSkipSpace = [Parcoa iss_quickUnichar:'}' skipSpace:YES];
        untilSemiColon = [Parcoa iss_takeUntilChar:';'];
        propertyNameValueSeparator = [Parcoa iss_nameValueSeparator];

        anyName = [Parcoa iss_anythingButWhiteSpaceAndControlChars:1];
        anythingButControlChars = [Parcoa iss_anythingButBasicControlChars:1];
        identifier = [Parcoa iss_validIdentifierChars:1];
        anyValue = untilSemiColon;

        number = [[Parcoa digit] concatMany1];
        ParcoaParser* fraction = [[dot then:number] concat];
        number = [[number then:[Parcoa option:fraction default:@""]] concat];

        ParcoaParser* quote = [Parcoa oneOf:@"'\""];
        ParcoaParser* notQuote = [Parcoa noneOf:@"'\""];
        quotedString = [[quote keepRight:[notQuote concatMany]] keepLeft:quote];


        // Comments
        commentParser = [[Parcoa iss_commentParser] transform:^id(id value) {
            ISSLogTrace(@"Comment: %@", [value iss_trim]);
            return [NSNull null];
        } name:@"commentParser"];


        // Variables
        validVariableNameSet = [Parcoa iss_validIdentifierCharsSet];
        ParcoaParser* variableParser = [[[[[[Parcoa iss_quickUnichar:'@'] keepRight:[identifier concatMany1]] skipSurroundingSpaces] keepLeft:propertyNameValueSeparator] then:[anyValue keepLeft:semiColonSkipSpace]] transform:^id(id value) {
            [[InterfaCSS interfaCSS] setValue:value[1] forStyleSheetVariableWithName:value[0]];
            return value;
        } name:@"variableParser"];


        // Selectors
        ParcoaParser* typeName = [Parcoa choice:@[identifier, [Parcoa iss_quickUnichar:'*']]];
        ParcoaParser* classNameSelector = [dot keepRight:identifier];
        ParcoaParser* plusOrMinus = [Parcoa choice:@[ [Parcoa iss_quickUnichar:'+'], [Parcoa iss_quickUnichar:'-']]];
        ParcoaParser* pseudoClassParameterParserFull = [[Parcoa sequential:@[
                openParen, [Parcoa spaces], [Parcoa optional:plusOrMinus], [Parcoa optional:number], [Parcoa iss_quickUnichar:'n'], [Parcoa spaces],
                plusOrMinus, [Parcoa spaces], number, [Parcoa spaces], closeParen]]
        transform:^id(id value) {
            NSString* aModifier = [self elementOrNil:value index:2] ?: @"";
            NSString* aValue = [self elementOrNil:value index:3] ?: @"1";
            NSInteger a = [[aModifier stringByAppendingString:aValue] integerValue];
            NSString* bModifier = [self elementOrNil:value index:6] ?: @"";
            NSString* bValue = [self elementOrNil:value index:8];
            NSInteger b = [[bModifier stringByAppendingString:bValue] integerValue];
            return @[@(a), @(b)];
        } name:@"pseudoClassParameterFull"];
        ParcoaParser* pseudoClassParameterParserAN = [[Parcoa sequential:@[
                openParen, [Parcoa spaces], [Parcoa optional:plusOrMinus], [Parcoa optional:number], [Parcoa iss_quickUnichar:'n'], [Parcoa spaces], closeParen]]
        transform:^id(id value) {
            NSString* aModifier = [self elementOrNil:value index:2] ?: @"";
            NSString* aValue = [self elementOrNil:value index:3] ?: @"1";
            NSInteger a = [[aModifier stringByAppendingString:aValue] integerValue];
            return @[@(a), @0];
        } name:@"pseudoClassParameterAN"];
        ParcoaParser* pseudoClassParameterParserEven = [[Parcoa sequential:@[
                openParen, [Parcoa spaces], [Parcoa iss_stringIgnoringCase:@"even"], [Parcoa spaces], closeParen]]
        transform:^id(id value) {
            return @[@2, @0];
        } name:@"pseudoClassParameterEven"];
        ParcoaParser* pseudoClassParameterParserOdd = [[Parcoa sequential:@[
                openParen, [Parcoa spaces], [Parcoa iss_stringIgnoringCase:@"odd"], [Parcoa spaces], closeParen]]
        transform:^id(id value) {
            return @[@2, @1];
        } name:@"pseudoClassParameterOdd"];
        
        ParcoaParser* pseudoClassParameterParsers = [Parcoa choice:@[pseudoClassParameterParserFull, pseudoClassParameterParserAN, pseudoClassParameterParserEven, pseudoClassParameterParserOdd]];

        ParcoaParser* pseudoClassSelector = [[Parcoa sequential:@[colon, identifier, [Parcoa optional:pseudoClassParameterParsers]]] transform:^id(id value) {
            NSString* pseudoClassName = [self elementOrNil:value index:1] ?: @"";
            pseudoClassName = [pseudoClassName stringByReplacingOccurrencesOfString:@"-" withString:@""];
            NSArray* p = [self elementOrNil:value index:2] ?: @[@1, @0];
            NSInteger a = [p[0] integerValue];
            NSInteger b = [p[1] integerValue];

            @try {
                ISSPseudoClassType pseudoClassType = [ISSPseudoClass pseudoClassTypeFromString:pseudoClassName];
                return [ISSPseudoClass pseudoClassWithA:a b:b type:pseudoClassType];
            } @catch (NSException* e) {
                ISSLogWarning(@"Invalid pseudo class: %@", pseudoClassName);
                return [NSNull null];
            }
        } name:@"pseudoClass"];

        ParcoaParser* typeSelector = [[Parcoa sequential:@[
                typeName, [Parcoa optional:classNameSelector], [Parcoa optional:pseudoClassSelector],
        ]] transform:^id(id value) {
            ISSSelector* selector = [ISSSelector selectorWithType:[self elementOrNil:value index:0] class:[self elementOrNil:value index:1] pseudoClass:[self elementOrNil:value index:2]];
            return selector ?: [NSNull null];
        } name:@"typeAndClassSelector"];

        ParcoaParser* classSelector = [[Parcoa sequential:@[
                classNameSelector, [Parcoa optional:pseudoClassSelector],
        ]] transform:^id(id value) {
            ISSSelector* selector = [ISSSelector selectorWithType:nil class:[self elementOrNil:value index:0] pseudoClass:[self elementOrNil:value index:1]];
            return selector ?: [NSNull null];
        } name:@"typeAndClassSelector"];

        ParcoaParser* simpleSelector = [Parcoa choice:@[classSelector, typeSelector]];

        ParcoaParser* descendantCombinator = [[[Parcoa space] many1] transform:^id(id value) {
            return @(ISSSelectorCombinatorDescendant);
        } name:@"descendantCombinator"];
        ParcoaParser* childCombinator = [[Parcoa iss_quickUnichar:'>' skipSpace:YES] transform:^id(id value) {
            return @(ISSSelectorCombinatorChild);
        } name:@"childCombinator"];
        ParcoaParser* adjacentSiblingCombinator = [[Parcoa iss_quickUnichar:'+' skipSpace:YES] transform:^id(id value) {
            return @(ISSSelectorCombinatorAdjacentSibling);
        } name:@"adjacentSiblingCombinator"];
        ParcoaParser* generalSiblingCombinator = [[Parcoa iss_quickUnichar:'~' skipSpace:YES] transform:^id(id value) {
            return @(ISSSelectorCombinatorGeneralSibling);
        } name:@"generalSiblingCombinator"];
        ParcoaParser* combinators = [Parcoa choice:@[generalSiblingCombinator, adjacentSiblingCombinator, childCombinator, descendantCombinator]];

        ParcoaParser* selectorChain = [[simpleSelector sepBy1Keep:combinators] transform:^id(id value) {
            id result = [ISSSelectorChain selectorChainWithComponents:value];
            if( !result ) {
                ISSLogWarning(@"Invalid selector chain: %@", value);
                return [NSNull null];
            }
            else return result;
        } name:@"selectorChain"];

        ParcoaParser* selectors = [[selectorChain skipSurroundingSpaces] sepBy1:comma];


        // Properties
        transformedValueCache = [[NSMutableDictionary alloc] init];
        ParcoaParser* propertyDeclarations = [self propertyParsers:selectors];

        ParcoaParser* rulesetParser = [[selectors then:[propertyDeclarations between:openBraceSkipSpace and:closeBraceSkipSpace]] dictionaryWithKeys:@[@"selectors", @"declarations"]];


         // Unrecognized content
        ParcoaParser* unrecognizedContent = [[self unrecognizedLineParser] transform:^id(id value) {
            if( [value iss_hasData] ) ISSLogWarning(@"Warning! Unrecognized content: '%@'", [value iss_trim]);
            return [NSNull null];
        } name:@"unrecognizedContent"];

        cssParser = [[Parcoa choice:@[commentParser, variableParser, rulesetParser, unrecognizedContent]] many];
    }
    return self;
}


#pragma mark - Property declaration processing (setup of nested declarations)

- (void) processProperties:(NSMutableDictionary*)properties withSelectorChains:(NSArray*)_selectorChains andAddToDeclarations:(NSMutableArray*)declarations {
    NSMutableArray* nestedDeclarations = [[NSMutableArray alloc] init];
    // Make sure selector chains are valid
    NSArray* selectorChains = [_selectorChains filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary* bindings) {
        return [evaluatedObject isKindOfClass:ISSSelectorChain.class];
    }]];

    if( selectorChains.count ) {
        for(id key in properties.allKeys) {
            if( [key isKindOfClass:NSArray.class] ) {
                // Remove mapping for nested selector chains in properties
                NSMutableDictionary* nestedProperties = properties[key];
                [properties removeObjectForKey:key];

                // Construct new selector chains by appending selector to parent selector chains
                NSMutableArray* nestedSelectorChains = [[NSMutableArray alloc] init];
                for(ISSSelectorChain* selectorChain in key) {
                    for(ISSSelectorChain* parentChain in selectorChains) {
                        if( [selectorChain isKindOfClass:ISSSelectorChain.class] ) {
                            [nestedSelectorChains addObject:[parentChain selectorChainByAddingDescendantSelectorChain:selectorChain]];
                        }
                    }
                }

                [nestedDeclarations addObject:@[nestedProperties, nestedSelectorChains]];
            }
        }

        // Add declaration
        [declarations addObject:[[ISSPropertyDeclarations alloc] initWithSelectorChains:selectorChains andProperties:properties]];

        // Process nested declarations
        for(NSArray* declarationPair in nestedDeclarations) {
            [self processProperties:declarationPair[0] withSelectorChains:declarationPair[1] andAddToDeclarations:declarations];
        }
    } else {
        ISSLogWarning(@"No valid selector chains in declaration (count before validation: %d) - properties: %@", _selectorChains.count, properties);
    }
}


#pragma mark - ISSStyleSheet interface

- (NSMutableArray*) parse:(NSString*)styleSheetData {
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];

    ParcoaResult* result = [styleSheetData iss_hasData] ? [cssParser parse:styleSheetData] : nil;
    if( result.isOK ) {
        ISSLogDebug(@"Done parsing stylesheet in %g seconds", ([NSDate timeIntervalSinceReferenceDate] - t));
        NSMutableArray* declarations = [NSMutableArray array];

        for(id element in result.value) {
            if( [element isKindOfClass:[NSDictionary class]] ) {
                NSDictionary* declaration = (NSDictionary*)element;

                NSMutableDictionary* properties = declaration[@"declarations"];
                NSArray* selectorChains = declaration[@"selectors"];

                [self processProperties:properties withSelectorChains:selectorChains andAddToDeclarations:declarations];
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

- (id) transformValue:(NSString*)value asPropertyType:(ISSPropertyType)propertyType {
    if( propertyType != ISSPropertyTypeEnumType ) {
        ISSPropertyDefinition* fauxDef = [[ISSPropertyDefinition alloc] initAnonymousPropertyDefinitionWithType:propertyType];
        return [self doTransformValue:value forProperty:fauxDef];
    } else {
        ISSLogWarning(@"Enum property type not allowed in %s", __PRETTY_FUNCTION__);
        return nil;
    }
}

- (id) transformValue:(NSString*)value forPropertyDefinition:(ISSPropertyDefinition*)propertyDefinition {
    return [self doTransformValue:value forProperty:propertyDefinition];
}

@end
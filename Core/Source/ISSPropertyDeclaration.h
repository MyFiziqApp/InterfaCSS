//
//  ISSPropertyDeclaration.h
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT - http://www.github.com/tolo/InterfaCSS/blob/master/LICENSE
//

#import "ISSPropertyDefinition.h"


NS_ASSUME_NONNULL_BEGIN


@class ISSPropertyDeclaration, ISSElementStylingProxy, ISSStyleSheetManager;


extern NSString* const ISSPropertyDeclarationUseCurrentValue;

// TODO: Rename to ISSPropertyValue?

/**
 * Represents the declaration of a property name/value pair in a stylesheet (i.e. name and value etc).
 */
@interface ISSPropertyDeclaration : NSObject<NSCopying>

@property (nonatomic, strong, readonly, nullable) NSString* propertyName;
@property (nonatomic, strong, readonly, nullable) NSString* nestedElementKeyPath;
@property (nonatomic, readonly) BOOL isNestedElementKeyPathRegistrationPlaceholder;
@property (nonatomic, strong, readonly) NSString* fqn;

@property (nonatomic, strong, readonly, nullable) NSString* rawValue;
@property (nonatomic, readonly) BOOL useCurrentValue;

@property (nonatomic, strong, readonly, nullable) NSArray<NSString*>* rawParameters;

@property (nonatomic, strong, readonly) NSString* stringRepresentation;

- (instancetype) initWithPropertyName:(NSString*)name rawValue:(nullable NSString*)rawValue rawParameters:(nullable NSArray<NSString*>*)rawParameters nestedElementKeyPath:(nullable NSString*)nestedElementKeyPath;
- (instancetype) initWithNestedElementKeyPathToRegister:(NSString*)nestedElementKeyPath;

@end


NS_ASSUME_NONNULL_END

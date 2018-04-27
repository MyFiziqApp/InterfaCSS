//
//  ISSPropertyDeclaration.h
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT - http://www.github.com/tolo/InterfaCSS/blob/master/LICENSE
//

#import "ISSPropertyDefinition.h"


NS_ASSUME_NONNULL_BEGIN


@class ISSPropertyDeclaration, ISSElementStylingProxy;


typedef id _Nullable (^ISSPropertyValueTransformationBlock)(ISSPropertyDeclaration* propertyDeclaration, ISSPropertyType propertyType, BOOL* containsVariables);


extern NSObject* const ISSPropertyDeclarationUseCurrentValue;



/**
 * Represents the declaration of a property in a stylesheet (i.e. name and value etc).
 */
@interface ISSPropertyDeclaration : NSObject<NSCopying>

@property (nonatomic, readonly, nullable) NSString* propertyName;
@property (nonatomic, readonly, nullable) NSString* nestedElementKeyPath;
@property (nonatomic, readonly) BOOL isNestedElementKeyPathRegistrationPlaceholder;

@property (nonatomic, readonly, nullable) NSArray* parameters;

@property (nonatomic, strong, nullable) id rawValue;
@property (nonatomic, readonly) BOOL useCurrentValue;
@property (nonatomic, copy, nullable) ISSPropertyValueTransformationBlock valueTransformationBlock;


- (instancetype) initWithPropertyName:(NSString*)name nestedElementKeyPath:(nullable NSString*)nestedElementKeyPath;
- (instancetype) initWithPropertyName:(NSString*)name parameters:(nullable NSArray*)parameters nestedElementKeyPath:(nullable NSString*)nestedElementKeyPath;
- (instancetype) initWithNestedElementKeyPathToRegister:(NSString*)nestedElementKeyPath;

- (nullable id) valueForProperty:(ISSPropertyDefinition*)property;
- (nullable id) valueForPropertyType:(ISSPropertyType)propertyType enumValueMapping:(nullable ISSPropertyEnumValueMapping*)enumValueMapping valueCacheKey:(nullable NSString*)valueCacheKey;

@end


NS_ASSUME_NONNULL_END

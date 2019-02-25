//
//  ISSProperty.h
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN


NS_SWIFT_NAME(PropertyType)
typedef NSString* ISSPropertyType NS_EXTENSIBLE_STRING_ENUM;

// TODO: Only define some property types here? 
extern ISSPropertyType const ISSPropertyTypeString;
extern ISSPropertyType const ISSPropertyTypeAttributedString;
extern ISSPropertyType const ISSPropertyTypeTextAttributes;
extern ISSPropertyType const ISSPropertyTypeBool;
extern ISSPropertyType const ISSPropertyTypeNumber;
extern ISSPropertyType const ISSPropertyTypeRelativeNumber;
extern ISSPropertyType const ISSPropertyTypeOffset;
extern ISSPropertyType const ISSPropertyTypeRect;
extern ISSPropertyType const ISSPropertyTypeSize;
extern ISSPropertyType const ISSPropertyTypePoint;
extern ISSPropertyType const ISSPropertyTypeEdgeInsets;
extern ISSPropertyType const ISSPropertyTypeColor;
extern ISSPropertyType const ISSPropertyTypeCGColor;
extern ISSPropertyType const ISSPropertyTypeTransform;
extern ISSPropertyType const ISSPropertyTypeFont;
extern ISSPropertyType const ISSPropertyTypeImage;
extern ISSPropertyType const ISSPropertyTypeEnumType;
extern ISSPropertyType const ISSPropertyTypeUnknown;




@class ISSProperty, ISSRuntimeProperty;


NS_SWIFT_NAME(PropertySetterBlock)
typedef BOOL (^ISSPropertySetterBlock)(ISSProperty* property, id target, id _Nullable value, NSArray* _Nullable parameters);
NS_SWIFT_NAME(PropertyParameterTransformer)
typedef _Nonnull id (^ISSPropertyParameterTransformer)(ISSProperty* property, NSString* parameterStringValue);


NS_SWIFT_NAME(PropertyEnumValueMapping)
@interface ISSPropertyEnumValueMapping : NSObject

@property (nonatomic, strong, readonly) NSDictionary* enumValues;
@property (nonatomic, strong, readonly) NSString* enumBaseName;
@property (nonatomic, strong, readonly, nullable) id defaultValue;

- (instancetype) initWithEnumValues:(NSDictionary*)enumValues enumBaseName:(NSString*)enumBaseName defaultValue:(nullable id)defaultValue;

- (id) enumValueFromString:(NSString*)string;

@end

NS_SWIFT_NAME(PropertyBitMaskEnumValueMapping)
@interface ISSPropertyBitMaskEnumValueMapping : ISSPropertyEnumValueMapping
@end



/**
 * Represents the definition of a property that can be declared in a stylesheet. 
 */
NS_SWIFT_NAME(Property)
@interface ISSProperty : NSObject

@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) NSString* normalizedName;

@property (nonatomic, strong, readonly) Class declaredInClass;

@property (nonatomic, strong, readonly) NSString* fqn;

@property (nonatomic, readonly) ISSPropertyType type;

@property (nonatomic, strong, readonly, nullable) ISSPropertyEnumValueMapping* enumValueMapping;

@property (nonatomic, strong, readonly, nullable) NSArray<ISSPropertyParameterTransformer>* parameterTransformers;

@property (nonatomic, copy, readonly, nullable) ISSPropertySetterBlock setterBlock;


- (instancetype) init NS_UNAVAILABLE;

- (instancetype) initCustomPropertyWithName:(NSString*)name inClass:(Class)clazz type:(ISSPropertyType)type enumValueMapping:(nullable ISSPropertyEnumValueMapping*)enumValueMapping
                      parameterTransformers:(nullable NSArray<ISSPropertyParameterTransformer>*)parameterTransformers setterBlock:(nullable ISSPropertySetterBlock)setter NS_DESIGNATED_INITIALIZER;

- (instancetype) initCustomPropertyWithName:(NSString*)name inClass:(Class)clazz type:(ISSPropertyType)type setterBlock:(ISSPropertySetterBlock)setter;

- (instancetype) initWithRuntimeProperty:(ISSRuntimeProperty*)runtimeProperty type:(ISSPropertyType)type enumValueMapping:(nullable ISSPropertyEnumValueMapping*)enumValueMapping;

- (instancetype) initParameterizedPropertyWithName:(NSString*)name inClass:(Class)clazz type:(ISSPropertyType)type selector:(SEL)selector enumValueMapping:(nullable ISSPropertyEnumValueMapping*)enumValueMapping
                             parameterTransformers:(NSArray<ISSPropertyParameterTransformer>*)parameterTransformers;


- (NSArray*) transformParameters:(NSArray*)rawParams;

- (BOOL) setValue:(nullable id)value onTarget:(nullable id)target withParameters:(nullable NSArray*)params;

+ (NSString*) normalizePropertyName:(NSString*)name;

@end

// TODO: Compound property support
//@interface ISSCompoundProperty : ISSProperty
//@end

NS_ASSUME_NONNULL_END
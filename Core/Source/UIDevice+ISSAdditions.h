//
//  UIDevice+ISSAdditions.h
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIDevice (ISSAdditions)

+ (NSString*) iss_deviceModelId;

+ (BOOL) iss_versionGreaterOrEqualTo:(NSString*)version;

+ (BOOL) iss_versionLessOrEqualTo:(NSString*)version;

@end

NS_ASSUME_NONNULL_END

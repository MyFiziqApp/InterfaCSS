//
//  ISSDateUtils.h
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

#import <Foundation/Foundation.h>


@interface ISSDateUtils : NSObject

+ (NSDate*) parseHttpDate:(NSString*)string;

+ (NSString*) formatHttpDate:(NSDate*)date;

@end

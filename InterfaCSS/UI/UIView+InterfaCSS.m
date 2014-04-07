//
//  UIView+InterfaCSS.m
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Created by Tobias Löfstrand on 2012-02-22.
//  Copyright (c) 2012 Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

#import "UIView+InterfaCSS.h"

#import "InterfaCSS.h"


@implementation UIView (InterfaCSS)

- (NSString*) getStyleClassISS {
    return [self.styleClassesISS anyObject];
}

- (void) setStyleClassISS:(NSString*)styleClass {
    [self setStyleClassesISS:[NSSet setWithObject:styleClass] animated:NO];
}

- (NSSet*) getStyleClassesISS {
    return [[InterfaCSS interfaCSS] styleClassesForUIElement:self];
}

- (void) setStyleClassesISS:(NSSet*)classes {
    [self setStyleClassesISS:classes animated:NO];
}

- (void) scheduleApplyStylingISS {
    [[InterfaCSS interfaCSS] scheduleApplyStyling:self animated:NO];
}

- (void) scheduleApplyStylingISS:(BOOL)animated {
    [[InterfaCSS interfaCSS] scheduleApplyStyling:self animated:animated];
}

- (void) setStyleClassesISS:(NSSet*)classes animated:(BOOL)animated {
    [[InterfaCSS interfaCSS] setStyleClasses:classes forUIElement:self];
    [self scheduleApplyStylingISS:animated];
}

- (void) setStyleClassISS:(NSString*)styleClass animated:(BOOL)animated {
    [self setStyleClassesISS:[NSSet setWithObject:styleClass]];
}

- (BOOL) hasStyleClassISS:(NSString*)styleClass {
    return [[InterfaCSS interfaCSS] uiElement:self hasStyleClass:styleClass];
}

- (void) addStyleClassISS:(NSString*)styleClass {
    [self addStyleClassISS:styleClass animated:NO];
}

- (void) addStyleClassISS:(NSString*)styleClass animated:(BOOL)animated {
    [[InterfaCSS interfaCSS] addStyleClass:styleClass forUIElement:self];
    [self scheduleApplyStylingISS:animated];
}

- (void) removeStyleClassISS:(NSString*)styleClass {
    [self removeStyleClassISS:styleClass animated:NO];
}

- (void) removeStyleClassISS:(NSString*)styleClass animated:(BOOL)animated {
    [[InterfaCSS interfaCSS] removeStyleClass:styleClass forUIElement:self];
    [self scheduleApplyStylingISS:animated];
}

- (void) applyStylingISS:(BOOL)invalidateStyles {
    if( invalidateStyles ) [[InterfaCSS interfaCSS] clearCachedStylesForUIElement:self];
    [[InterfaCSS interfaCSS] applyStyling:self];
}

- (void) applyStylingISS {
    [self applyStylingISS:NO];
}

- (void) applyStylingWithAnimationISS:(BOOL)invalidateStyles {
    if( invalidateStyles ) [[InterfaCSS interfaCSS] clearCachedStylesForUIElement:self];
    [[InterfaCSS interfaCSS] applyStylingWithAnimation:self];
}

- (void) applyStylingWithAnimationISS {
    [self applyStylingWithAnimationISS:NO];
}

@end
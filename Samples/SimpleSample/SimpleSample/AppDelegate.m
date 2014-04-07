//
//  AppDelegate.m
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Created by Tobias Löfstrand on 2012-02-24.
//  Copyright (c) 2012 Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

#import "AppDelegate.h"

#import "InterfaCSS.h"
#import "SimpleSampleViewController.h"
#import "PrototypeExampleViewController.h"
#import "UIView+InterfaCSS.h"


@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [[InterfaCSS interfaCSS] loadStyleSheetFromMainBundleFile:@"main.css"];
    
    // When developing your app, consider using an auto refreshable stylesheet that is loaded from a web server (or perhaps a cloud service like Dropbox,
    // Sugarsync etc) or the local file system.
//#if DEBUG == 1
//    [[InterfaCSS interfaCSS] loadRefreshableStyleSheetFromURL:[NSURL URLWithString:@"http://someserver/myprettystyles.css"]];
//#endif
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    SimpleSampleViewController* viewController = [[SimpleSampleViewController alloc] init];
    PrototypeExampleViewController* prototypeExampleViewController = [[PrototypeExampleViewController alloc] init];

    UITabBarController* tabBarController = [[UITabBarController alloc] init];
    tabBarController.tabBar.styleClassISS = @"tabBarStyle1";
    tabBarController.viewControllers = @[viewController, prototypeExampleViewController];
    tabBarController.selectedIndex = 0;
    
    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
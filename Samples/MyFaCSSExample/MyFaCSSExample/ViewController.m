//
//  ViewController.m
//  MyFaCSSExample
//
//  Created by Sean Smith on 12/12/19.
//  Copyright © 2019 MYQ. All rights reserved.
//

#import "ViewController.h"
#import <MyFaCSS/InterfaCSS.h>

@interface ViewController ()
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) InterfaCSS *css;
@property (assign, nonatomic) BOOL hasSetLayouts;
@end

@implementation ViewController

- (InterfaCSS *)css {
    return [InterfaCSS sharedInstance];
}

- (UILabel *)titleLabel {
    if (!_titleLabel) {
        _titleLabel = [[UILabel alloc] init];
        [self.css addStyleClass:@"main-view-controller-label" forUIElement:_titleLabel];
    }
    return _titleLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *stylePath = [[NSBundle mainBundle] pathForResource:@"MyFaCSSStyles" ofType:@"css"];
    [self.css loadStyleSheetFromFile:stylePath];
    [self.css addStyleClass:@"main-view-controller" forUIElement:self.view];
    [self.view addSubview:self.titleLabel];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (!self.hasSetLayouts) {
        self.hasSetLayouts = YES;
        [self.css applyStyling:self.view includeSubViews:YES];
    }
}

@end

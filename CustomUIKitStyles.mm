/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "CustomUIKitStyles.h"

UIColor* const       redButtonColorWithAlpha = [UIColor colorWithRed:230.0f/255  green:72.0f/255   blue:64.0f/255  alpha:0.85];
UIColor* const      blueButtonColorWithAlpha = [UIColor colorWithRed:0.160784314 green:0.670588235 blue:0.88627451 alpha:0.85];
UIColor* const  blueGrayButtonColorWithAlpha = [UIColor colorWithRed:64.0f/255   green:110.0f/255  blue:117.0f/255 alpha:0.85];
UIColor* const  redButtonColorWithLightAlpha = [UIColor colorWithRed:230.0f/255  green:72.0f/255   blue:64.0f/255  alpha:0.45];
UIColor* const blackLabelColorWithLightAlpha = [UIColor colorWithRed:0.0         green:0.0         blue:0.0        alpha:0.2];

@implementation UIButton (customStyle)

- (void)applyCustomStyleWithBackgroundColor:(UIColor*)color {

    self.layer.cornerRadius = 15.0f;
    self.backgroundColor = color;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.layer.borderColor = [UIColor whiteColor].CGColor;
    self.layer.borderWidth = 2.0f;

    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];

    self.titleLabel.font = [UIFont fontWithName:@"Helvetica Neue" size:16.0];
}

@end



@implementation UILabel (customStyle)

- (void)applyCustomStyleWithBackgroundColor:(UIColor*)color {
    self.layer.cornerRadius = 15.f;
    self.backgroundColor = color;
    self.textColor = [UIColor whiteColor];
    self.layer.masksToBounds = YES;
}

@end

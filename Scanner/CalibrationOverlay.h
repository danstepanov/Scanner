/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>

@interface CalibrationOverlay : UIView

+ (CalibrationOverlay*) calibrationOverlaySubviewOf: (UIView*) view atOrigin: (CGPoint) origin;
+ (CalibrationOverlay*) calibrationOverlaySubviewOf: (UIView*) view atCenter: (CGPoint) center;

@end

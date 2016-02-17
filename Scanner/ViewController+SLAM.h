/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#define HAS_LIBCXX

#import "ViewController.h"
#import <Structure/Structure.h>
#import <Structure/StructureSLAM.h>

#import "MeshViewController.h"

@interface ViewController (SLAM)

- (void)setupSLAM;
- (void)resetSLAM;
- (void)clearSLAM;
- (void)processDepthFrame:(STDepthFrame *)depthFrame
          colorFrameOrNil:(STColorFrame *)colorFrame;

@end

/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "ViewController+Camera.h"
#import "ViewController+Sensor.h"
#import "ViewController+SLAM.h"
#import "ViewController+OpenGL.h"

#include <cmath>

// Needed to determine platform string
#include <sys/types.h>
#include <sys/sysctl.h>

#pragma mark - Utilities

namespace // anonymous namespace for local functions.
{
    BOOL isIpadAir2()
    {
        const char* kernelStringName = "hw.machine";
        NSString* deviceModel;
        {
            size_t size;
            sysctlbyname(kernelStringName, NULL, &size, NULL, 0); // Get the size first
            
            char *stringNullTerminated = (char*)malloc(size);
            sysctlbyname(kernelStringName, stringNullTerminated, &size, NULL, 0); // Now, get the string itself
            
            deviceModel = [NSString stringWithUTF8String:stringNullTerminated];
            free(stringNullTerminated);
        }
        
        if ([deviceModel isEqualToString:@"iPad5,3"]) return YES; // Wi-Fi
        if ([deviceModel isEqualToString:@"iPad5,4"]) return YES; // Wi-Fi + LTE
        return NO;
    }
    
    BOOL getDefaultHighResolutionSettingForCurrentDevice()
    {
        // iPad Air 2 can handle 30 FPS high-resolution, so enable it by default.
        if (isIpadAir2())
            return TRUE;
        
        // Older devices can only handle 15 FPS high-resolution, so keep it disabled by default
        // to avoid showing a low framerate.
        return FALSE;
    }
} // anonymous

#pragma mark - ViewController Setup

@implementation ViewController

- (void)dealloc
{
    [self.avCaptureSession stopRunning];
    
    if ([EAGLContext currentContext] == _display.context)
    {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _calibrationOverlay = nil;

    [self setupGL];
    
    [self setupUserInterface];
    
    [self setupMeshViewController];
    
    [self setupGestures];
    
    [self setupIMU];
    
    [self setupStructureSensor];
    
    // Later, we’ll set this true if we have a device-specific calibration
    _useColorCamera = [STSensorController approximateCalibrationGuaranteedForDevice];
    
    // Make sure we get notified when the app becomes active to start/restore the sensor state if necessary.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // The framebuffer will only be really ready with its final size after the view appears.
    [(EAGLView *)self.view setFramebuffer];
    
    [self setupGLViewport];

    [self updateAppStatusMessage];
    
    // We will connect to the sensor when we receive appDidBecomeActive.
}

- (void)appDidBecomeActive
{
    if ([self currentStateNeedsSensor])
        [self connectToStructureSensorAndStartStreaming];
    
    // Abort the current scan if we were still scanning before going into background since we
    // are not likely to recover well.
    if (_slamState.scannerState == ScannerStateScanning)
    {
        [self resetButtonPressed:self];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    [self respondToMemoryWarning];
}

- (void)setupUserInterface
{
    // Make sure the status bar is hidden.
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    
    // Fully transparent message label, initially.
    self.appStatusMessageLabel.alpha = 0;
    
    // Make sure the label is on top of everything else.
    self.appStatusMessageLabel.layer.zPosition = 100;
    
    // Set the default value for the high resolution switch. If set, will use 2592x1968 as color input.
    self.enableHighResolutionColorSwitch.on = getDefaultHighResolutionSettingForCurrentDevice();
}

// Make sure the status bar is disabled (iOS 7+)
- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)setupGestures
{
    // Register pinch gesture for volume scale adjustment.
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGesture:)];
    [pinchGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchGesture];
}

- (void)setupMeshViewController
{
    // The mesh viewer will be used after scanning.
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        _meshViewController = [[MeshViewController alloc] initWithNibName:@"MeshView_iPhone" bundle:nil];
    } else {
        _meshViewController = [[MeshViewController alloc]  initWithNibName:@"MeshView_iPad" bundle:nil];
    }
    _meshViewController.delegate = self;
    _meshViewNavigationController = [[UINavigationController alloc] initWithRootViewController:_meshViewController];
}

- (void)presentMeshViewer:(STMesh *)mesh
{
    [_meshViewController setupGL:_display.context];
    
    _meshViewController.colorEnabled = _useColorCamera;
    _meshViewController.mesh = mesh;
    [_meshViewController setCameraProjectionMatrix:_display.depthCameraGLProjectionMatrix];
    
    GLKVector3 volumeCenter = GLKVector3MultiplyScalar([_slamState.mapper volumeSizeInMeters], 0.5);
    [_meshViewController resetMeshCenter:volumeCenter];
    
    [self presentViewController:_meshViewNavigationController animated:YES completion:^{}];
}

- (void)enterCubePlacementState
{
    // Switch to the Scan button.
    self.scanButton.hidden = NO;
    self.doneButton.hidden = YES;
    self.resetButton.hidden = YES;
    
    // We'll enable the button only after we get some initial pose.
    self.scanButton.enabled = NO;
    
    // Cannot be lost in cube placement mode.
    _trackingLostLabel.hidden = YES;
    
    [self setColorCameraParametersForInit];
    
    _slamState.scannerState = ScannerStateCubePlacement;
    
    [self updateIdleTimer];
}

- (void)enterScanningState
{
    // Switch to the Done button.
    self.scanButton.hidden = YES;
    self.doneButton.hidden = NO;
    self.resetButton.hidden = NO;
    
    // Tell the mapper if we have a support plane so that it can optimize for it.
    [_slamState.mapper setHasSupportPlane:_slamState.cameraPoseInitializer.hasSupportPlane];
    
    _slamState.tracker.initialCameraPose = _slamState.cameraPoseInitializer.cameraPose;
    
    // We will lock exposure during scanning to ensure better coloring.
    [self setColorCameraParametersForScanning];
    
    _slamState.scannerState = ScannerStateScanning;
}

- (void)enterViewingState
{
    // Cannot be lost in view mode.
    [self hideTrackingErrorMessage];
    
    _appStatus.statusMessageDisabled = true;
    [self updateAppStatusMessage];
    
    // Hide the Scan/Done/Reset button.
    self.scanButton.hidden = YES;
    self.doneButton.hidden = YES;
    self.resetButton.hidden = YES;
    
    [_sensorController stopStreaming];

    if (_useColorCamera)
        [self stopColorCamera];
    
    [_slamState.mapper finalizeTriangleMeshWithSubsampling:1];
    
    STMesh *mesh = [_slamState.scene lockAndGetSceneMesh];
    [self presentMeshViewer:mesh];
    
    [_slamState.scene unlockSceneMesh];
    
    _slamState.scannerState = ScannerStateViewing;
    
    [self updateIdleTimer];
}

namespace { // anonymous namespace for utility function.
    
    float keepInRange(float value, float minValue, float maxValue)
    {
        if (isnan (value))
            return minValue;
        
        if (value > maxValue)
            return maxValue;
        
        if (value < minValue)
            return minValue;
        
        return value;
    }
    
}

- (void)adjustVolumeSize:(GLKVector3)volumeSize
{
    // Make sure the volume size remains between 10 centimeters and 10 meters.
    volumeSize.x = keepInRange (volumeSize.x, 0.1, 10.f);
    volumeSize.y = keepInRange (volumeSize.y, 0.1, 10.f);
    volumeSize.z = keepInRange (volumeSize.z, 0.1, 10.f);
    
    _slamState.mapper.volumeSizeInMeters = volumeSize;
    
    _slamState.cameraPoseInitializer.volumeSizeInMeters = volumeSize;
    [_display.cubeRenderer adjustCubeSize:_slamState.mapper.volumeSizeInMeters
                         volumeResolution:_slamState.mapper.volumeResolution];
}

#pragma mark -  Structure Sensor Management

-(BOOL)currentStateNeedsSensor
{
    switch (_slamState.scannerState)
    {
        // Initialization and scanning need the sensor.
        case ScannerStateCubePlacement:
        case ScannerStateScanning:
            return TRUE;
            
        // Other states don't need the sensor.
        default:
            return FALSE;
    }
}

#pragma mark - IMU

- (void)setupIMU
{
    _lastGravity = GLKVector3Make (0,0,0);
    
    // 60 FPS is responsive enough for motion events.
    const float fps = 60.0;
    _motionManager = [[CMMotionManager alloc] init];
    _motionManager.accelerometerUpdateInterval = 1.0/fps;
    _motionManager.gyroUpdateInterval = 1.0/fps;
    
    // Limiting the concurrent ops to 1 is a simple way to force serial execution
    _imuQueue = [[NSOperationQueue alloc] init];
    [_imuQueue setMaxConcurrentOperationCount:1];
    
    __weak ViewController *weakSelf = self;
    CMDeviceMotionHandler dmHandler = ^(CMDeviceMotion *motion, NSError *error)
    {
        // Could be nil if the self is released before the callback happens.
        if (weakSelf) {
            [weakSelf processDeviceMotion:motion withError:error];
        }
    };
    
    [_motionManager startDeviceMotionUpdatesToQueue:_imuQueue withHandler:dmHandler];
}

- (void)processDeviceMotion:(CMDeviceMotion *)motion withError:(NSError *)error
{
    if (_slamState.scannerState == ScannerStateCubePlacement)
    {
        // Update our gravity vector, it will be used by the cube placement initializer.
        _lastGravity = GLKVector3Make (motion.gravity.x, motion.gravity.y, motion.gravity.z);
    }
    
    if (_slamState.scannerState == ScannerStateCubePlacement || _slamState.scannerState == ScannerStateScanning)
    {
        // The tracker is more robust to fast moves if we feed it with motion data.
        [_slamState.tracker updateCameraPoseWithMotion:motion];
    }
}

#pragma mark - UI Callbacks

- (IBAction)enableNewTrackerSwitchChanged:(id)sender
{
    // Save the volume size.
    GLKVector3 previousVolumeSize = _options.initialVolumeSizeInMeters;
    if (_slamState.initialized)
        previousVolumeSize = _slamState.mapper.volumeSizeInMeters;
    
    // Simulate a full reset to force a creation of a new tracker.
    [self resetButtonPressed:self.resetButton];
    [self clearSLAM];
    [self setupSLAM];
    
    // Restore the volume size cleared by the full reset.
    _slamState.mapper.volumeSizeInMeters = previousVolumeSize;
    [self adjustVolumeSize:_slamState.mapper.volumeSizeInMeters];
}

- (IBAction)enableHighResolutionColorSwitchChanged:(id)sender
{
    if (self.avCaptureSession)
    {
        [self stopColorCamera];
        if (_useColorCamera)
            [self startColorCamera];
    }
    
    // Force a scan reset since we cannot changing the image resolution during the scan is not
    // supported by STColorizer.
    [self resetButtonPressed:self.resetButton];
}

- (IBAction)scanButtonPressed:(id)sender
{
    [self enterScanningState];
}

- (IBAction)resetButtonPressed:(id)sender
{
    [self resetSLAM];
}

- (IBAction)doneButtonPressed:(id)sender
{
    [self enterViewingState];
}

// Manages whether we can let the application sleep.
-(void)updateIdleTimer
{
    if ([self isStructureConnectedAndCharged] && [self currentStateNeedsSensor])
    {
        // Do not let the application sleep if we are currently using the sensor data.
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    }
    else
    {
        // Let the application sleep if we are only viewing the mesh or if no sensors are connected.
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    }
}

- (void)showTrackingMessage:(NSString*)message
{
    self.trackingLostLabel.text = message;
    self.trackingLostLabel.hidden = NO;
}

- (void)hideTrackingErrorMessage
{
    self.trackingLostLabel.hidden = YES;
}

- (void)showAppStatusMessage:(NSString *)msg
{
    _appStatus.needsDisplayOfStatusMessage = true;
    [self.view.layer removeAllAnimations];
    
    [self.appStatusMessageLabel setText:msg];
    [self.appStatusMessageLabel setHidden:NO];
    
    // Progressively show the message label.
    [self.view setUserInteractionEnabled:false];
    [UIView animateWithDuration:0.5f animations:^{
        self.appStatusMessageLabel.alpha = 1.0f;
    }completion:nil];
}

- (void)hideAppStatusMessage
{
    if (!_appStatus.needsDisplayOfStatusMessage)
        return;
    
    _appStatus.needsDisplayOfStatusMessage = false;
    [self.view.layer removeAllAnimations];
    
    __weak ViewController *weakSelf = self;
    [UIView animateWithDuration:0.5f
                     animations:^{
                         weakSelf.appStatusMessageLabel.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         // If nobody called showAppStatusMessage before the end of the animation, do not hide it.
                         if (!_appStatus.needsDisplayOfStatusMessage)
                         {
                             // Could be nil if the self is released before the callback happens.
                             if (weakSelf) {
                                 [weakSelf.appStatusMessageLabel setHidden:YES];
                                 [weakSelf.view setUserInteractionEnabled:true];
                             }
                         }
     }];
}

-(void)updateAppStatusMessage
{
    // Skip everything if we should not show app status messages (e.g. in viewing state).
    if (_appStatus.statusMessageDisabled)
    {
        [self hideAppStatusMessage];
        return;
    }
    
    // First show sensor issues, if any.
    switch (_appStatus.sensorStatus)
    {
        case AppStatus::SensorStatusOk:
        {
            break;
        }
            
        case AppStatus::SensorStatusNeedsUserToConnect:
        {
            [self showAppStatusMessage:_appStatus.pleaseConnectSensorMessage];
            return;
        }
            
        case AppStatus::SensorStatusNeedsUserToCharge:
        {
            [self showAppStatusMessage:_appStatus.pleaseChargeSensorMessage];
            return;
        }
    }
    
    // Then show color camera permission issues, if any.
    if (!_appStatus.colorCameraIsAuthorized)
    {
        [self showAppStatusMessage:_appStatus.needColorCameraAccessMessage];
        return;
    }

    // If we reach this point, no status to show.
    [self hideAppStatusMessage];
}

- (void)pinchGesture:(UIPinchGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
    {
        if (_slamState.scannerState == ScannerStateCubePlacement)
        {
            _volumeScale.initialPinchScale = _volumeScale.currentScale / [gestureRecognizer scale];
        }
    }
    else if ([gestureRecognizer state] == UIGestureRecognizerStateChanged)
    {
        if(_slamState.scannerState == ScannerStateCubePlacement)
        {
            // In some special conditions the gesture recognizer can send a zero initial scale.
            if (!isnan (_volumeScale.initialPinchScale))
            {
                _volumeScale.currentScale = [gestureRecognizer scale] * _volumeScale.initialPinchScale;
                
                // Don't let our scale multiplier become absurd
                _volumeScale.currentScale = keepInRange(_volumeScale.currentScale, 0.01, 1000.f);
                
                GLKVector3 newVolumeSize = GLKVector3MultiplyScalar(_options.initialVolumeSizeInMeters, _volumeScale.currentScale);
                
                [self adjustVolumeSize:newVolumeSize];
            }
        }
    }
}

#pragma mark - MeshViewController delegates

- (void)meshViewWillDismiss
{
    // If we are running colorize work, we should cancel it.
    if (_naiveColorizeTask)
    {
        [_naiveColorizeTask cancel];
        _naiveColorizeTask = nil;
    }
    if (_enhancedColorizeTask)
    {
        [_enhancedColorizeTask cancel];
        _enhancedColorizeTask = nil;
    }
    
    [_meshViewController hideMeshViewerMessage];
}

- (void)meshViewDidDismiss
{
    _appStatus.statusMessageDisabled = false;
    [self updateAppStatusMessage];
    
    [self connectToStructureSensorAndStartStreaming];
    [self resetSLAM];
}

- (void)backgroundTask:(STBackgroundTask *)sender didUpdateProgress:(double)progress
{
    if (sender == _naiveColorizeTask)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_meshViewController showMeshViewerMessage:[NSString stringWithFormat:@"Processing: % 3d%%", int(progress*20)]];
        });
    }
    else if (sender == _enhancedColorizeTask)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_meshViewController showMeshViewerMessage:[NSString stringWithFormat:@"Processing: % 3d%%", int(progress*80)+20]];
        });
    }
}

- (BOOL)meshViewDidRequestColorizing:(STMesh*)mesh previewCompletionHandler:(void (^)())previewCompletionHandler enhancedCompletionHandler:(void (^)())enhancedCompletionHandler
{
    if (_naiveColorizeTask) // already one running?
    {
        NSLog(@"Already one colorizing task running!");
        return FALSE;
    }

    _naiveColorizeTask = [STColorizer
                     newColorizeTaskWithMesh:mesh
                     scene:_slamState.scene
                     keyframes:[_slamState.keyFrameManager getKeyFrames]
                     completionHandler: ^(NSError *error)
                     {
                         if (error != nil) {
                             NSLog(@"Error during colorizing: %@", [error localizedDescription]);
                         }
                         else
                         {
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 previewCompletionHandler();
                                 _meshViewController.mesh = mesh;
                                 [self performEnhancedColorize:(STMesh*)mesh enhancedCompletionHandler:enhancedCompletionHandler];
                             });
                             _naiveColorizeTask = nil;
                         }
                     }
                     options:@{kSTColorizerTypeKey: @(STColorizerPerVertex),
                               kSTColorizerPrioritizeFirstFrameColorKey: @(_options.prioritizeFirstFrameColor)}
                     error:nil];
    
    if (_naiveColorizeTask)
    {
        _naiveColorizeTask.delegate = self;
        [_naiveColorizeTask start];
        return TRUE;
    }
    
    return FALSE;
}

- (void)performEnhancedColorize:(STMesh*)mesh enhancedCompletionHandler:(void (^)())enhancedCompletionHandler
{
    _enhancedColorizeTask =[STColorizer
       newColorizeTaskWithMesh:mesh
       scene:_slamState.scene
       keyframes:[_slamState.keyFrameManager getKeyFrames]
       completionHandler: ^(NSError *error)
       {
           if (error != nil) {
               NSLog(@"Error during colorizing: %@", [error localizedDescription]);
           }
           else
           {
               dispatch_async(dispatch_get_main_queue(), ^{
                   enhancedCompletionHandler();
                   _meshViewController.mesh = mesh;
               });
               _enhancedColorizeTask = nil;
           }
       }
       options:@{kSTColorizerTypeKey: @(STColorizerTextureMapForObject),
                 kSTColorizerPrioritizeFirstFrameColorKey: @(_options.prioritizeFirstFrameColor),
                 kSTColorizerQualityKey: @(_options.colorizerQuality),
                 kSTColorizerTargetNumberOfFacesKey: @(_options.colorizerTargetNumFaces)} // 20k faces is enough for most objects.
       error:nil];
    
    if (_enhancedColorizeTask)
    {
        // We don't need the keyframes anymore now that the final colorizing task was started.
        // Clearing it now gives a chance to early release the keyframe memory when the colorizer
        // stops needing them.
        [_slamState.keyFrameManager clear];
        
        _enhancedColorizeTask.delegate = self;
        [_enhancedColorizeTask start];
    }
}


- (void) respondToMemoryWarning
{
    switch( _slamState.scannerState )
    {
        case ScannerStateViewing:
        {
            // If we are running a colorizing task, abort it
            if( _enhancedColorizeTask != nil && !_slamState.showingMemoryWarning )
            {
                _slamState.showingMemoryWarning = true;
                
                // stop the task
                [_enhancedColorizeTask cancel];
                _enhancedColorizeTask = nil;
                
                // hide progress bar
                [_meshViewController hideMeshViewerMessage];
                
                UIAlertController *alertCtrl= [UIAlertController alertControllerWithTitle:@"Memory Low"
                                                                                  message:@"Colorizing was canceled."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action)
                                           {
                                               _slamState.showingMemoryWarning = false;
                                           }];
                
                [alertCtrl addAction:okAction];
                
                // show the alert in the meshViewController
                [_meshViewController presentViewController:alertCtrl animated:YES completion:nil];
            }
            
            break;
        }
        case ScannerStateScanning:
        {
            if( !_slamState.showingMemoryWarning )
            {
                _slamState.showingMemoryWarning = true;
                
                UIAlertController *alertCtrl= [UIAlertController alertControllerWithTitle:@"Memory Low"
                                                                                  message:@"Scanning will be stopped to avoid loss."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action)
                                           {
                                               _slamState.showingMemoryWarning = false;
                                               [self enterViewingState];
                                           }];
                
                
                [alertCtrl addAction:okAction];
                
                // show the alert
                [self presentViewController:alertCtrl animated:YES completion:nil];
            }
            
            break;
        }
        default:
        {
            // not much we can do here
        }
    }
}
@end

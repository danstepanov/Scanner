/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#include "ViewpointController.h"

#import <mach/mach_time.h>

#include <cmath>

// Helper functions
namespace
{

    double nowInSeconds()
    {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        
        uint64_t newTime = mach_absolute_time();
        
        return ((double)newTime*timebase.numer)/((double)timebase.denom *1e9);
    }

} // Anonymous

struct ViewpointController::PrivateData
{
    // Projection matrix before starting user interaction.
    GLKMatrix4 referenceProjectionMatrix;
    
    // Centroid of the mesh.
    GLKVector3 meshCenter;
    
    // Scale management
    float scaleWhenPinchGestureBegan;
    float currentScale;
    
    // ModelView rotation.
    double lastModelViewRotationUpdateTimestamp;
    GLKVector2 oneFingerPanWhenGestureBegan;
    GLKMatrix4 modelViewRotationWhenPanGestureBegan;
    GLKMatrix4 modelViewRotation;
    GLKVector2 modelViewRotationVelocity; // expressed in terms of touch coordinates.
    
    // Rotation speed will slow down with time.
    GLKVector2 velocitiesDampingRatio;
    
    // Translation in screen space.
    GLKVector2 twoFingersPanWhenGestureBegan;
    GLKVector2 meshCenterOnScreenWhenPanGestureBegan;
    GLKVector2 meshCenterOnScreen;
    
    GLKVector2 screenCenter;
    GLKVector2 screenSize;
    
    bool cameraOrProjectionChangedSinceLastUpdate;
};

ViewpointController::ViewpointController (float screenSizeX, float screenSizeY)
: d (new PrivateData)
{
    d->screenSize = GLKVector2Make(screenSizeX, screenSizeY);
    reset();
}

ViewpointController::~ViewpointController()
{
    delete d; d = 0;
}

void ViewpointController::reset()
{
    d->cameraOrProjectionChangedSinceLastUpdate = false;
    d->scaleWhenPinchGestureBegan = 1.0;
    d->currentScale = 1.0;
    d->screenCenter = GLKVector2MultiplyScalar(d->screenSize, 0.5);
    d->meshCenterOnScreen = GLKVector2MultiplyScalar(d->screenSize, 0.5);
    d->modelViewRotationWhenPanGestureBegan = GLKMatrix4Identity;
    d->modelViewRotation = GLKMatrix4Identity;
    d->velocitiesDampingRatio = GLKVector2Make(0.95, 0.95);
    d->modelViewRotationVelocity = GLKVector2Make(0, 0);
}

void ViewpointController::setCameraProjection(GLKMatrix4 projRt)
{
    d->referenceProjectionMatrix = projRt;
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

void ViewpointController::setMeshCenter(GLKVector3 center)
{
    d->meshCenter = center;
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

// Scale Gesture Control
void ViewpointController::onPinchGestureBegan(float scale)
{
    d->scaleWhenPinchGestureBegan = d->currentScale / scale;
}

void ViewpointController::onPinchGestureChanged(float scale)
{
    d->currentScale = scale * d->scaleWhenPinchGestureBegan;
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

// 3D modelView rotation gesture control.
void ViewpointController::onOneFingerPanBegan(GLKVector2 &touch)
{
    d->modelViewRotationWhenPanGestureBegan = d->modelViewRotation;
    d->oneFingerPanWhenGestureBegan = touch;
}

void ViewpointController::onOneFingerPanChanged(GLKVector2 &touch)
{
    GLKVector2 distMoved = GLKVector2Subtract(touch, d->oneFingerPanWhenGestureBegan);
    GLKVector2 spinDegree = GLKVector2Negate(GLKVector2DivideScalar(distMoved, 300));
    
    GLKMatrix4 rotX = GLKMatrix4MakeYRotation(spinDegree.x);
    GLKMatrix4 rotY = GLKMatrix4MakeXRotation(-spinDegree.y);
    
    d->modelViewRotation = GLKMatrix4Multiply(GLKMatrix4Multiply(rotX, rotY), d->modelViewRotationWhenPanGestureBegan);
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

void ViewpointController::onOneFingerPanEnded(GLKVector2 vel)
{
    d->modelViewRotationVelocity = vel;
    d->lastModelViewRotationUpdateTimestamp = nowInSeconds();
}

// Screen-space translation gesture control.
void ViewpointController::onTwoFingersPanBegan(GLKVector2 &touch)
{
    d->twoFingersPanWhenGestureBegan = touch;
    d->meshCenterOnScreenWhenPanGestureBegan = d->meshCenterOnScreen;
}

void ViewpointController::onTwoFingersPanChanged(GLKVector2 &touch)
{
    d->meshCenterOnScreen = GLKVector2Add(GLKVector2Subtract(touch, d->twoFingersPanWhenGestureBegan), d->meshCenterOnScreenWhenPanGestureBegan);
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

void ViewpointController::onTwoFingersPanEnded(GLKVector2 vel)
{
}

void ViewpointController::onTouchBegan()
{
    // Stop the current animations when the user touches the screen.
    d->modelViewRotationVelocity = GLKVector2Make(0, 0);
}

// ModelView matrix in OpenGL space.
GLKMatrix4 ViewpointController::currentGLModelViewMatrix() const
{
    GLKMatrix4 meshCenterToOrigin = GLKMatrix4MakeTranslation(-d->meshCenter.x, -d->meshCenter.y, -d->meshCenter.z);

    // We'll put the object at some distance.
    GLKMatrix4 originToVirtualViewpoint = GLKMatrix4MakeTranslation(0, 0, 4*d->meshCenter.z);
    
    GLKMatrix4 modelView = originToVirtualViewpoint;
    modelView = GLKMatrix4Multiply(modelView, d->modelViewRotation); // will apply the rotation around the mesh center.
    modelView = GLKMatrix4Multiply(modelView, meshCenterToOrigin);
    return modelView;
}

// Projection matrix in OpenGL space.
GLKMatrix4 ViewpointController::currentGLProjectionMatrix() const
{
    // The scale is directly applied to the reference projection matrix.
    GLKMatrix4 scale = GLKMatrix4MakeScale(d->currentScale, d->currentScale, 1);
    
    // Since the translation is done in screen space, it's also applied to the projection matrix directly.
    GLKMatrix4 centerTranslation = currentProjectionCenterTranslation();
    return GLKMatrix4Multiply(centerTranslation,  GLKMatrix4Multiply(scale, d->referenceProjectionMatrix));
}

bool ViewpointController::update()
{
    bool viewpointChanged = d->cameraOrProjectionChangedSinceLastUpdate;
    
    // Modelview rotation animation.
    if (GLKVector2Length(d->modelViewRotationVelocity) > 1e-5f)
    {
        double nowSec = nowInSeconds ();
        double elapsedSec = nowSec - d->lastModelViewRotationUpdateTimestamp;
        d->lastModelViewRotationUpdateTimestamp = nowSec;
        
        GLKVector2 distMoved = GLKVector2MultiplyScalar(d->modelViewRotationVelocity, elapsedSec);
        GLKVector2 spinDegree = GLKVector2Negate(GLKVector2DivideScalar(distMoved, 300));
        
        GLKMatrix4 rotX = GLKMatrix4MakeYRotation(spinDegree.x);
        GLKMatrix4 rotY = GLKMatrix4MakeXRotation(-spinDegree.y);
        d->modelViewRotation = GLKMatrix4Multiply(GLKMatrix4Multiply(rotX, rotY), d->modelViewRotation);
        
        // Slow down the velocities.
        d->modelViewRotationVelocity.x *= d->velocitiesDampingRatio.x;
        d->modelViewRotationVelocity.y *= d->velocitiesDampingRatio.y;
        
        // Make sure we stop animating and taking resources when it became too small.
        if (std::abs(d->modelViewRotationVelocity.x) < 1.f) d->modelViewRotationVelocity.x = 0;
        if (std::abs(d->modelViewRotationVelocity.y) < 1.f) d->modelViewRotationVelocity.y = 0;
        
        viewpointChanged = true;
    }
 
    d->cameraOrProjectionChangedSinceLastUpdate = false;
    
    return viewpointChanged;
}

GLKMatrix4 ViewpointController::currentProjectionCenterTranslation() const
{
    GLKVector2 deltaFromScreenCenter = GLKVector2Subtract(d->screenCenter, d->meshCenterOnScreen);
    return GLKMatrix4MakeTranslation(-deltaFromScreenCenter.x/d->screenCenter.x,  deltaFromScreenCenter.y/d->screenCenter.y, 0);
}

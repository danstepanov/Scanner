/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#pragma once

#import <GLKit/GLKit.h>

class ViewpointController
{
public:
    ViewpointController(float screenSizeX, float screenSizeY);
    ~ViewpointController();
    
    void reset();
    
    void setCameraProjection(GLKMatrix4 projection);
    
    void setMeshCenter(GLKVector3 center);
    
    // Pinch gesture for scale.
    void onPinchGestureBegan(float scale);
    void onPinchGestureChanged(float scale);
    
    // One-finger pan gesture for rotation.
    void onOneFingerPanBegan(GLKVector2 &touch);
    void onOneFingerPanChanged(GLKVector2 &touch);
    void onOneFingerPanEnded(GLKVector2 vel);
    
    // Two-fingers pan gesture for translation.
    void onTwoFingersPanBegan(GLKVector2 &touch);
    void onTwoFingersPanChanged(GLKVector2 &touch);
    void onTwoFingersPanEnded(GLKVector2 vel);

    // Touch without a gesture will stop the current animations.
    void onTouchBegan();
    
    // Current modelView matrix in OpenGL space.
    GLKMatrix4 currentGLModelViewMatrix() const;
    
    // Current projection matrix in OpenGL space.
    GLKMatrix4 currentGLProjectionMatrix() const;

    // Apply one update step. Will apply current velocities and animations.
    // Returns true if the current viewpoint changed.
    bool update();
    
private:
    GLKMatrix4 currentProjectionCenterTranslation() const;
    
private:
    struct PrivateData;
    PrivateData* d;
};

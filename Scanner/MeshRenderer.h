/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#pragma once

#import <GLKit/GLKit.h>
#import <CoreVideo/CVImageBuffer.h>

@class STMesh;

class MeshRenderer
{
public:
    enum RenderingMode
    {
        RenderingModeXRay = 0,
        RenderingModePerVertexColor,
        RenderingModeTextured,
        RenderingModeLightedGray,
        
        RenderingModeNumModes
    };
    
    MeshRenderer();
    ~MeshRenderer();
    
    void initializeGL (GLenum defaultTextureUnit = GL_TEXTURE3);
    void releaseGLBuffers (); // release the data uploaded to the GPU.
    void releaseGLTextures (); // release the data uploaded to the GPU.
    
    void setRenderingMode(RenderingMode mode);
    RenderingMode getRenderingMode() const;
    
    void clear();
    
    void uploadMesh (STMesh* mesh);
    
    void render(const GLKMatrix4& projectionMatrix, const GLKMatrix4& modelViewMatrix);

private:
    void renderPartialMesh(int meshIndex);

    void enableVertexBuffer (int meshIndex);
    void disableVertexBuffer (int meshIndex);
    
    void enableNormalBuffer (int meshIndex);
    void disableNormalBuffer (int meshIndex);
    
    void enableVertexColorBuffer (int meshIndex);
    void disableVertexColorBuffer (int meshIndex);
    
    void enableVertexTexcoordsBuffer (int meshIndex);
    void disableVertexTexcoordBuffer (int meshIndex);
    
    void enableLinesElementBuffer (int meshIndex);
    void enableTrianglesElementBuffer (int meshIndex);
    
    void uploadTexture (CVImageBufferRef pixelBuffer);
    
private:
    class PrivateData;
    PrivateData* d;
};

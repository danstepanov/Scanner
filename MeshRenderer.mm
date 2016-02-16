/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <GLKit/GLKit.h>
#import <OpenGLES/ES2/glext.h> // GL_RED_EXT

#import "MeshRenderer.h"
#import "CustomShaders.h"

#import <Structure/StructureSLAM.h>

#define MAX_MESHES 30

// Local functions

struct MeshRenderer::PrivateData
{
    LightedGrayShader lightedGrayShader;
    PerVertexColorShader perVertexColorShader;
    XrayShader xRayShader;
    YCbCrTextureShader yCbCrTextureShader;
    
    int numUploadedMeshes = 0;
    int numTriangleIndices[MAX_MESHES];
    int numLinesIndices[MAX_MESHES];

    bool hasPerVertexColor = false;
    bool hasPerVertexNormals = false;
    bool hasPerVertexUV = false;
    bool hasTexture = false;
    
    // Vertex buffer objects.
    GLuint vertexVbo[MAX_MESHES];
    GLuint normalsVbo[MAX_MESHES];
    GLuint colorsVbo[MAX_MESHES];
    GLuint texcoordsVbo[MAX_MESHES];
    GLuint facesVbo[MAX_MESHES];
    GLuint linesVbo[MAX_MESHES];

    // OpenGL Texture reference for y and chroma images.
    CVOpenGLESTextureRef lumaTexture = NULL;
    CVOpenGLESTextureRef chromaTexture = NULL;

    // OpenGL Texture cache for the color texture.
    CVOpenGLESTextureCacheRef textureCache = NULL;
    
    // Texture unit to use for texture binding/rendering.
    GLenum textureUnit = GL_TEXTURE3;
    
    // Current render mode.
    RenderingMode currentRenderingMode = RenderingModeLightedGray;
};

MeshRenderer::MeshRenderer()
: d (new PrivateData)
{
}

void MeshRenderer::initializeGL (GLenum defaultTextureUnit)
{
    d->textureUnit = defaultTextureUnit;
    glGenBuffers (MAX_MESHES, d->vertexVbo);
    glGenBuffers (MAX_MESHES, d->normalsVbo);
    glGenBuffers (MAX_MESHES, d->colorsVbo);
    glGenBuffers (MAX_MESHES, d->texcoordsVbo);
    glGenBuffers (MAX_MESHES, d->facesVbo);
    glGenBuffers (MAX_MESHES, d->linesVbo);    
}

void MeshRenderer::releaseGLTextures ()
{
    if (d->lumaTexture)
    {
        CFRelease (d->lumaTexture);
        d->lumaTexture = NULL;
    }
    
    if (d->chromaTexture)
    {
        CFRelease(d->chromaTexture);
        d->chromaTexture = NULL;
    }
    
    if (d->textureCache)
    {
        CFRelease(d->textureCache);
        d->textureCache = NULL;
    }
}

void MeshRenderer::releaseGLBuffers ()
{
    for (int meshIndex = 0; meshIndex < d->numUploadedMeshes; ++meshIndex)
    {
        glBindBuffer(GL_ARRAY_BUFFER, d->vertexVbo[meshIndex]);
        glBufferData(GL_ARRAY_BUFFER, 0, NULL, GL_STATIC_DRAW);
        
        glBindBuffer(GL_ARRAY_BUFFER, d->normalsVbo[meshIndex]);
        glBufferData(GL_ARRAY_BUFFER, 0, NULL, GL_STATIC_DRAW);
        
        glBindBuffer(GL_ARRAY_BUFFER, d->colorsVbo[meshIndex]);
        glBufferData(GL_ARRAY_BUFFER, 0, NULL, GL_STATIC_DRAW);
        
        glBindBuffer(GL_ARRAY_BUFFER, d->texcoordsVbo[meshIndex]);
        glBufferData(GL_ARRAY_BUFFER, 0, NULL, GL_STATIC_DRAW);
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, d->facesVbo[meshIndex]);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, 0, NULL, GL_STATIC_DRAW);
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, d->linesVbo[meshIndex]);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, 0, NULL, GL_STATIC_DRAW);
    }
}

MeshRenderer::~MeshRenderer()
{
    if(d->vertexVbo[0])
        glDeleteBuffers(MAX_MESHES, d->vertexVbo);
    
    if(d->normalsVbo[0])
        glDeleteBuffers(MAX_MESHES, d->normalsVbo);
    
    if(d->colorsVbo[0])
        glDeleteBuffers(MAX_MESHES, d->colorsVbo);
    
    if(d->texcoordsVbo[0])
        glDeleteBuffers(MAX_MESHES, d->texcoordsVbo);
    
    if(d->facesVbo[0])
        glDeleteBuffers(MAX_MESHES, d->facesVbo);
    
    if(d->linesVbo[0])
        glDeleteBuffers(MAX_MESHES, d->linesVbo);
    
    releaseGLTextures ();

    delete d;
}

void MeshRenderer::clear()
{
    if(d->currentRenderingMode == RenderingModePerVertexColor || d->currentRenderingMode == RenderingModeTextured)
        glClearColor(0.9, 0.9, 0.9, 1.0);
    else
        glClearColor(0.1, 0.1, 0.1, 1.0);
    
    glClearDepthf(1.0);
    
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

void MeshRenderer::setRenderingMode( RenderingMode mode )
{
    d->currentRenderingMode = mode;
}

MeshRenderer::RenderingMode MeshRenderer::getRenderingMode() const
{
    return d->currentRenderingMode;
}

void MeshRenderer::uploadMesh (STMesh* mesh)
{
    int numUploads = fmin((int)[mesh numberOfMeshes], MAX_MESHES);
    d->numUploadedMeshes = fmin((int)[mesh numberOfMeshes], MAX_MESHES);
    
    d->hasPerVertexColor = [mesh hasPerVertexColors];
    d->hasPerVertexNormals = [mesh hasPerVertexNormals];
    d->hasPerVertexUV = [mesh hasPerVertexUVTextureCoords];
    d->hasTexture = ([mesh meshYCbCrTexture] != NULL);

    if (d->hasTexture)
        uploadTexture ([mesh meshYCbCrTexture]);
    
    for (int meshIndex = 0; meshIndex < numUploads; ++meshIndex)
    {
        const int numVertices = [mesh numberOfMeshVertices:meshIndex];
        
        glBindBuffer(GL_ARRAY_BUFFER, d->vertexVbo[meshIndex]);
        glBufferData(GL_ARRAY_BUFFER, numVertices * sizeof (GLKVector3), [mesh meshVertices:meshIndex], GL_STATIC_DRAW);
        
        if (d->hasPerVertexNormals)
        {
            glBindBuffer(GL_ARRAY_BUFFER, d->normalsVbo[meshIndex]);
            glBufferData(GL_ARRAY_BUFFER, numVertices * sizeof (GLKVector3), [mesh meshPerVertexNormals:meshIndex], GL_STATIC_DRAW);
        }
        
        if (d->hasPerVertexColor)
        {
            glBindBuffer(GL_ARRAY_BUFFER, d->colorsVbo[meshIndex]);
            glBufferData(GL_ARRAY_BUFFER, numVertices * sizeof (GLKVector3), [mesh meshPerVertexColors:meshIndex], GL_STATIC_DRAW);
        }
        
        if (d->hasPerVertexUV)
        {
            glBindBuffer(GL_ARRAY_BUFFER, d->texcoordsVbo[meshIndex]);
            glBufferData(GL_ARRAY_BUFFER, numVertices * sizeof (GLKVector2), [mesh meshPerVertexUVTextureCoords:meshIndex], GL_STATIC_DRAW);
        }
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, d->facesVbo[meshIndex]);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, [mesh numberOfMeshFaces:meshIndex] * sizeof(unsigned short) * 3,
                     [mesh meshFaces:meshIndex], GL_STATIC_DRAW);
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, d->linesVbo[meshIndex]);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, [mesh numberOfMeshLines:meshIndex] * sizeof(unsigned short) * 2,
                     [mesh meshLines:meshIndex], GL_STATIC_DRAW);
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        d->numTriangleIndices[meshIndex] = [mesh numberOfMeshFaces:meshIndex] * 3;
        d->numLinesIndices[meshIndex] = [mesh numberOfMeshLines:meshIndex] * 2;
    }
}

void MeshRenderer::uploadTexture (CVImageBufferRef pixelBuffer)
{
    int width = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    EAGLContext *context = [EAGLContext currentContext];
    assert (context != nil);
    
    releaseGLTextures ();
    
    if (d->textureCache == NULL)
    {
        CVReturn texError = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, context, NULL, &d->textureCache);
        if (texError) { NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", texError); }
    }
    
    // Allow the texture cache to do internal cleanup.
    CVOpenGLESTextureCacheFlush(d->textureCache, 0);
    
    OSType pixelFormat = CVPixelBufferGetPixelFormatType (pixelBuffer);
    assert(pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
    
    // Activate the default texture unit.
    glActiveTexture (d->textureUnit);
    
    // Create a new Y texture from the video texture cache.
    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                d->textureCache,
                                                                pixelBuffer,
                                                                NULL,
                                                                GL_TEXTURE_2D,
                                                                GL_RED_EXT,
                                                                (int)width,
                                                                (int)height,
                                                                GL_RED_EXT,
                                                                GL_UNSIGNED_BYTE,
                                                                0,
                                                                &d->lumaTexture);
    
    if (err)
    {
        NSLog(@"Error with CVOpenGLESTextureCacheCreateTextureFromImage: %d", err);
        return;
    }
    
    // Set rendering properties for the new texture.
    glBindTexture(CVOpenGLESTextureGetTarget(d->lumaTexture), CVOpenGLESTextureGetName(d->lumaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // Activate the next texture unit for CbCr.
    glActiveTexture (d->textureUnit + 1);
    // Create a new CbCr texture from the video texture cache.
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       d->textureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RG_EXT,
                                                       (int)width/2,
                                                       (int)height/2,
                                                       GL_RG_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       1,
                                                       &d->chromaTexture);
    if (err)
    {
        NSLog(@"Error with CVOpenGLESTextureCacheCreateTextureFromImage: %d", err);
        return;
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(d->chromaTexture), CVOpenGLESTextureGetName(d->chromaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindTexture(GL_TEXTURE_2D, 0);
}

void MeshRenderer::enableVertexBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->vertexVbo[meshIndex]);
    glEnableVertexAttribArray(CustomShader::ATTRIB_VERTEX);
    glVertexAttribPointer(CustomShader::ATTRIB_VERTEX, 3, GL_FLOAT, GL_FALSE, 0, 0);
}

void MeshRenderer::disableVertexBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->vertexVbo[meshIndex]);
    glDisableVertexAttribArray(CustomShader::ATTRIB_VERTEX);
}

void MeshRenderer::enableNormalBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->normalsVbo[meshIndex]);
    glEnableVertexAttribArray(CustomShader::ATTRIB_NORMAL);
    glVertexAttribPointer(CustomShader::ATTRIB_NORMAL, 3, GL_FLOAT, GL_FALSE, 0, 0);
}

void MeshRenderer::disableNormalBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->normalsVbo[meshIndex]);
    glDisableVertexAttribArray(CustomShader::ATTRIB_NORMAL);
}

void MeshRenderer::enableVertexColorBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->colorsVbo[meshIndex]);
    glEnableVertexAttribArray(CustomShader::ATTRIB_COLOR);
    glVertexAttribPointer(CustomShader::ATTRIB_COLOR, 3, GL_FLOAT, GL_FALSE, 0, 0);
}

void MeshRenderer::disableVertexColorBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->colorsVbo[meshIndex]);
    glDisableVertexAttribArray(CustomShader::ATTRIB_COLOR);
}

void MeshRenderer::enableVertexTexcoordsBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->texcoordsVbo[meshIndex]);
    glEnableVertexAttribArray(CustomShader::ATTRIB_TEXCOORD);
    glVertexAttribPointer(CustomShader::ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 0, 0);
}

void MeshRenderer::disableVertexTexcoordBuffer (int meshIndex)
{
    glBindBuffer(GL_ARRAY_BUFFER, d->texcoordsVbo[meshIndex]);
    glDisableVertexAttribArray(CustomShader::ATTRIB_TEXCOORD);
}

void MeshRenderer::enableLinesElementBuffer (int meshIndex)
{
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, d->linesVbo[meshIndex]);
    glLineWidth(1.0);
}

void MeshRenderer::enableTrianglesElementBuffer (int meshIndex)
{
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, d->facesVbo[meshIndex]);
}

void MeshRenderer::renderPartialMesh(int meshIndex)
{
    if (d->numTriangleIndices[meshIndex] <= 0) // nothing uploaded.
        return;
    
    switch (d->currentRenderingMode)
    {
        case RenderingModeXRay:
        {
            enableLinesElementBuffer(meshIndex);
            enableVertexBuffer(meshIndex);
            enableNormalBuffer(meshIndex);
            glDrawElements(GL_LINES, d->numLinesIndices[meshIndex], GL_UNSIGNED_SHORT, 0);
            disableNormalBuffer(meshIndex);
            disableVertexBuffer(meshIndex);
            break;
        }
            
        case RenderingModeLightedGray:
        {
            enableTrianglesElementBuffer(meshIndex);
            enableVertexBuffer(meshIndex);
            enableNormalBuffer(meshIndex);
            glDrawElements(GL_TRIANGLES, d->numTriangleIndices[meshIndex], GL_UNSIGNED_SHORT, 0);
            disableNormalBuffer(meshIndex);
            disableVertexBuffer(meshIndex);
            break;
        }
            
        case RenderingModePerVertexColor:
        {
            enableTrianglesElementBuffer(meshIndex);
            enableVertexBuffer(meshIndex);
            enableNormalBuffer(meshIndex);
            enableVertexColorBuffer(meshIndex);
            glDrawElements(GL_TRIANGLES, d->numTriangleIndices[meshIndex], GL_UNSIGNED_SHORT, 0);
            disableVertexColorBuffer(meshIndex);
            disableNormalBuffer(meshIndex);
            disableVertexBuffer(meshIndex);
            break;
        }

        case RenderingModeTextured:
        {
            enableTrianglesElementBuffer(meshIndex);
            enableVertexBuffer(meshIndex);
            enableVertexTexcoordsBuffer(meshIndex);
            glDrawElements(GL_TRIANGLES, d->numTriangleIndices[meshIndex], GL_UNSIGNED_SHORT, 0);
            disableVertexTexcoordBuffer(meshIndex);
            disableVertexBuffer(meshIndex);
            break;
        }

        default:
            NSLog(@"Unknown rendering mode.");
            break;
    }
    
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void MeshRenderer::render(const GLKMatrix4& projectionMatrix, const GLKMatrix4& modelViewMatrix)
{
    if (d->currentRenderingMode == RenderingModePerVertexColor && !d->hasPerVertexColor && d->hasTexture && d->hasPerVertexUV)
    {
        NSLog(@"Warning: The mesh has no per-vertex colors, but a texture, switching the rendering mode to RenderingModeTextured");
        d->currentRenderingMode = RenderingModeTextured;
    }
    else if (d->currentRenderingMode == RenderingModeTextured && (!d->hasTexture || !d->hasPerVertexUV) && d->hasPerVertexColor)
    {
        NSLog(@"Warning: The mesh has no texture, but per-vertex colors, switching the rendering mode to RenderingModePerVertexColor");
        d->currentRenderingMode = RenderingModePerVertexColor;
    }
    
    switch (d->currentRenderingMode)
    {
        case RenderingModeXRay:
            d->xRayShader.enable();
            d->xRayShader.prepareRendering(projectionMatrix.m, modelViewMatrix.m);
            break;
            
        case RenderingModeLightedGray:
            d->lightedGrayShader.enable();
            d->lightedGrayShader.prepareRendering(projectionMatrix.m, modelViewMatrix.m);
            break;

        case RenderingModePerVertexColor:
            if (!d->hasPerVertexColor)
            {
                NSLog(@"Warning: the mesh has no colors, skipping rendering.");
                return;
            }
            d->perVertexColorShader.enable();
            d->perVertexColorShader.prepareRendering(projectionMatrix.m, modelViewMatrix.m);
            break;
            
        case RenderingModeTextured:
            if (!d->hasTexture || d->lumaTexture == NULL || d->chromaTexture == NULL)
            {
                NSLog(@"Warning: null textures, skipping rendering.");
                return;
            }
            
            glActiveTexture(d->textureUnit);
            glBindTexture(CVOpenGLESTextureGetTarget(d->lumaTexture),
                          CVOpenGLESTextureGetName(d->lumaTexture));
            
            glActiveTexture(d->textureUnit + 1);
            glBindTexture(CVOpenGLESTextureGetTarget(d->chromaTexture),
                          CVOpenGLESTextureGetName(d->chromaTexture));
            
            d->yCbCrTextureShader.enable();
            d->yCbCrTextureShader.prepareRendering(projectionMatrix.m, modelViewMatrix.m, d->textureUnit);
            break;

        default:
            NSLog(@"Unknown rendering mode.");
            return;
    }
    
    // Keep previous GL_DEPTH_TEST state
    BOOL wasDepthTestEnabled = glIsEnabled(GL_DEPTH_TEST);
    glEnable(GL_DEPTH_TEST);
    
    for (int i = 0; i < d->numUploadedMeshes; ++i)
    {
        renderPartialMesh (i);
    }
    
    if (!wasDepthTestEnabled)
        glDisable(GL_DEPTH_TEST);
}

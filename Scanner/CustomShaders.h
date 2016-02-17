/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#pragma once

#include <GLKit/GLKit.h>

// Helper functions.
GLuint loadOpenGLProgramFromString (const char *vertex_shader_src,
                                    const char *fragment_shader_src,
                                    const int num_attributes,
                                    GLuint *attribute_ids,
                                    const char **attribute_names);

class CustomShader
{
public:
    enum {
        ATTRIB_VERTEX,
        ATTRIB_NORMAL,
        ATTRIB_COLOR,
        ATTRIB_TEXCOORD,
    };
    
public:
    CustomShader ()
    : _loaded (false)
    {}
    
public:
    
    virtual void load () = 0;
    
    virtual void enable ()
    {
        if (!_loaded)
            load ();
        glUseProgram (_glProgram);
    }
    
protected:
    virtual const char *vertexShaderSource() = 0;
    virtual const char *fragmentShaderSource() = 0;
    
protected:
    GLuint _glProgram;
    bool _loaded;
};


class LightedGrayShader : public CustomShader
{
public:
    
    virtual void prepareRendering (const float *projection, const float *modelView)
    {
        glUniformMatrix4fv(_modelviewLocation, 1, GL_FALSE, modelView);
        glUniformMatrix4fv (_projectionLocation, 1, GL_FALSE, projection);
        
        glDisable (GL_BLEND);
    }
    
    virtual void load()
    {
        const int NUM_ATTRIBS = 2;
        
        GLuint attributeIds[NUM_ATTRIBS] = { ATTRIB_VERTEX, ATTRIB_NORMAL };
        const char *attributeNames[NUM_ATTRIBS] = { "a_position", "a_normal" };
        
        _glProgram = loadOpenGLProgramFromString(vertexShaderSource(), fragmentShaderSource(), NUM_ATTRIBS, attributeIds, attributeNames);
        
        _projectionLocation = glGetUniformLocation(_glProgram, "u_perspective_projection");
        _modelviewLocation = glGetUniformLocation(_glProgram, "u_modelview");
        
        glUseProgram(0);
        _loaded = true;
    }
    
protected:
    
    const char *vertexShaderSource ()
    {
        return R"(
        attribute vec4 a_position;
        attribute vec3 a_normal;
        
        uniform mat4 u_perspective_projection;
        uniform mat4 u_modelview;
        
        varying float v_luminance;
        
        void main()
        {
            gl_Position = u_perspective_projection*u_modelview*a_position;
            
            //mat3 scaledRotation = mat3(u_modelview);
            
            // Directional lighting that moves with the camera
            vec3 vec = mat3(u_modelview)*a_normal;
            
            // Slightly reducing the effect of the lighting
            v_luminance = 0.5*abs(vec.z) + 0.5;
        }
        )";
    }
    
    const char *fragmentShaderSource ()
    {
        return R"(
        precision mediump float;
        
        varying float v_luminance;
        
        void main()
        {
            gl_FragColor = vec4(v_luminance, v_luminance, v_luminance, 1.0);
        }
        )";
    }
    
private:
    GLuint _projectionLocation;
    GLuint _modelviewLocation;
};


class PerVertexColorShader : public CustomShader
{
public:
    
    virtual void load()
    {
        const int NUM_ATTRIBS = 3;
        
        GLuint attributeIds[NUM_ATTRIBS] = { ATTRIB_VERTEX, ATTRIB_NORMAL, ATTRIB_COLOR };
        const char *attributeNames[NUM_ATTRIBS] = { "a_position", "a_normal", "a_color" };
        
        _glProgram = loadOpenGLProgramFromString(vertexShaderSource(), fragmentShaderSource(), NUM_ATTRIBS, attributeIds, attributeNames);
        
        _projectionLocation = glGetUniformLocation(_glProgram, "u_perspective_projection");
        _modelviewLocation = glGetUniformLocation(_glProgram, "u_modelview");
        
        glUseProgram(0);
        _loaded = true;
    }
    
    virtual void prepareRendering (const float *projection, const float *modelView)
    {
        glUniformMatrix4fv(_modelviewLocation, 1, GL_FALSE, modelView);
        glUniformMatrix4fv (_projectionLocation, 1, GL_FALSE, projection);
        
        glDisable (GL_BLEND);
    }
    
protected:
    
    const char *vertexShaderSource ()
    {
        return R"(
        attribute vec4 a_position;
        attribute vec3 a_normal;
        attribute vec3 a_color;
        uniform mat4 u_perspective_projection;
        uniform mat4 u_modelview;
        
        varying vec3 v_color;
        
        void main()
        {
            gl_Position = u_perspective_projection*u_modelview*a_position;
            v_color = a_color;
        }
        )";
    }
    
    const char *fragmentShaderSource ()
    {
        return R"(
        precision mediump float;
        
        varying vec3 v_color;
        void main()
        {
            gl_FragColor = vec4(v_color, 1.0);
        }
        )";
    }
    
private:
    GLuint _projectionLocation;
    GLuint _modelviewLocation;
};


class XrayShader : public CustomShader
{
public:
    
    virtual void load()
    {
        const int NUM_ATTRIBS = 2;
        
        GLuint attributeIds[NUM_ATTRIBS] = { ATTRIB_VERTEX, ATTRIB_NORMAL };
        const char *attributeNames[NUM_ATTRIBS] = { "a_position", "a_normal" };
        
        _glProgram = loadOpenGLProgramFromString(vertexShaderSource(), fragmentShaderSource(), NUM_ATTRIBS, attributeIds, attributeNames);
        
        _projectionLocation = glGetUniformLocation(_glProgram, "u_perspective_projection");
        _modelviewLocation = glGetUniformLocation(_glProgram, "u_modelview");
        
        glUseProgram(0);
        _loaded = true;
    }
    
    virtual void prepareRendering (const float *projection, const float *modelView)
    {
        glUniformMatrix4fv(_modelviewLocation, 1, GL_FALSE, modelView);
        glUniformMatrix4fv (_projectionLocation, 1, GL_FALSE, projection);
        
        glDisable (GL_BLEND);
    }
    
protected:
    
    virtual const char *vertexShaderSource ()
    {
        return R"(
        attribute vec4 a_position;
        attribute vec3 a_normal;
        uniform mat4 u_perspective_projection;
        uniform mat4 u_modelview;
        
        varying float v_luminance;
        
        void main()
        {
            gl_Position = u_perspective_projection*u_modelview*a_position;
            
            // Directional lighting that moves with the camera
            vec3 vec = mat3(u_modelview)*a_normal;
            v_luminance = 1.0 - abs(vec.z);
        }
        )";
    }
    
    virtual const char *fragmentShaderSource ()
    {
        return R"(
        precision mediump float;
        
        varying float v_luminance;
        
        void main()
        {
            gl_FragColor = vec4(v_luminance, v_luminance, v_luminance, 1.0);
        }
        )";
    }
    
private:
    GLuint _projectionLocation;
    GLuint _modelviewLocation;
};

class YCbCrTextureShader : public CustomShader
{
public:
    virtual void load ()
    {
        GLuint attributeIds[2] = { ATTRIB_VERTEX, ATTRIB_TEXCOORD};
        const char *attributeNames[2] = { "a_position", "a_texCoord" };
        
        _glProgram = loadOpenGLProgramFromString(vertexShaderSource(), fragmentShaderSource(), 2, attributeIds, attributeNames);
        
        _projectionLocation = glGetUniformLocation(_glProgram, "u_perspective_projection");
        _modelviewLocation = glGetUniformLocation(_glProgram, "u_modelview");
        _ySamplerLocation = glGetUniformLocation(_glProgram, "s_texture_y");
        _cbcrSamplerLocation = glGetUniformLocation(_glProgram, "s_texture_cbcr");
        
        glUseProgram(0);
        _loaded = true;
    }
    
    virtual void prepareRendering (const float *projection, const float *modelView, GLint textureUnit)
    {
        glUniformMatrix4fv (_modelviewLocation, 1, GL_FALSE, modelView);
        glUniformMatrix4fv (_projectionLocation, 1, GL_FALSE, projection);
        
        glUniform1i (_ySamplerLocation, textureUnit - GL_TEXTURE0);
        glUniform1i (_cbcrSamplerLocation, textureUnit + 1 - GL_TEXTURE0);
    }
    
    virtual const char *vertexShaderSource ()
    {
        return R"(
        attribute vec4 a_position;
        attribute vec2 a_texCoord;
        uniform mat4 u_perspective_projection;
        uniform mat4 u_modelview;
        
        varying vec2 v_texCoord;
        
        void main()
        {
            gl_Position = u_perspective_projection*u_modelview*a_position;
            
            v_texCoord = a_texCoord;
        }
        )";
    }
    
    virtual const char *fragmentShaderSource ()
    {
        return R"(
        precision mediump float;
        
        uniform sampler2D s_texture_y;
        uniform sampler2D s_texture_cbcr;
        
        varying vec2 v_texCoord;
        void main()
        {
            mediump vec3 yuv;
            lowp vec3 rgb;
            
            yuv.x = texture2D(s_texture_y, v_texCoord).r;
            yuv.yz = texture2D(s_texture_cbcr, v_texCoord).rg - vec2(0.5, 0.5);
            
            rgb = mat3(      1,       1,      1,
                       0, -.18732, 1.8556,
                       1.57481, -.46813,      0) * yuv;
            
            gl_FragColor = vec4(rgb, 1.0);
        }
        )";
    }
    
public:
    GLuint _projectionLocation;
    GLuint _modelviewLocation;
    GLuint _ySamplerLocation;
    GLuint _cbcrSamplerLocation;
};

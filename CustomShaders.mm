/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#include "CustomShaders.h"

GLuint loadOpenGLShaderFromString(GLenum type, const char *shaderSrc)
{
    GLuint shader;
    GLint compiled;
    
    // Create the shader object
    shader = glCreateShader ( type );
    
    if ( shader == 0 )
        return 0;
    
    // Load the shader source
    glShaderSource ( shader, 1, &shaderSrc, NULL );
    
    // Compile the shader
    glCompileShader ( shader );
    
    // Check the compile status
    glGetShaderiv ( shader, GL_COMPILE_STATUS, &compiled );
    
    if ( !compiled )
    {
        GLint infoLen = 0;
        
        glGetShaderiv ( shader, GL_INFO_LOG_LENGTH, &infoLen );
        
        if ( infoLen > 1 )
        {
            char* infoLog = (char*)malloc (sizeof(char) * infoLen );
            
            glGetShaderInfoLog ( shader, infoLen, NULL, infoLog );
            printf( "Error compiling shader:\n%s\n", infoLog );
            printf( "Code: %s\n", shaderSrc);
            
            free ( infoLog );
        }
        
        glDeleteShader ( shader );
        return 0;
    }
    
    return shader;
    
}

GLuint loadOpenGLProgramFromString (const char *vertex_shader_src,
                                    const char *fragment_shader_src,
                                    const int num_attributes,
                                    GLuint *attribute_ids,
                                    const char **attribute_names)
{
    GLuint vertex_shader;
    GLuint fragment_shader;
    GLuint program_object;
    
    // Load the vertex/fragment shaders
    vertex_shader = loadOpenGLShaderFromString(GL_VERTEX_SHADER, vertex_shader_src);
    if (vertex_shader == 0 )
        return 0;
    
    fragment_shader = loadOpenGLShaderFromString(GL_FRAGMENT_SHADER, fragment_shader_src);
    if (fragment_shader == 0 )
    {
        glDeleteShader(vertex_shader);
        return 0;
    }
    
    // Create the program object
    program_object = glCreateProgram();
    
    if (program_object == 0)
        return 0;
    
    glAttachShader (program_object, vertex_shader);
    glAttachShader (program_object, fragment_shader);
    
    // Bind attributes before linking
    for(int i = 0; i < num_attributes; i++)
        glBindAttribLocation(program_object, attribute_ids[i], attribute_names[i]);
    
    GLint linked;
    
    // Link the program
    glLinkProgram(program_object);
    
    // Check the link status
    glGetProgramiv(program_object, GL_LINK_STATUS, &linked);
    
    if ( !linked )
    {
        GLint infoLen = 0;
        
        glGetProgramiv (program_object, GL_INFO_LOG_LENGTH, &infoLen);
        
        if (infoLen > 1)
        {
            char* infoLog = (char*)malloc (sizeof(char) * infoLen);
            
            glGetProgramInfoLog(program_object, infoLen, NULL, infoLog);
            
            NSLog(@"Error linking program:\n%s\n", infoLog);
            
            free(infoLog);
        }
        
        glDeleteProgram(program_object);
        return 0;
    }
    
    // Free up no longer needed shader resources
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    
    return program_object;
}

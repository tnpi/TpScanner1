#import <UIKit/UIKit.h>

#import <AVFoundation/AVFoundation.h>
#define HAS_LIBCXX


struct DisplayData
{
    // OpenGL context.
    EAGLContext *context;
    
    // OpenGL Texture reference for y images.
    CVOpenGLESTextureRef lumaTexture;
    
    // OpenGL Texture reference for color images.
    CVOpenGLESTextureRef chromaTexture;
    
    // OpenGL Texture cache for the color camera.
    CVOpenGLESTextureCacheRef videoTextureCache;
    /*
    // Shader to render a GL texture as a simple quad.
    STGLTextureShaderYCbCr *yCbCrTextureShader;
    STGLTextureShaderRGBA *rgbaTextureShader;
    
    GLuint depthAsRgbaTexture;
    
    // Renders the volume boundaries as a cube.
    STCubeRenderer *cubeRenderer;
     */
};


@interface ViewController : UIViewController
{
    
    DisplayData _display;
    
}
@end


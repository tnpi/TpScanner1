/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "ViewController+OpenGL.h"

#include <cmath>
#include <limits>

// tanaka add
#define BUFFER_OFFSET(i) ((char *)NULL + (i))



@implementation ViewController (OpenGL)

#pragma mark -  OpenGL


// tanaka テスト用
// http://qiita.com/weed/items/3992814597432fef3c95
typedef struct {
    GLKVector3 position;
} Vertex;

//　テスト用 三角の座標
// verticesはvertex（頂点）の複数形
static const Vertex vertices[] =
{
    {{-0.5f, -0.5f,  0.0}},
    {{ 0.5f, -0.5f,  0.0}},
    {{-0.5f,  0.5f,  0.0}}
};
GLuint g_texID;


// OpenGLのセットアップ
- (void)setupGL
{
    
    // Create an EAGLContext for our EAGLView.
    // EAGLContextを 私たちのEAGLViewからをつくる
    _display.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_display.context) { NSLog(@"Failed to create ES context"); }
    
    // EAGLContextに現在のコンテキストを設定、EAGLビューのビューにも設定
    [EAGLContext setCurrentContext:_display.context];
    [(EAGLView*)self.view setContext:_display.context];
    [(EAGLView*)self.view setFramebuffer];
    
    // シェーダーの初期化 (StructureSDKの機能) RGBA, yCbCr（カメラ）
    _display.yCbCrTextureShader = [[STGLTextureShaderYCbCr alloc] init];
    _display.rgbaTextureShader = [[STGLTextureShaderRGBA alloc] init];
    
    // Set up texture and textureCache for images output by the color camera.
    // テクスチャとテクスチャキャッシュのセットアップ　カラーカメラの画像出力のための
    CVReturn texError = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _display.context, NULL, &_display.videoTextureCache);
    if (texError) { NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", texError); }
    
    ///OpenGLではglBindTextureでテクスチャをバインドし，glTexCoordでテクスチャ座標を指定して貼り付ける．このときテクスチャを表すのがglGenTexture関数に生成されたテクスチャオブジェクトである．
    glGenTextures(1, &_display.depthAsRgbaTexture);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _display.depthAsRgbaTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    /*
    glGenBuffers(2, &vertexBufferID);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBufferID);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
     */
}


// GLビューポートのセットアップ
- (void)setupGLViewport
{
    const float vgaAspectRatio = 640.0f/480.0f;
    
    // Helper function to handle float precision issues.
    // floatの正確性？
    auto nearlyEqual = [] (float a, float b) { return std::abs(a-b) < std::numeric_limits<float>::epsilon(); };
    
    CGSize frameBufferSize = [(EAGLView*)self.view getFramebufferSize];
    
    float imageAspectRatio = 1.0f;
    
    float framebufferAspectRatio = frameBufferSize.width/frameBufferSize.height;
    
    // The iPad's diplay conveniently has a 4:3 aspect ratio just like our video feed.
    // Some iOS devices need to render to only a portion of the screen so that we don't distort
    // our RGB image. Alternatively, you could enlarge the viewport (losing visual information),
    // but fill the whole screen.
    if (!nearlyEqual (framebufferAspectRatio, vgaAspectRatio))
        imageAspectRatio = 480.f/640.0f;
    
    _display.viewport[0] = 0;
    _display.viewport[1] = 0;
    _display.viewport[2] = frameBufferSize.width*imageAspectRatio;
    _display.viewport[3] = frameBufferSize.height;
}


// GLカラーテクスチャをアップロード
- (void)uploadGLColorTexture:(STColorFrame*)colorFrame
{
    if (!_display.videoTextureCache)
    {
        NSLog(@"Cannot upload color texture: No texture cache is present.");
        return;
    }
    
    // Clear the previous color texture.
    // 前のカラーテクスチャを消去
    if (_display.lumaTexture)
    {
        CFRelease (_display.lumaTexture);
        _display.lumaTexture = NULL;
    }
    
    // Clear the previous color texture
    // 前のカラーテクスチャを消去
    if (_display.chromaTexture)
    {
        CFRelease (_display.chromaTexture);
        _display.chromaTexture = NULL;
    }
    
    // Displaying image with width over 1280 is an overkill. Downsample it to save bandwidth.
    // 1280pxを超える画像表示は一種のオーバーキルなので、帯域幅を守るためにダウンサンプルする。
    while( colorFrame.width > 2560 )
        colorFrame = colorFrame.halfResolutionColorFrame;
    
    CVReturn err;
    
    // Allow the texture cache to do internal cleanup.
    CVOpenGLESTextureCacheFlush(_display.videoTextureCache, 0);
    
    // カラーカメラのサンプルバッファから画像を取得して、画像バッファCVImageBufferRefを作る
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(colorFrame.sampleBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    OSType pixelFormat = CVPixelBufferGetPixelFormatType (pixelBuffer);
    NSAssert(pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, @"YCbCr is expected!");
    
    // lumaTexture関係 ------------
    // Activate the default texture unit.
    glActiveTexture (GL_TEXTURE0);
    
    // Create an new Y texture from the video texture cache.
    // 輝度成分のテクスチャを作る？
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _display.videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RED_EXT,
                                                       (int)width,
                                                       (int)height,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &_display.lumaTexture);
    
    if (err)
    {
        NSLog(@"Error with CVOpenGLESTextureCacheCreateTextureFromImage: %d", err);
        return;
    }
    
    // Set good rendering properties for the new texture.
    glBindTexture(CVOpenGLESTextureGetTarget(_display.lumaTexture), CVOpenGLESTextureGetName(_display.lumaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // chromaTexture関係に同種の処理 -----------
    // Activate the default texture unit.
    glActiveTexture (GL_TEXTURE1);
    
    // Create an new CbCr texture from the video texture cache.
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _display.videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RG_EXT,
                                                       (int)width/2,
                                                       (int)height/2,
                                                       GL_RG_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       1,
                                                       &_display.chromaTexture);
    
    if (err)
    {
        NSLog(@"Error with CVOpenGLESTextureCacheCreateTextureFromImage: %d", err);
        return;
    }
    
    // Set rendering properties for the new texture.
    glBindTexture(CVOpenGLESTextureGetTarget(_display.chromaTexture), CVOpenGLESTextureGetName(_display.chromaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
}


// デプスからカラーテクスチャーをアップロード
- (void)uploadGLColorTextureFromDepth:(STDepthFrame*)depthFrame
{
    // デプスをカラフルな画像に変換
    [_depthAsRgbaVisualizer convertDepthFrameToRgba:depthFrame];
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _display.depthAsRgbaTexture);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _depthAsRgbaVisualizer.width, _depthAsRgbaVisualizer.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, _depthAsRgbaVisualizer.rgbaBuffer);
    
}


// デプスフレームからシーンを描画
- (void)renderSceneForDepthFrame:(STDepthFrame*)depthFrame colorFrameOrNil:(STColorFrame*)colorFrame
{
    // Activate our view framebuffer.
    [(EAGLView *)self.view setFramebuffer];
    
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glClear(GL_DEPTH_BUFFER_BIT);
    
    // ビューポートの設定
    glViewport (_display.viewport[0], _display.viewport[1], _display.viewport[2], _display.viewport[3]);
    
    // スキャナの状態ごとに
    switch (_slamState.scannerState)
    {
        // キューブ配置のとき
        case ScannerStateCubePlacement:
        {
            // Render the background image from the color camera.
            [self renderCameraImage];
            
            if (_slamState.cameraPoseInitializer.hasValidPose)
            {
                GLKMatrix4 depthCameraPose = _slamState.cameraPoseInitializer.cameraPose;
                
                GLKMatrix4 cameraViewpoint;
                float alpha;
                if (_useColorCamera)
                {
                    // Make sure the viewpoint is always to color camera one, even if not using registered depth.
                    
                    GLKMatrix4 colorCameraPoseInStreamCoordinateSpace;
                    [depthFrame colorCameraPoseInDepthCoordinateFrame:colorCameraPoseInStreamCoordinateSpace.m];
                    
                    // colorCameraPoseInWorld
                    cameraViewpoint = GLKMatrix4Multiply(depthCameraPose, colorCameraPoseInStreamCoordinateSpace);
                    alpha = 0.5;
                }
                else
                {
                    cameraViewpoint = depthCameraPose;
                    alpha = 1.0;
                }
                
                // Highlighted depth values inside the current volume area.
                [_display.cubeRenderer renderHighlightedDepthWithCameraPose:cameraViewpoint alpha:alpha];
                
                // Render the wireframe cube corresponding to the current scanning volume.
                [_display.cubeRenderer renderCubeOutlineWithCameraPose:cameraViewpoint
                                                      depthTestEnabled:false
                                                  occlusionTestEnabled:true];
            }
            break;
        }

        // スキャン中のとき
        case ScannerStateScanning:
        {
            // Enable GL blending to show the mesh with some transparency.
            // 透過を有効にする
            glEnable (GL_BLEND);
            
            // Render the background image from the color camera.
            [self renderCameraImage];
            
            // Render the current mesh reconstruction using the last estimated camera pose.
            // 現在のメッシュを最後のカメラ姿勢に基づいて再構成して描画する
            GLKMatrix4 depthCameraPose = [_slamState.tracker lastFrameCameraPose];
            
            GLKMatrix4 cameraGLProjection;
            if (_useColorCamera)
            {
                cameraGLProjection = colorFrame.glProjectionMatrix;
            }
            else
            {
                cameraGLProjection = depthFrame.glProjectionMatrix;
            }
            
            GLKMatrix4 cameraViewpoint;
            if (_useColorCamera && !_options.useHardwareRegisteredDepth)
            {
                // If we want to use the color camera viewpoint, and are not using registered depth, then
                // we need to deduce the color camera pose from the depth camera pose.
                
                GLKMatrix4 colorCameraPoseInDepthCoordinateSpace;
                [depthFrame colorCameraPoseInDepthCoordinateFrame:colorCameraPoseInDepthCoordinateSpace.m];
                
                // colorCameraPoseInWorld
                cameraViewpoint = GLKMatrix4Multiply(depthCameraPose, colorCameraPoseInDepthCoordinateSpace);
            }
            else
            {
                cameraViewpoint = depthCameraPose;
            }
            
            // メッシュを描画する 多分グレースケールのアレを重ね合わせるあれ
            // important
            // テスト的にコメントアウト by tanaka
            /*
            [_slamState.scene renderMeshFromViewpoint:cameraViewpoint
                                   cameraGLProjection:cameraGLProjection
                                                alpha:0.8
                             highlightOutOfRangeDepth:true
                                            wireframe:false];
             */
            
            // ----------------------------------------------------------------------
            // ここで自前でOpenGLでポリゴン変換・表示処理を追加すれば、
            // とりあえずリアルタイムに3Dスキャン・表示ができるはず tanaka
            // important
            // ----------------------------------------------------------------------
            /*
            glEnableVertexAttribArray(GLKVertexAttribPosition);
            glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), BUFFER_OFFSET(0));
            glDrawArrays(GL_TRIANGLES, 0, 3);
             */
            //[self tmpRender];
            static const GLfloat vtx[] = {
                200, 120,
                440, 120,
                440, 360,
                200, 360,
            };
            
            /*
             glTexCoordPointer(2, GL_FLOAT, 0, texuv);
             
             // Step6. テクスチャの画像指定
             glBindTexture(GL_TEXTURE_2D, g_texID);
             */
            
            NSLog(@"exec tmpRender");
            
            // Step7. テクスチャの描画
            //glEnable(GL_TEXTURE_2D);
            glClear(GL_COLOR_BUFFER_BIT);       // 背景が真っ黒になる（キューブ以外見えない）
            glEnableClientState(GL_VERTEX_ARRAY);

            glVertexPointer(2, GL_FLOAT, 0, vtx);

            //glEnableClientState(GL_TEXTURE_COORD_ARRAY);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            //glDisableClientState(GL_TEXTURE_COORD_ARRAY);
            glDisableClientState(GL_VERTEX_ARRAY);
            //glDisable(GL_TEXTURE_2D);
            glFlush();

            
            glDisable (GL_BLEND);
            NSLog(@"exec tmpRender end");
            
            // Render the wireframe cube corresponding to the scanning volume.
            // Here we don't enable occlusions to avoid performance hit.
            // ワイヤフレームのキューブをレンダリングする
            [_display.cubeRenderer renderCubeOutlineWithCameraPose:cameraViewpoint
                                                  depthTestEnabled:true
                                              occlusionTestEnabled:false];
            break;
        }
            
        // MeshViewerController handles this.
        // メッシュビューの時
        case ScannerStateViewing:
        default: {}
    };
    
    // Check for OpenGL errors
    GLenum err = glGetError ();
    if (err != GL_NO_ERROR)
        NSLog(@"glError = %x", err);
    
    // Display the rendered framebuffer.
    [(EAGLView *)self.view presentFramebuffer];
}

-(void)tmpRender
{
    static const GLfloat vtx[] = {
        200, 120,
        440, 120,
        440, 360,
        200, 360,
    };
    glVertexPointer(2, GL_FLOAT, 0, vtx);
    
    // Step5. テクスチャの領域指定
    static const GLfloat texuv[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        1.0f, 0.0f,
        0.0f, 0.0f,
    };
    /*
    glTexCoordPointer(2, GL_FLOAT, 0, texuv);
    
    // Step6. テクスチャの画像指定
    glBindTexture(GL_TEXTURE_2D, g_texID);
    */
    
    NSLog(@"exec tmpRender");
    
    // Step7. テクスチャの描画
    //glEnable(GL_TEXTURE_2D);
    glEnableClientState(GL_VERTEX_ARRAY);
    //glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    //glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    //glDisable(GL_TEXTURE_2D);
}


// カメラ画像のレンダリング
- (void)renderCameraImage
{
    // カラーカメラを使う場合
    if (_useColorCamera)
    {
        if (!_display.lumaTexture || !_display.chromaTexture)
            return;
        
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(CVOpenGLESTextureGetTarget(_display.lumaTexture),
                      CVOpenGLESTextureGetName(_display.lumaTexture));
        
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(CVOpenGLESTextureGetTarget(_display.chromaTexture),
                      CVOpenGLESTextureGetName(_display.chromaTexture));
        
        glDisable(GL_BLEND);
        [_display.yCbCrTextureShader useShaderProgram];
        [_display.yCbCrTextureShader renderWithLumaTexture:GL_TEXTURE0 chromaTexture:GL_TEXTURE1];
    }
    // デプスセンサを使う場合
    else
    {
        if(_display.depthAsRgbaTexture == 0)
            return;
        
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, _display.depthAsRgbaTexture);
        [_display.rgbaTextureShader useShaderProgram];                  // シェーダを使う
        [_display.rgbaTextureShader renderTexture:GL_TEXTURE0];
    }
    glUseProgram (0);
    
}


@end
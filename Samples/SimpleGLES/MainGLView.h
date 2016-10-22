//
//  MainGLView.h
//  SimpleGLES
//
//  Created by 田中翔吾 on 2015/11/27.
//  Copyright © 2015年 田中翔吾. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>


@interface MainGLView : UIView
{
    /** OpenGL ESの描画設定を保持する物 **/
    EAGLContext *context;
    
    /** フレームバッファとレンダバッファ **/
    GLuint mFrameBuffer;
    
    
    GLuint mColorBuffer;    // カラーレンダバッファ
    
    
}

@property (nonatomic, retain) EAGLContext *context;


- ( id ) initWithCoder:(NSCoder *)aDecoder;

//- (void)setFramebuffer;

/**
 *	描画準備　ES2.0でいるか怪しい
 */
//- ( void ) BeginScene;

/**
 *	描画終了　ES2.0でいるか怪しい
 */
//- ( void ) EndScene;

@end

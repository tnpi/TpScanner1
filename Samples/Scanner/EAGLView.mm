/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/


#import <QuartzCore/QuartzCore.h>

#import "EAGLView.h"
#import <mach/mach.h>

@interface EAGLView () {

    // The pixel dimensions of the CAEAGLLayer.
    // CAEAGLLayerのピクセル面
    GLint framebufferWidth;
    GLint framebufferHeight;
    
    // The OpenGL ES names for the framebuffer and renderbuffer used to render to this view.
    // OpenGL ESは名づける、このビューを描画するために、フレームバッファートレンダーバッファーを使う？？
    GLuint defaultFramebuffer, colorRenderbuffer, depthRenderbuffer;

}

- (void)createFramebuffer;
- (void)deleteFramebuffer;

@end


// 実装
@implementation EAGLView

@dynamic context;

// You must implement this method
// このメソッドをあなたは実装しなければならない
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


//The EAGL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:.
// EAGLビューはnibファイルの中にストアされています。-initWithCoderが送られる時、それは展開されます
- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if (self)
    {
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;     // このレイヤを持っているビューに対して描かないと画面に現れずエラーになるs
        
        eaglLayer.opaque = TRUE;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        
        self.contentScaleFactor = 1.0;
    }
    
    return self;
}

- (void)dealloc
{
    [self deleteFramebuffer];
}

- (EAGLContext *)context
{
    return context;
}

- (void)setContext:(EAGLContext *)newContext
{
    if (context != newContext)
    {
        [self deleteFramebuffer];
        context = newContext;
        
        [EAGLContext setCurrentContext:nil];
    }
}

// フレームバッファーを作る
- (void)createFramebuffer
{
    if (context && !defaultFramebuffer)
    {
        [EAGLContext setCurrentContext:context];
        
        // Create default framebuffer object.
		glGenFramebuffers(1, &defaultFramebuffer);
		glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
		
		// Create color render buffer and allocate backing store.
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);

        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
            NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

// フレームバッファーを削除
- (void)deleteFramebuffer
{
    if (context)
    {
        [EAGLContext setCurrentContext:context];
        
        if (defaultFramebuffer)
        {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (depthRenderbuffer)
        {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
        
        if (colorRenderbuffer)
        {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
    }
}

// フレームバッファーをセット
- (void)setFramebuffer
{
    if (context)
    {
        [EAGLContext setCurrentContext:context];
        
        if (!defaultFramebuffer) {
            [self createFramebuffer];
        }
        
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        glViewport(0, 0, framebufferWidth, framebufferHeight);
    }
}


- (BOOL)presentFramebuffer
{
    BOOL success = FALSE;
    
    // iOS may crash if presentRenderbuffer is called when the application is in background.
    // iOSはクラッシュするだろう　アプリケーションがバックグラウンドにある時に、presentRenderbufferが呼ばれたら
    if (context && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground)
    {
        [EAGLContext setCurrentContext:context];
        
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        success = [context presentRenderbuffer:GL_RENDERBUFFER];
    }
    
    return success;
}

// サブビューをレイアウトする
- (void)layoutSubviews
{
    [super layoutSubviews];
    
    // CAREFUL!!!! If you have autolayout enabled, you will re-create your framebuffer all the time if
    // your EAGLView has any subviews that are updated. For example, having a UILabel that is updated
    // to display FPS will result in layoutSubviews being called every frame. Two ways around this:
    // 1) don't use autolayout
    // 2) don't add any subviews to the EAGLView. Have the EAGLView be a subview of another "master" view.
    // 気をつけて！もしあなたが自動レイアウトを有効にしているなら、あなたはあなたのフレームバッファーをいつも再生成するでしょう、
    // あなたのEAGLViewが何かのサブビューを持っていてそれが更新される時。
    // 例えば、UIラベルを持っていてそれがFPSを表示するために更新された時、その結果はレイアウトサブビューでマイフレーム呼ばれる。
    // これには2つの方法があります
    //  1). autolayoutを使わない
    //  2). EAGLViewにサブビューを追加しない。EAGLビューを別のマスターのビューのサブビューにする
    
    // The framebuffer will be re-created at the beginning of the next setFramebuffer method call.
    [self deleteFramebuffer];
}

- (CGSize)getFramebufferSize
{
    return CGSizeMake(framebufferWidth, framebufferHeight);
}


@end

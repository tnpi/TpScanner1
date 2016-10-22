/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/


#import <UIKit/UIKit.h>

#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

// This class wraps the CAEAGLLayer from CoreAnimation into a convenient UIView subclass.
// The view content is basically an EAGL surface you render your OpenGL scene into.
// Note that setting the view non-opaque will only work if the EAGL surface has an alpha channel.
// このクラスはCAEAGLayerをラップします、コアアニメーションから　便利なUIviewサブクラスへ
// このビューコンテントは、基礎的なEAGLサーフェスです　あなたが描画するOpenGLシーンの中への
// 注意 非不透明な（透明な）ビューの設定は　 EAGLサーフェスがアルファチャンネルを持っている時だけ働きます
@interface EAGLView : UIView {

    EAGLContext *context;
    
}

@property (nonatomic, retain) EAGLContext *context;

- (void)setFramebuffer;
- (BOOL)presentFramebuffer;
- (CGSize)getFramebufferSize;

@end

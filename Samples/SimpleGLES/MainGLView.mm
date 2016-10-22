//
//  MainGLView.m
//  SimpleGLES
//
//  Created by 田中翔吾 on 2015/11/27.
//  Copyright © 2015年 田中翔吾. All rights reserved.
//

#import "MainGLView.h"



@implementation MainGLView

@dynamic context;

/**
 *	この関数を書くことで OpenGL ESを描画できるレイヤーを自動的にセットする
 */
+ ( Class )layerClass
{
    return [ CAEAGLLayer class ];
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/


//- (id)initWithFrame:(CGRect)frame
- ( id ) initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    
    if (self)
    {
        /** 設定されたレイヤの取得 **/
        CAEAGLLayer *eaglLayer = ( CAEAGLLayer *)self.layer;
        //CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;     // このレイヤを持っているビューに対して描かないと画面に現れずエラーになるs
        
        // 不透明にすることで処理速度が上がる
        eaglLayer.opaque = YES;
        
        /** 描画の設定を行う **/
        // 辞書登録をする。
        // 順番として 値 → キー
        eaglLayer.drawableProperties = [ NSDictionary dictionaryWithObjectsAndKeys:
                                       /** 描画後レンダバッファの内容を保持しない。 **/
                                       [ NSNumber numberWithBool:FALSE ],
                                       kEAGLDrawablePropertyRetainedBacking,
                                       /** カラーレンダバッファの1ピクセルあたりRGBAを8bitずつ保持する **/
                                       kEAGLColorFormatRGBA8,
                                       kEAGLDrawablePropertyColorFormat,
                                       /** 終了 **/
                                       nil ];
        
        self.contentScaleFactor = 1.0;
        
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];   // OpenGL ES2.0 DisplayData.EAGLContext
        
        
        //ここから別ソース
        
        // set context
        //[EAGLContext setCurrentContext:context];

        
        
    }

    return self;

    

}


- (EAGLContext *)context
{
    return context;
}


- (void)setContext:(EAGLContext *)newContext
{
    if (context != newContext)
    {
        //[self deleteFramebuffer];  temporary
        context = newContext;
        
        [EAGLContext setCurrentContext:nil];
    }
}


@end

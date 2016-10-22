//
//  ViewController.m
//  SimpleGLES
//
//  Created by 田中翔吾 on 2015/11/27.
//  Copyright © 2015年 田中翔吾. All rights reserved.
//

#import "ViewController.h"
#import "MainGLView.h"


//では、まず継承元を UIViewController に変更
//これで このViewController で勝手にOpenGL ESの初期化をさせない
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    /*
    [(EAGLView*)self.view setContext:_display.context];
    [(EAGLView*)self.view setFramebuffer];
    */
    
    //self.view.context
//    _display.context = self.view.context;
//    [EAGLContext setCurrentContext:_display.context];
//    [(EAGLView*)self.view setContext:_display.context];
 //   [(EAGLView*)self.view setFramebuffer];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

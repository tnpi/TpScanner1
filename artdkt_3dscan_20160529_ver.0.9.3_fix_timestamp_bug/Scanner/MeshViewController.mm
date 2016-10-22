/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "MeshViewController.h"
#import "MeshRenderer.h"
#import "ViewpointController.h"
#import "CustomUIKitStyles.h"

#import <ImageIO/ImageIO.h>

#import "STMesh+JAGSerialize.h"

#include <vector>
#include <cmath>


// Local Helper Functions
namespace
{
    
    // JPEGで保存
    void saveJpegFromRGBABuffer(const char* filename, unsigned char* src_buffer, int width, int height)
    {
        
        // 指定のファイル名でファイルオープン
        FILE *file = fopen(filename, "w");
        if(!file)
            return;
        
        CGColorSpaceRef colorSpace;
        CGImageAlphaInfo alphaInfo;
        CGContextRef context;
        
        colorSpace = CGColorSpaceCreateDeviceRGB();
        alphaInfo = kCGImageAlphaNoneSkipLast;
        context = CGBitmapContextCreate(src_buffer, width, height, 8, width * 4, colorSpace, alphaInfo);
        CGImageRef rgbImage = CGBitmapContextCreateImage(context);
        
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        CFMutableDataRef jpgData = CFDataCreateMutable(NULL, 0);
        
        CGImageDestinationRef imageDest = CGImageDestinationCreateWithData(jpgData, CFSTR("public.jpeg"), 1, NULL);
        CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault, // Our empty IOSurface properties dictionary
                                                     NULL,
                                                     NULL,
                                                     0,
                                                     &kCFTypeDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
        CGImageDestinationAddImage(imageDest, rgbImage, (CFDictionaryRef)options);
        CGImageDestinationFinalize(imageDest);
        CFRelease(imageDest);
        CFRelease(options);
        CGImageRelease(rgbImage);
        
        fwrite(CFDataGetBytePtr(jpgData), 1, CFDataGetLength(jpgData), file);
        fclose(file);
        CFRelease(jpgData);
    }
    
}


// 宣言
@interface MeshViewController ()
{
    STMesh *_mesh;
    CADisplayLink *_displayLink;
    MeshRenderer *_renderer;
    ViewpointController *_viewpointController;
    GLfloat _glViewport[4];
    
    GLKMatrix4 _modelViewMatrixBeforeUserInteractions;
    GLKMatrix4 _projectionMatrixBeforeUserInteractions;
}

@property MFMailComposeViewController *mailViewController;

@end


// 実装
@implementation MeshViewController

@synthesize mesh = _mesh;

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil
{
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(dismissView)];
    self.navigationItem.leftBarButtonItem = backButton;
    
    UIBarButtonItem *emailButton = [[UIBarButtonItem alloc] initWithTitle:@"Email"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(emailMesh)];
    //self.navigationItem.rightBarButtonItem = emailButton;
    
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        self.title = @"Structure Sensor Scanner";
    }
    
    return self;
}


// ジェスチャー認識をセットアップ
- (void)setupGestureRecognizer
{
    UIPinchGestureRecognizer *pinchScaleGesture = [[UIPinchGestureRecognizer alloc]
                                                   initWithTarget:self
                                                   action:@selector(pinchScaleGesture:)];
    [pinchScaleGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchScaleGesture];
    
    // We'll use one finger pan for rotation.
    UIPanGestureRecognizer *oneFingerPanGesture = [[UIPanGestureRecognizer alloc]
                                                   initWithTarget:self
                                                   action:@selector(oneFingerPanGesture:)];
    [oneFingerPanGesture setDelegate:self];
    [oneFingerPanGesture setMaximumNumberOfTouches:1];
    [self.view addGestureRecognizer:oneFingerPanGesture];
    
    // We'll use two fingers pan for in-plane translation.
    UIPanGestureRecognizer *twoFingersPanGesture = [[UIPanGestureRecognizer alloc]
                                                    initWithTarget:self
                                                    action:@selector(twoFingersPanGesture:)];
    [twoFingersPanGesture setDelegate:self];
    [twoFingersPanGesture setMaximumNumberOfTouches:2];
    [twoFingersPanGesture setMinimumNumberOfTouches:2];
    [self.view addGestureRecognizer:twoFingersPanGesture];
}


// 画面のインスタンスが初期化される時、一回だけ
// アプリを起動して、画面を読み込み終わった時
- (void)viewDidLoad
{
    NSLog(@"MeshViewControler::viewDidLoad ");
    [super viewDidLoad];

    
    gestureAreaHeight = 650;
    
    NSLog(@"viewDidLoad _recordMeshNum:%d", _recordMeshNum);

    
    playbackFlag = true;
    playbackFrameCounter = 0;
    _playbackRecordTimeSlider.minimumValue = 0;
    _playbackRecordTimeSlider.maximumValue = _recordMeshNum;
    _playbackRecordTimeSlider.value = 0;//_recordMeshNum/2;

    savedMeshNum = 0;
    
    self.meshViewerMessageLabel.alpha = 0.0;
    self.meshViewerMessageLabel.hidden = true;
    
    [self.meshViewerMessageLabel applyCustomStyleWithBackgroundColor:blackLabelColorWithLightAlpha];
    _saveRecordMeshNumLabel.text = [NSString stringWithFormat:@"%d", savedMeshNum ];
    _allRecordMeshNumLabel.text = [NSString stringWithFormat:@"%d", _recordMeshNum ];


    // オブジェクトの初期化
    _renderer = new MeshRenderer();
    _viewpointController = new ViewpointController(self.view.frame.size.width,
                                                   gestureAreaHeight);        // self.view.frame.size.height
    
    UIFont *font = [UIFont boldSystemFontOfSize:14.0f];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:font
                                                           forKey:NSFontAttributeName];
    
    [self.displayControl setTitleTextAttributes:attributes
                                    forState:UIControlStateNormal];
    
    [self setupGestureRecognizer];
    
    /*
    [NSTimer scheduledTimerWithTimeInterval:1.0 / 10
                                     target:self selector:@selector(updateFrame:) userInfo:nil repeats:YES];
     */
    
    
    // ogawa add
    // Do any additional setup after loading the view, typically from a nib.
    MyUdpConnection *udp2 = [[MyUdpConnection alloc]initWithDelegate:self portNum:5556];
    [udp2 bind];
    
    soundIdScan = UINT32_MAX;
    soundIdPlay = UINT32_MAX;
    soundIdScanStop = UINT32_MAX;
    soundIdSave = UINT32_MAX;
    soundIdBackToScan = UINT32_MAX;
    soundIdError = UINT32_MAX;
    soundIdIcant = UINT32_MAX;
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"scan" withExtension:@"aiff"], &(soundIdScan));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"play" withExtension:@"aiff"], &(soundIdPlay));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"scan_stop" withExtension:@"aiff"], &(soundIdScanStop));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"scan_reload" withExtension:@"aiff"], &(soundIdScanReload));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"save" withExtension:@"aiff"], &(soundIdSave));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"back_to_scan" withExtension:@"aiff"], &(soundIdBackToScan));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"error" withExtension:@"aiff"], &(soundIdError));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"cant" withExtension:@"aiff"], &(soundIdIcant));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"scan_state_scanning" withExtension:@"aiff"], &(soundIdStateScanning));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"scan_state_viewing" withExtension:@"aiff"], &(soundIdStateViewing));
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"scan_state_cube_setting" withExtension:@"aiff"], &(soundIdStateCubeSetting));
    

}


// ラベルのセット
- (void)setLabel:(UILabel*)label enabled:(BOOL)enabled {
    
    UIColor* whiteLightAlpha = [UIColor colorWithRed:1.0  green:1.0   blue:1.0 alpha:0.5];
    
    if(enabled)
        [label setTextColor:[UIColor whiteColor]];
        else
        [label setTextColor:whiteLightAlpha];
}


// 画面が表示される直前
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (_displayLink)
    {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    _viewpointController->reset();

    if (!self.colorEnabled)
        [self.displayControl removeSegmentAtIndex:2 animated:NO];
    
    self.displayControl.selectedSegmentIndex = 1;
    _renderer->setRenderingMode( MeshRenderer::RenderingModeLightedGray );
}


// メモリ警告を受け取った時の処理
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}


// OpenGLのセットアップ
- (void)setupGL:(EAGLContext *)context
{
    NSLog(@"MeshViewController setupGL start");
    [(EAGLView*)self.view setContext:context];
    [EAGLContext setCurrentContext:context];
    
    // GLの初期化
    NSLog(@"MeshViewController initializeGL start");
    _renderer->initializeGL();
    NSLog(@"MeshViewController initializeGL end");
    
    [(EAGLView*)self.view setFramebuffer];
    NSLog(@"MeshViewController setFramebuffer end");

    CGSize framebufferSize = [(EAGLView*)self.view getFramebufferSize];
    
    float imageAspectRatio = 1.0f;
    
    // The iPad's diplay conveniently has a 4:3 aspect ratio just like our video feed.
    // Some iOS devices need to render to only a portion of the screen so that we don't distort
    // our RGB image. Alternatively, you could enlarge the viewport (losing visual information),
    // but fill the whole screen.
    if ( std::abs(framebufferSize.width/framebufferSize.height - 640.0f/480.0f) > 1e-3)
        imageAspectRatio = 480.f/640.0f;
    
    _glViewport[0] = (framebufferSize.width - framebufferSize.width*imageAspectRatio)/2;
    _glViewport[1] = 0;
    _glViewport[2] = framebufferSize.width*imageAspectRatio;
    _glViewport[3] = framebufferSize.height;
}

// ビューを片付ける（前のスキャンモードに戻る）
- (void)dismissView
{
    if ([self.delegate respondsToSelector:@selector(meshViewWillDismiss)])
        [self.delegate meshViewWillDismiss];
    
    // Make sure we clear the data we don't need.
    _renderer->releaseGLBuffers();
    _renderer->releaseGLTextures();
    
    [_displayLink invalidate];
    _displayLink = nil;
    
    self.mesh = nil;
    
    [(EAGLView *)self.view setContext:nil];
    
    [self dismissViewControllerAnimated:YES completion:^{
        if([self.delegate respondsToSelector:@selector(meshViewDidDismiss)])
            [self.delegate meshViewDidDismiss];
    }];
    
    // 戻るときに配列を全削除　これしないと落ちる tanaka
    _recordMeshNum = 0;
    [mvcRecordMeshList removeAllObjects];
    [mvcScanFrameDateList removeAllObjects];    // 2016.6
}


#pragma mark - MeshViewer setup when loading the mesh

// カメラのプロジェクションマトリックスをセット
- (void)setCameraProjectionMatrix:(GLKMatrix4)projection
{
    _viewpointController->setCameraProjection(projection);
    _projectionMatrixBeforeUserInteractions = projection;
}

// meshCenterをリセット
- (void)resetMeshCenter:(GLKVector3)center
{
    _viewpointController->reset();
    _viewpointController->setMeshCenter(center);
    _modelViewMatrixBeforeUserInteractions = _viewpointController->currentGLModelViewMatrix();
}

// メッシュをセット
- (void)setMesh:(STMesh *)meshRef
{
    NSLog(@"MeshViewController setMesh start");
    _mesh = meshRef;
    
    if (meshRef)
    {
        NSLog(@"MeshViewController setMesh mesh exists");
        
        _renderer->uploadMesh(meshRef);
        //NSLog(@"MeshViewController setMesh mesh upload 2times");
        //_renderer->uploadMesh(meshRef);
    
        [self trySwitchToColorRenderingMode];

        self.needsDisplay = TRUE;
    }
}


// tanaka add
- (void)setRecordMeshList:(NSMutableArray *)listRef
{
    mvcRecordMeshList = listRef; // add by tanaka
    savedMeshNum = 0;

}

// add 2016.6
- (void)setScanFrameDateList:(NSMutableArray *)listRef
{
    mvcScanFrameDateList = listRef; // add by tanaka
    
}


// tanaka add
- (void)setScanStartDate:(NSDate *)date
{
    scanStartDate = date; // add by tanaka
}


#pragma mark - Email Mesh OBJ file
// メッシュObjのEメール送信

// メール編集コントローラー
- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [self.mailViewController dismissViewControllerAnimated:YES completion:nil];
}

// スクリーンショットの用意（メールに添付する）
- (void)prepareScreenShot:(NSString*)screenshotPath
{
    const int width = 320;
    const int height = 240;
    
    GLint currentFrameBuffer;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFrameBuffer);
    
    // Create temp texture, framebuffer, renderbuffer
    glViewport(0, 0, width, height);
    
    GLuint outputTexture;
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &outputTexture);
    glBindTexture(GL_TEXTURE_2D, outputTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    
    GLuint colorFrameBuffer, depthRenderBuffer;
    glGenFramebuffers(1, &colorFrameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, colorFrameBuffer);
    glGenRenderbuffers(1, &depthRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderBuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, outputTexture, 0);
    
    // Keep the current render mode
    MeshRenderer::RenderingMode previousRenderingMode = _renderer->getRenderingMode();
    
    STMesh* meshToRender = _mesh;
    
    // Screenshot rendering mode, always use colors if possible.
    // スクリーンショットレンダリングモードでは、可能ならば常にカラーを使う
    if ([meshToRender hasPerVertexUVTextureCoords] && [meshToRender meshYCbCrTexture])      // テクスチャの画像とUVを頂点ごとに持っている場合
    {
        _renderer->setRenderingMode( MeshRenderer::RenderingModeTextured );     // important?
    }
    else if ([meshToRender hasPerVertexColors]) // 頂点カラーしかない場合
    {
        _renderer->setRenderingMode( MeshRenderer::RenderingModePerVertexColor );
    }
    else // meshToRender can be nil if there is no available color mesh.    // カラーメッシュがない場合、グレーでレンダリング
    {
        _renderer->setRenderingMode( MeshRenderer::RenderingModeLightedGray );
    }
    
    // Render from the initial viewpoint for the screenshot.
    // スクリーンショットのために初期視点からレンダリングする
    _renderer->clear();
    _renderer->render(_projectionMatrixBeforeUserInteractions, _modelViewMatrixBeforeUserInteractions);
    
    // Back to current render mode
    // 元のレンダリングモードに戻る
    _renderer->setRenderingMode( previousRenderingMode );
    
    // RGBAピクセル構造体の一時的な定義
    struct RgbaPixel { uint8_t rgba[4]; };
    std::vector<RgbaPixel> screenShotRgbaBuffer (width*height);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, screenShotRgbaBuffer.data());
    
    // We need to flip the axis, because OpenGL reads out the buffer from the bottom.
    // 軸の反転が必要、OpenGLはバッファを下から読むので
    std::vector<RgbaPixel> rowBuffer (width);
    for (int h = 0; h < height/2; ++h)
    {
        RgbaPixel* screenShotDataTopRow    = screenShotRgbaBuffer.data() + h * width;
        RgbaPixel* screenShotDataBottomRow = screenShotRgbaBuffer.data() + (height - h - 1) * width;
        
        // Swap the top and bottom rows, using rowBuffer as a temporary placeholder.
        memcpy(rowBuffer.data(), screenShotDataTopRow, width * sizeof(RgbaPixel));
        memcpy(screenShotDataTopRow, screenShotDataBottomRow, width * sizeof (RgbaPixel));
        memcpy(screenShotDataBottomRow, rowBuffer.data(), width * sizeof (RgbaPixel));
    }
    
    // RGBAバッファをJPEGで保存
    saveJpegFromRGBABuffer([screenshotPath UTF8String], reinterpret_cast<uint8_t*>(screenShotRgbaBuffer.data()), width, height);
    
    // Back to the original frame buffer
    // オリジナルのフレームバッファに戻る
    glBindFramebuffer(GL_FRAMEBUFFER, currentFrameBuffer);
    glViewport(_glViewport[0], _glViewport[1], _glViewport[2], _glViewport[3]);
    
    // Free the data
    // データを解放する
    glDeleteTextures(1, &outputTexture);
    glDeleteFramebuffers(1, &colorFrameBuffer);
    glDeleteRenderbuffers(1, &depthRenderBuffer);
}

/*
 メールでOBJファイルを送る処理
 */
- (void)emailMesh
{
    // メールビューコントローラーの初期化
    self.mailViewController = [[MFMailComposeViewController alloc] init];

    // 初期化できなかった場合、エラー処理
    if (!self.mailViewController)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"The email could not be sent."
            message:@"Please make sure an email account is properly setup on this device."
            preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action) { }];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
        
        return;
    }
    
    self.mailViewController.mailComposeDelegate = self;
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        self.mailViewController.modalPresentationStyle = UIModalPresentationFormSheet;
    
    // Setup paths and filenames.
    // パスとファイル名の設定
    NSString* cacheDirectory = [NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES ) objectAtIndex:0];
    NSString* zipFilename = @"Model.zip";
    NSString* screenshotFilename = @"Preview.jpg";
    
    NSString *zipPath = [cacheDirectory stringByAppendingPathComponent:zipFilename];
    NSString *screenshotPath =[cacheDirectory stringByAppendingPathComponent:screenshotFilename];
    
    // Take a screenshot and save it to disk.
    // スクリーンショットを撮ってディスクに保存
    [self prepareScreenShot:screenshotPath];
    
    // メール件名の設定
    [self.mailViewController setSubject:@"3D Model"];
    
    // メッセージ本文の設定
    NSString *messageBody = @"This model was captured with the open source Scanner sample app in the Structure SDK.\n\nCheck it out!\n\nMore info about the Structure SDK: http://structure.io/developers";
    
    [self.mailViewController setMessageBody:messageBody isHTML:NO];
    
    // Request a zipped OBJ file, potentially with embedded MTL and texture.
    NSDictionary* options = @{ kSTMeshWriteOptionFileFormatKey: @(STMeshWriteOptionFileFormatObjFileZip) };
    
    // メッシュをファイルに書き出す
    // important
    NSError* error;
    STMesh* meshToSend = _mesh;
    BOOL success = [meshToSend writeToFile:zipPath options:options error:&error];

    // エラー処理
    if (!success)
    {
        self.mailViewController = nil;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"The email could not be sent."
            message: [NSString stringWithFormat:@"Exporting failed: %@.",[error localizedDescription]]
            preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action) { }];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
        
        return;
    }
    
    // Attach the Screenshot.
    // スクリーンショットの添付
    [self.mailViewController addAttachmentData:[NSData dataWithContentsOfFile:screenshotPath] mimeType:@"image/jpeg" fileName:screenshotFilename];
    
    // Attach the zipped mesh.
    // zip化されたメッシュの添付
    [self.mailViewController addAttachmentData:[NSData dataWithContentsOfFile:zipPath] mimeType:@"application/zip" fileName:zipFilename];

    // 完了処理
    [self presentViewController:self.mailViewController animated:YES completion:^(){}];
}


#pragma mark - Rendering



-(void)updateFrame:(NSTimer*)timer {
    NSLog(@"meshViewController::updateFrame");
    return;
    /*
    if (playbackFlag) {
        playbackFrameCounter++;

        //[self draw];
    }
    */
}


// レンダリング
// important
- (void)draw
{
    //NSLog(@"meshViewController::draw");
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error:nil];
    
    if (dictionary) {
        int GiB = 1024*1024*1024;
        float free = [[dictionary objectForKey: NSFileSystemFreeSize] floatValue]/GiB;
        float total = [[dictionary objectForKey: NSFileSystemSize] floatValue]/GiB;
        //NSLog(@"Space: %.1f", free);
        //NSLog(@"Total: %.1f", total);
        _diskSpaceLabel.text = [NSString stringWithFormat:@"%.1f", free];
        _maxDiskSpaceLabel.text = [NSString stringWithFormat:@"%.1f GB", total];
    }
    
    
    //int tIndex = 0;//(playbackFrameCounter % (_recordMeshNum));
    //STMesh* tMesh = [mvcRecordMeshList objectAtIndex:tIndex];       // tanaka add important!
    
    playbackFrame = (playbackFrameCounter % (_recordMeshNum-2)) + 2;
    STMesh* tMesh = [mvcRecordMeshList objectAtIndex:playbackFrame];       // tanaka add important!
    //STMesh *tMesh = [mvcRecordMeshList objectAtIndex:[mvcRecordMeshList count]-2];
    
    
    //[self setMesh:tMesh];
    
    
    _renderer->uploadMesh(tMesh); // ここを更新しないとアニメーションはしなくなります tanaka
    
    
    //if (_recordMeshNum >= 2) {
        //NSLog(@"mvcRecordMeshList [0]: %@", [mvcRecordMeshList objectAtIndex:0]);
        //NSLog(@"mvcRecordMeshList [1]: %@", [mvcRecordMeshList objectAtIndex:1]);
    //}
    
    [(EAGLView *)self.view setFramebuffer];
    
    glViewport(_glViewport[0], _glViewport[1], _glViewport[2], _glViewport[3]);
    
    bool viewpointChanged = _viewpointController->update();
    
    // If nothing changed, do not waste time and resources rendering.
    // 描画内容に変化がなくても描画し直すように変更
    //if (!_needsDisplay && !viewpointChanged)
    //    return;
    
    GLKMatrix4 currentModelView = _viewpointController->currentGLModelViewMatrix();
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();
    
    _renderer->clear();
    _renderer->render (currentProjection, currentModelView);

    _needsDisplay = FALSE;
    
    [(EAGLView *)self.view presentFramebuffer];
    
    if (playbackFlag) {     // tanaka add
        NSLog(@"now on play..");
        playbackFrameCounter++;
        
        if (_loopPlaySwitch.isOn) {
            playbackFrameCounter %= _recordMeshNum;
        } else {
            if (playbackFrameCounter >= _recordMeshNum) {
                playbackFrameCounter = 0;
                playbackFlag = false;
            }
        }
        
        //self.playbackRecordTimeValueLabel.text = [NSString stringWithFormat:@"%d",playbackFrameCounter];
    }
    _playbackRecordTimeSlider.value = playbackFrameCounter;
    _playbackRecordTimeValueLabel.text = [NSString stringWithFormat:@"%d", playbackFrameCounter];
    
    _debugTraceLabelMV.text = [NSString stringWithFormat:@"recordMeshNum: %d \n playbackFrameCounter: %d \n playFrame(playbackFrame): %d", _recordMeshNum, playbackFrameCounter, playbackFrame];
    
    _recordMeshNumLabel.text = [NSString stringWithFormat:@"%d", _recordMeshNum];
    
    
    _playbackRecordTimeSlider.maximumValue = _recordMeshNum;
    _saveRecordMeshNumLabel.text = [NSString stringWithFormat:@"%d", savedMeshNum ];
    _allRecordMeshNumLabel.text = [NSString stringWithFormat:@"%d", _recordMeshNum ];

}


#pragma mark - Touch & Gesture control
// タッチ＆ジェスチャー操作
// ピンチでスケール
- (void)pinchScaleGesture:(UIPinchGestureRecognizer *)gestureRecognizer
{
    // Forward to the ViewpointController.
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onPinchGestureBegan([gestureRecognizer scale]);
    else if ( [gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onPinchGestureChanged([gestureRecognizer scale]);
}

// １本指でパン操作
- (void)oneFingerPanGesture:(UIPanGestureRecognizer *)gestureRecognizer
{
    CGPoint touchPos = [gestureRecognizer locationInView:self.view];
    CGPoint touchVel = [gestureRecognizer velocityInView:self.view];
    GLKVector2 touchPosVec = GLKVector2Make(touchPos.x, touchPos.y);
    GLKVector2 touchVelVec = GLKVector2Make(touchVel.x, touchVel.y);
    
    if (touchPos.y < gestureAreaHeight) {
    
        if([gestureRecognizer state] == UIGestureRecognizerStateBegan)
            _viewpointController->onOneFingerPanBegan(touchPosVec);
        else if([gestureRecognizer state] == UIGestureRecognizerStateChanged)
            _viewpointController->onOneFingerPanChanged(touchPosVec);
        else if([gestureRecognizer state] == UIGestureRecognizerStateEnded)
            _viewpointController->onOneFingerPanEnded (touchVelVec);
    }
}

// ２本指でパン操作
- (void)twoFingersPanGesture:(UIPanGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer numberOfTouches] != 2)
        return;
    
    CGPoint touchPos = [gestureRecognizer locationInView:self.view];
    CGPoint touchVel = [gestureRecognizer velocityInView:self.view];
    GLKVector2 touchPosVec = GLKVector2Make(touchPos.x, touchPos.y);
    GLKVector2 touchVelVec = GLKVector2Make(touchVel.x, touchVel.y);

    if (touchPos.y < gestureAreaHeight) {

        if([gestureRecognizer state] == UIGestureRecognizerStateBegan)
            _viewpointController->onTwoFingersPanBegan(touchPosVec);
        else if([gestureRecognizer state] == UIGestureRecognizerStateChanged)
            _viewpointController->onTwoFingersPanChanged(touchPosVec);
        else if([gestureRecognizer state] == UIGestureRecognizerStateEnded)
            _viewpointController->onTwoFingersPanEnded (touchVelVec);
    }
}

- (void)touchesBegan:(NSSet *)touches
           withEvent:(UIEvent *)event
{
    _viewpointController->onTouchBegan();
}


#pragma mark - UI Control
// UI操作

// カラーレンダリングモードの切り替え
- (void)trySwitchToColorRenderingMode
{
    // Choose the best available color render mode, falling back to LightedGray
    // ベストな可能なカラーレンダリングモードを選択する、失敗したらLightedGrayに戻る
    
    // This method may be called when colorize operations complete, and will
    // switch the render mode to color, as long as the user has not changed
    // the selector.
    // このメソッドはおそらく色づけ操作が完了する時に呼ばれる、
    // そしてレンダリングモードをカラーに切り替えるだろう、セレクターを変更しない限りずっと

    if(self.displayControl.selectedSegmentIndex == 2)
    {
        if ( [_mesh hasPerVertexUVTextureCoords])
            _renderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
        else if ([_mesh hasPerVertexColors])
            _renderer->setRenderingMode(MeshRenderer::RenderingModePerVertexColor);
        else
            _renderer->setRenderingMode(MeshRenderer::RenderingModeLightedGray);
    }
}

// 表示コンロールの変更　（ボタン操作時の処理）
- (IBAction)displayControlChanged:(id)sender {
    
    switch (self.displayControl.selectedSegmentIndex) {
        case 0: // x-ray
        {
            _renderer->setRenderingMode(MeshRenderer::RenderingModeXRay);
        }
            break;
        case 1: // lighted-gray
        {
            _renderer->setRenderingMode(MeshRenderer::RenderingModeLightedGray);
        }
            break;
        case 2: // color
        {
            [self trySwitchToColorRenderingMode];

            // メッシュは色づけされているかどうか
            bool meshIsColorized = [_mesh hasPerVertexColors] ||
                                   [_mesh hasPerVertexUVTextureCoords];
            
            // 色づけされていなかったらする
            // ※colorizeMeshしない限り、ごくかんたんな色もつかない
            if ( !meshIsColorized ) [self colorizeMesh];
        }
            break;
        default:
            break;
    }
    
    self.needsDisplay = TRUE;
}

- (IBAction)playRecordButtonPressed:(UIButton *)sender {
    NSLog(@"playRecordButtonPressed");
    //_playbackRecordTimeSlider.value = 0;
    playbackFlag = true;
    
}

- (IBAction)stopRecordButtonPressed:(UIButton *)sender {
    NSLog(@"stopRecordButtonPressed");
    playbackFlag = false;
}

- (IBAction)backRecordButtonPressed:(UIButton *)sender {
    NSLog(@"backRecordButtonPressed");
    playbackFrameCounter = 0;
    self.playbackRecordTimeValueLabel.text = [NSString stringWithFormat:@"%d", 0];
}

- (IBAction)playbackRecordTimeSliderChange:(UISlider *)sender {
    NSLog(@"playbackRecordTimeSliderChange");
    playbackFrameCounter = (int)sender.value;
    self.playbackRecordTimeValueLabel.text = [NSString stringWithFormat:@"%d",playbackFrameCounter];

    
    //_playbackRecordTimeSlider.value = playbackFrameCounter;
    
}

// セーブ処理
- (IBAction)mvcSaveButtonPressed:(id)sender {
    [self doSaveAction];
}

- (IBAction)loopPlaySwitchPressed:(id)sender {
}

- (IBAction)loopPlaySwitch:(id)sender {
}


// メッシュを色づけする
// important
- (void)colorizeMesh
{
    // デリゲート
    [self.delegate
        meshViewDidRequestColorizing:_mesh
        previewCompletionHandler:^{
        }
        enhancedCompletionHandler:^{
            // Hide progress bar.
            [self hideMeshViewerMessage];
        }
     ];
}


// メッシュビューワーのメッセージを隠す
- (void)hideMeshViewerMessage
{
    [UIView animateWithDuration:0.5f animations:^{
        self.meshViewerMessageLabel.alpha = 0.0f;
    } completion:^(BOOL finished){
        [self.meshViewerMessageLabel setHidden:YES];
    }];
}


// メッシュビューワーのメッセージを表示
- (void)showMeshViewerMessage:(NSString *)msg
{
    [self.meshViewerMessageLabel setText:msg];
    
    if (self.meshViewerMessageLabel.hidden == YES)
    {
        [self.meshViewerMessageLabel setHidden:NO];
        
        self.meshViewerMessageLabel.alpha = 0.0f;
        [UIView animateWithDuration:0.5f animations:^{
            self.meshViewerMessageLabel.alpha = 1.0f;
        }];
    }
}


// ogawa add
- (void)receiveUdpData:(NSData *)data {
    
    NSString *receivedData =  [[NSString alloc] initWithData:data
                                                    encoding:NSUTF8StringEncoding];
    // receivedDataがlength:12のデータになっているので、Length:4に変換する
    char *recvChars = (char *) [receivedData UTF8String];
    receivedData = [NSString stringWithCString: recvChars encoding:NSUTF8StringEncoding];

    NSLog(@"meshViewController::receiveUdpData: %@", receivedData);

    
    //NSString *mes = [NSString stringWithFormat:@"2Received UDP: %@, A B2", receivedData];
    NSString *mes = [NSString stringWithFormat:@"2Received UDP: %@, ", receivedData];
    
    //NSLog(@"rData length: %lu", (unsigned long)[receivedData length]);
    
    _receivedMessageUDPLabel.text = mes;
    
    if ([receivedData compare:@"back_to_scan"] == NSOrderedSame){

        AudioServicesPlaySystemSound(soundIdBackToScan);
        [self dismissView];

    } else  if ([receivedData compare:@"save"] == NSOrderedSame){

        [self doSaveAction];
        AudioServicesPlaySystemSound(soundIdSave);
        
    } else  if ([receivedData compare:@"state"] == NSOrderedSame){

        AudioServicesPlaySystemSound(soundIdStateViewing);

    } else  if ([receivedData compare:@"play"] == NSOrderedSame){
        
        playbackFlag = true;
        AudioServicesPlaySystemSound(soundIdPlay);
    
    } else {
        
        AudioServicesPlaySystemSound(soundIdStateViewing);
    }
    
}


-(void) doSaveAction {
    
    //_recordMeshNum;
    
    //mvcRecordMeshList;
    
    
    int newSaveNum = 0;
    
    NSLog(@"mvcSaveButtonPressed saveWithData start2");
    
    // Documentsフォルダを得る
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *DocumentsDirPath = [paths objectAtIndex:0];
    
    NSLog(@"Documents folder path: %s", [DocumentsDirPath UTF8String]);
    
    NSString *artdktPath = [NSString stringWithFormat:@"%s/%s", [DocumentsDirPath UTF8String], [@"artdkt_structure3d" UTF8String]];
    
    NSLog(@"artDkt folder path: %s", [artdktPath UTF8String]);
    
    
    // 新しい保存のための番号を作るため、現在一番新しいセーブの番号を取得する
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSLog(@"filePathScan: %s", [artdktPath UTF8String] );
    for (NSString *content in [fileManager contentsOfDirectoryAtPath:artdktPath error:nil ]) {
        const char *chars = [content UTF8String];
        
        NSString *str = [NSString stringWithCString: chars encoding:NSUTF8StringEncoding];
        
        NSLog(@"filePathList: %s", chars);
        
        //NSSTring型をInt型に
        int oldSaveId = [ str intValue ];
        if (oldSaveId >= newSaveNum) {
            newSaveNum = oldSaveId;
        }
    }
    newSaveNum += 1;
    
    
    
    
    NSString *modelDirPath = [NSString stringWithFormat:@"%s/%d", [artdktPath UTF8String], newSaveNum];
    
    NSLog(@"make folder  proccess!");
    // フォルダを作る
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        BOOL created = [fileManager createDirectoryAtPath:modelDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
        
        if (!error){
            NSLog(@"error: %@", error);
        } else {
            NSLog(@"folder make success!");
        }
        
    }
    
    _saveRecordMeshNumLabel.text = @"0";
    
    
    NSString *scanTimeRecordList = @"";
    
    for(int i=0; i<[mvcRecordMeshList count]; i++) {
        STMesh *mesh = mvcRecordMeshList[i];
        NSError* error;
        NSString *tFilePath = [NSString stringWithFormat:@"%s/mesh_%d.obj", [modelDirPath UTF8String], i ];
        NSLog(@"write filePath: %s", [tFilePath UTF8String]);
        
        [mesh writeToFile:tFilePath
                  options:@{kSTMeshWriteOptionFileFormatKey: @(STMeshWriteOptionFileFormatObjFile)} //STMeshWriteOptionFileFormatObjFileZip}       // STMeshWriteOptionFileFormatObjFileZip
                    error:&error];
        savedMeshNum++;
        if (!error){
            NSLog(@"error: %@", error);
        }else{
            NSLog(@"save: %d/%d SUCCESS! ", savedMeshNum, _recordMeshNum);
        }
        _saveRecordMeshNumLabel.text = [NSString stringWithFormat:@"%d", savedMeshNum ];
        
        
        /* comment out bug 2016.6
        if (i == 0) {
            scanStartDate = [NSDate date];
        }  */
        
        
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"ja_JP"]]; // Localeの指定
        [df setDateFormat:@"yyyy/MM/dd HH:mm:ss.SSS"];
        
        /*
         NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
         [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
         //タイムゾーンの指定
         [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
         */
        
        //NSDate *nsd =  [NSDate date]; // comment out critical bug 2016.6 
        NSDate *nsd = mvcScanFrameDateList[i];
        
        NSString *strNow = [df stringFromDate:nsd];
        
        // ミリセカンド(ms)を取得
        long timeFromScanStart =  (long)([nsd timeIntervalSinceDate:scanStartDate] * 1000);
        
        
        NSString *lineStr = [NSString stringWithFormat:@"%i,%li,%@\n", i, timeFromScanStart, strNow];
        
        
        
        // 日付(NSDate) => 文字列(NSString)に変換
        //NSString* strNow = [NSString stringWithFormat:@"%@.%03d", [df stringFromDate: now], intMillSec];
        
        
        scanTimeRecordList = [scanTimeRecordList stringByAppendingString:lineStr ];//@"";
        
    }
    
    NSError* tError;
    NSString *timeRecordPath = [NSString stringWithFormat:@"%s/scanTimeRecord.csv", [modelDirPath UTF8String]];
    [scanTimeRecordList writeToFile:timeRecordPath
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&tError];
    
    //NSString *tFilePath = @"Documents/artdkt_structure3d/1/";
    NSLog(@"after fileScan filePath: %s", [modelDirPath UTF8String]);
    //filePath = [[NSBundle mainBundle] bundlePath];
    //filePath = @"Documents/artdkt_structure3d";
    
    
    // ディレクトリのファイル一覧を取得
    NSLog(@"filePathScan: %s", [DocumentsDirPath UTF8String] );
    for (NSString *content in [fileManager contentsOfDirectoryAtPath:DocumentsDirPath error:nil ]) {
        const char *chars = [content UTF8String];
        NSLog(@"filePathList: %s", chars);
    }
    
    // 1撮影分モデルのファイル一覧を取得
    NSLog(@"filePathScan: %s", [modelDirPath UTF8String] );
    for (NSString *content in [fileManager contentsOfDirectoryAtPath:modelDirPath error:nil ]) {
        const char *chars = [content UTF8String];
        NSLog(@"filePathList: %s", chars);
    }
    
    
    /*
     for(int i=0; i<[mvcRecordMeshList count]; i++) {
     //NSLog( [NSString stringWithFormat:@"%d: %@", i, mvcRecordMeshList[i]] );
     STMesh *mesh = mvcRecordMeshList[i];
     NSLog( [NSString stringWithFormat:@"%d: meshFaces %d", i, [mesh numberOfMeshFaces:i] ] );
     }
     */
    
    
    
    
    
    /*
     [mvcRecordMeshList removeObjectsInRange:NSMakeRange(0, 10)];
     [mvcRecordMeshList removeLastObject];
     [mvcRecordMeshList removeLastObject];
     */
    /*
     BOOL successful = [NSKeyedArchiver archiveRootObject:mvcRecordMeshList toFile:@"test.dat"];
     if (successful) {
     NSLog(@"%@", @"データのシリアライズ・保存に★成功★しました。");
     } else {
     NSLog(@"%@", @"データのシリアライズ・保存に【失敗】しました。");
     }
     */
    
    /*
     //[STMesh saveWithData:mvcRecordMeshList forKey:@"3dscan_01"];
     STMesh *m = mvcRecordMeshList[0];
     [m saveWithData:mvcRecordMeshList forKey:@"3dscan_01"];
     */
    
    /*
     NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
     NSString *filePath = [directory stringByAppendingPathComponent:@"data.dat"];
     
     NSArray *array = @[@"山田太郎", @"東京都中央区"];
     BOOL successful = [NSKeyedArchiver archiveRootObject:mvcRecordMeshList toFile:filePath];
     if (successful) {
     NSLog(@"%@", @"データのシリアライズ・保存に★成功★しました。");
     } else {
     NSLog(@"%@", @"データのシリアライズ・保存に【失敗】しました。");
     }
     
     //[NSKeyedArchiver archiveRootObject:mvcRecordMeshList toFile:""];
     */
    /*
     [NSObject saveWithData:mvcRecordMeshList forKey:@"3dscan_01"];
     */
    
    
    NSLog(@"saveWithData end2");
    

}

@end

/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/


#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>

#import <Structure/StructureSLAM.h>

#include <algorithm>


// アプリの状態を保持する構造体
struct AppStatus
{
    // ステータス通知テキストメッセージ
    NSString* const pleaseConnectSensorMessage = @"Please connect Structure Sensor.";
    NSString* const pleaseChargeSensorMessage = @"Please charge Structure Sensor.";
    NSString* const needColorCameraAccessMessage = @"This app requires camera access to capture color.\nAllow access by going to Settings → Privacy → Camera.";
    
    // センサの状態ID　センサ準備oK、接続が必要、充電が必要
    enum SensorStatus
    {
        SensorStatusOk,
        SensorStatusNeedsUserToConnect,
        SensorStatusNeedsUserToCharge,
    };
    
    // Structure Sensor status.
    SensorStatus sensorStatus = SensorStatusOk;
    
    // Whether iOS camera access was granted by the user.
    bool colorCameraIsAuthorized = true;
    
    // Whether there is currently a message to show.
    bool needsDisplayOfStatusMessage = false;
    
    // Flag to disable entirely status message display.
    bool statusMessageDisabled = false;
};


// 宣言 ----------------------------------------------------------------------------
@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    
    STSensorController *_sensorController;
    
    AVCaptureSession *_avCaptureSession;
    AVCaptureDevice *_videoDevice;

    UIImageView *_depthImageView;
    UIImageView *_normalsImageView;
    UIImageView *_colorImageView;
    
    uint16_t *_linearizeBuffer;
    uint8_t *_coloredDepthBuffer;
    uint8_t *_normalsBuffer;

    STNormalEstimator *_normalsEstimator;
    
    UILabel* _statusLabel;
    
    AppStatus _appStatus;
    
}

- (BOOL)connectAndStartStreaming;
- (void)renderDepthFrame:(STDepthFrame*)depthFrame;
- (void)renderNormalsFrame:(STDepthFrame*)normalsFrame;
- (void)renderColorFrame:(CMSampleBufferRef)sampleBuffer;
- (void)setupColorCamera;
- (void)startColorCamera;
- (void)stopColorCamera;

@end


// 実装 -------------------------------------------------------------------------
@implementation ViewController


// 画面のインスタンスが初期化される時、一回だけ
- (void)viewDidLoad
{
    // アプリを起動して、画面を読み込み終わった時
    
    [super viewDidLoad];
    
    _sensorController = [STSensorController sharedController];
    _sensorController.delegate = self;

    // Create three image views where we will render our frames
    // ３つのリアルタイム画像の表示位置決め
    
    CGRect depthFrame = self.view.frame;    // 今のビューの位置とサイズなどの情報をコピー
    depthFrame.size.height /= 1;            // 高さは半分に
    depthFrame.origin.y = 0;        // y座標は真ん中から
    depthFrame.origin.x = 1;
    depthFrame.origin.x = -self.view.frame.size.width * 0;   // x座標は　-画面横サイズの4/1　左下
    /*
    depthFrame.size.height /= 2;            // 高さは半分に
    depthFrame.origin.y = self.view.frame.size.height/2;        // y座標は真ん中から
    depthFrame.origin.x = 1;
    depthFrame.origin.x = -self.view.frame.size.width * 0.25;   // x座標は　-画面横サイズの4/1　左下
    */
    
    CGRect normalsFrame = self.view.frame;
    normalsFrame.size.height /= 8;
    normalsFrame.origin.y = self.view.frame.size.height/2;
    normalsFrame.origin.x = 1;
    normalsFrame.origin.x = self.view.frame.size.width * 0.25;  // 右下
    /*
    normalsFrame.size.height /= 2;
    normalsFrame.origin.y = self.view.frame.size.height/2;
    normalsFrame.origin.x = 1;
    normalsFrame.origin.x = self.view.frame.size.width * 0.25;  // 右下
    */
    
    CGRect colorFrame = self.view.frame;                        // 左上
    colorFrame.size.height /= 3;
    colorFrame.origin.x = self.view.frame.size.width * 0.25;  // 右下
    
    _linearizeBuffer = NULL;
    _coloredDepthBuffer = NULL;
    _normalsBuffer = NULL;

    // メインビューのサブビューに３つの（アスペクト）画像を登録
    _depthImageView = [[UIImageView alloc] initWithFrame:depthFrame];       // UIImageViewクラスは、画面上での画像表示を管理するクラスです。画面上に画像を表示するときに使用します。
    _depthImageView.contentMode = UIViewContentModeScaleAspectFit;      // UIImageView に UIImage を貼付けると、どんな縦横比の画像だろうと問答無用でUIImageView のサイズに変換されて貼付けられてしまう。画像の縦横比を維持したまま UIImageView に貼付けることが可能となる。
    [self.view addSubview:_depthImageView];         //サブビューとして追加
    
    _normalsImageView = [[UIImageView alloc] initWithFrame:normalsFrame];
    _normalsImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:_normalsImageView];
    
    _colorImageView = [[UIImageView alloc] initWithFrame:colorFrame];
    _colorImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:_colorImageView];

    
    // 通常のiPadカメラ（色画像情報）のセットアップを開始する
    [self setupColorCamera];
}

// 終了時処理
- (void)dealloc
{
    
    if (_linearizeBuffer)
        free(_linearizeBuffer);
    
    if (_coloredDepthBuffer)
        free(_coloredDepthBuffer);
    
    if (_normalsBuffer)
        free(_normalsBuffer);
}

// ビューが表示される時、毎回 	（画面が表示された後に呼び出される）
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    static BOOL fromLaunch = true;
    if(fromLaunch)
    {

        //
        // Create a UILabel in the center of our view to display status messages
        // ステータスのテキストメッセージ表示
    
        // We do this here instead of in viewDidLoad so that we get the correctly size/rotation view bounds
        // 画面が縦横回転した時とかのために毎回ここで設定
        if (!_statusLabel) {
            // ステータス表示ラベルの設定
            _statusLabel = [[UILabel alloc] initWithFrame:self.view.bounds];        // 領域
            _statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];  // 背景色 半透明の黒
            _statusLabel.textAlignment = NSTextAlignmentCenter;     // 中央寄せ
            _statusLabel.font = [UIFont systemFontOfSize:35.0];
            _statusLabel.numberOfLines = 2;
            _statusLabel.textColor = [UIColor whiteColor];

            [self updateAppStatusMessage];
            
            [self.view addSubview: _statusLabel];       // サブビューとして追加
        }

        [self connectAndStartStreaming];        // 3Dセンサに接続して開始
        fromLaunch = false;

        // From now on, make sure we get notified when the app becomes active to restore the sensor state if necessary.
        // これから先も、アプリがアクティブになったときにセンサを復旧するために通知を取得できるようにする
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidBecomeActive)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
}


// アプリがアクティブになる時
- (void)appDidBecomeActive
{
    [self connectAndStartStreaming];
}

// メモリ警告があったとき
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


// Structureセンサに接続してストリーミングを開始
- (BOOL)connectAndStartStreaming
{
    // センサの接続を初期化
    STSensorControllerInitStatus result = [_sensorController initializeSensorConnection];
    
    BOOL didSucceed = (result == STSensorControllerInitStatusSuccess || result == STSensorControllerInitStatusAlreadyInitialized);
    
    // 接続が成功したかどうか
    if (didSucceed)
    {
        // There's no status about the sensor that we need to display anymore
        _appStatus.sensorStatus = AppStatus::SensorStatusOk;
        [self updateAppStatusMessage];
        
        // Start the color camera, setup if needed
        // カラー画像カメラの開始（もし必要なら）
        [self startColorCamera];
        
        // Set sensor stream quality
        // デプスセンサの解像度を設定
        STStreamConfig streamConfig = STStreamConfigDepth320x240;

        // Request that we receive depth frames with synchronized color pairs
        // After this call, we will start to receive frames through the delegate methods
        // カラー画像とデプス画像の同期
        // これを呼んだ後から、デリゲートメソッドからフレームを受け取り始めます
        NSError* error = nil;
        BOOL optionsAreValid = [_sensorController startStreamingWithOptions:@{kSTStreamConfigKey : @(streamConfig),
                                                                              kSTFrameSyncConfigKey : @(STFrameSyncDepthAndRgb),
                                                                              kSTHoleFilterConfigKey: @TRUE} // looks better without holes
                                                                      error:&error];
        if (!optionsAreValid)
        {
            NSLog(@"Error during streaming start: %s", [[error localizedDescription] UTF8String]);
            return false;
        }
        
        // Allocate the depth -> surface normals converter class
        // 深度データから法泉面へのコンバータクラスの初期化
        _normalsEstimator = [[STNormalEstimator alloc] init];
    }
    else
    {
        // 接続に失敗した場合
        //
        if (result == STSensorControllerInitStatusSensorNotFound)
            NSLog(@"[Debug] No Structure Sensor found!");
        else if (result == STSensorControllerInitStatusOpenFailed)
            NSLog(@"[Error] Structure Sensor open failed.");
        else if (result == STSensorControllerInitStatusSensorIsWakingUp)
            NSLog(@"[Debug] Structure Sensor is waking from low power.");
        else if (result != STSensorControllerInitStatusSuccess)
            NSLog(@"[Debug] Structure Sensor failed to init with status %d.", (int)result);
        
        _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
        [self updateAppStatusMessage];
    }
    
    return didSucceed;
    
}

// アプリのステータスメッセージ表示するとき
- (void)showAppStatusMessage:(NSString *)msg
{
    _appStatus.needsDisplayOfStatusMessage = true;
    [self.view.layer removeAllAnimations];
    
    [_statusLabel setText:msg];
    [_statusLabel setHidden:NO];
    
    // Progressively show the message label.        メッセージのアニメ表示
    [self.view setUserInteractionEnabled:false];
    [UIView animateWithDuration:0.5f animations:^{
        _statusLabel.alpha = 1.0f;
    }completion:nil];
}

// アプリのステータスメッセージ表示offするとき
- (void)hideAppStatusMessage
{
    
    _appStatus.needsDisplayOfStatusMessage = false;
    [self.view.layer removeAllAnimations];
    
    // アニメーションさせながら消す
    [UIView animateWithDuration:0.5f
                     animations:^{
                         _statusLabel.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         // If nobody called showAppStatusMessage before the end of the animation, do not hide it.
                         if (!_appStatus.needsDisplayOfStatusMessage)
                         {
                             [_statusLabel setHidden:YES];
                             [self.view setUserInteractionEnabled:true];
                         }
                     }];
}

// アプリのステータスメッセージ更新
-(void)updateAppStatusMessage
{
    // Skip everything if we should not show app status messages (e.g. in viewing state).
    if (_appStatus.statusMessageDisabled)
    {
        [self hideAppStatusMessage];
        return;
    }
    
    // First show sensor issues, if any.
    switch (_appStatus.sensorStatus)
    {
        case AppStatus::SensorStatusOk:
        {
            break;
        }
            
        case AppStatus::SensorStatusNeedsUserToConnect:
        {
            [self showAppStatusMessage:_appStatus.pleaseConnectSensorMessage];
            return;
        }
            
        case AppStatus::SensorStatusNeedsUserToCharge:
        {
            [self showAppStatusMessage:_appStatus.pleaseChargeSensorMessage];
            return;
        }
    }
    
    // Then show color camera permission issues, if any.
    if (!_appStatus.colorCameraIsAuthorized)
    {
        [self showAppStatusMessage:_appStatus.needColorCameraAccessMessage];
        return;
    }
    
    // If we reach this point, no status to show.
    [self hideAppStatusMessage];
}


// センサが接続されているか、充電されているか
-(bool) isConnectedAndCharged
{
    return [_sensorController isConnected] && ![_sensorController isLowPower];
}


#pragma mark -
#pragma mark Structure SDK Delegate Methods

// センサが切断されたか
- (void)sensorDidDisconnect
{
    NSLog(@"Structure Sensor disconnected!");

    _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
    [self updateAppStatusMessage];
    
    // Stop the color camera when there isn't a connected Structure Sensor
    [self stopColorCamera];
}

// センサが接続されたか
- (void)sensorDidConnect
{
    NSLog(@"Structure Sensor connected!");
    [self connectAndStartStreaming];
}

- (void)sensorDidLeaveLowPowerMode
{
    _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
    [self updateAppStatusMessage];
}


- (void)sensorBatteryNeedsCharging
{
    // Notify the user that the sensor needs to be charged.
    _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToCharge;
    [self updateAppStatusMessage];
}

- (void)sensorDidStopStreaming:(STSensorControllerDidStopStreamingReason)reason
{
    //If needed, change any UI elements to account for the stopped stream

    // Stop the color camera when we're not streaming from the Structure Sensor
    [self stopColorCamera];

}

// センサがデプスフレームを出力したとき
- (void)sensorDidOutputDepthFrame:(STDepthFrame *)depthFrame
{
    // デプスフレームの描画と法線の描画
    [self renderDepthFrame:depthFrame];
    [self renderNormalsFrame:depthFrame];
}

// This synchronized API will only be called when two frames match. Typically, timestamps are within 1ms of each other.
// Two important things have to happen for this method to be called:
// Tell the SDK we want framesync with options @{kSTFrameSyncConfigKey : @(STFrameSyncDepthAndRgb)} in [STSensorController startStreamingWithOptions:error:]
// Give the SDK color frames as they come in:     [_ocSensorController frameSyncNewColorBuffer:sampleBuffer];
// ------------------------------------------------------------------------
// センサが同期された画像フレームとデプスフレームを出力したとき
- (void)sensorDidOutputSynchronizedDepthFrame:(STDepthFrame *)depthFrame
                                andColorFrame:(STColorFrame *)colorFrame
{
    // デプスフレームの描画と法線,カラーフレームの描画
    [self renderDepthFrame:depthFrame];
    [self renderNormalsFrame:depthFrame];
    [self renderColorFrame:colorFrame.sampleBuffer];
}


#pragma mark -
#pragma mark Rendering

const uint16_t maxShiftValue = 2048;

// 一般化した直線的なバッファ？
- (void)populateLinearizeBuffer
{
    _linearizeBuffer = (uint16_t*)malloc((maxShiftValue + 1) * sizeof(uint16_t));
    
    for (int i=0; i <= maxShiftValue; i++)
    {
        float v = i/ (float)maxShiftValue;
        v = powf(v, 3)* 6;
        _linearizeBuffer[i] = v*6*256;
    }
}

// デプスデータをRGBA情報に変換
// やっていることはconvertDepthFrameToRgbaと同じ（教育目的でここに書いているだけで、本当は左記の関数を呼べばいい）
// This function is equivalent to calling [STDepthAsRgba convertDepthFrameToRgba] with the
// STDepthToRgbaStrategyRedToBlueGradient strategy. Not using the SDK here for didactic purposes.
- (void)convertShiftToRGBA:(const uint16_t*)shiftValues depthValuesCount:(size_t)depthValuesCount
{
    // デプスフレームの縦x横回分繰り返す　解像度はカメラ画像と異なる場合あり？
    for (size_t i = 0; i < depthValuesCount; i++)
    {
        // We should not get higher values than maxShiftValue, but let's stay on the safe side.
        // センサから撮ってきた値がmaxShiftValue以上の場合にはmaxShiftValueを超えない値に制限する boundedShiftに入れる
        uint16_t boundedShift = std::min (shiftValues[i], maxShiftValue);
        
        // Use a lookup table to make the non-linear input values vary more linearly with metric depth
        // ルックアップテーブルを使って、センサから取ってきた非線形な入力値を、メートル法の深度でより線形な数値に変えて取得
        int linearizedDepth = _linearizeBuffer[boundedShift];
        
        // Use the upper byte of the linearized shift value to choose a base color
        // Base colors range from: (closest) White, Red, Orange, Yellow, Green, Cyan, Blue, Black (farthest)
        // 近いのは白、赤、オレンジ、、ブルー、黒（最も遠い）
        int lowerByte = (linearizedDepth & 0xff);
        
        // Use the lower byte to scale between the base colors
        int upperByte = (linearizedDepth >> 8);
        
        _coloredDepthBuffer[4*i+0] = std::max (255 - ((linearizedDepth >> 5)), 0);
        _coloredDepthBuffer[4*i+1] = std::max (255 - ((linearizedDepth >> 5)), 0);
        _coloredDepthBuffer[4*i+2] = std::max (255 - ((linearizedDepth >> 5)), 0);
        _coloredDepthBuffer[4*i+3] = 128;
        /*
        // HSV的な色相変換処理
        switch (upperByte)
        {
            case 0:
                _coloredDepthBuffer[4*i+0] = 255;
                _coloredDepthBuffer[4*i+1] = 255-lowerByte;
                _coloredDepthBuffer[4*i+2] = 255-lowerByte;
                _coloredDepthBuffer[4*i+3] = 255;
                break;
            case 1:
                _coloredDepthBuffer[4*i+0] = 255;
                _coloredDepthBuffer[4*i+1] = lowerByte;
                _coloredDepthBuffer[4*i+2] = 0;
                break;
            case 2:
                _coloredDepthBuffer[4*i+0] = 255-lowerByte;
                _coloredDepthBuffer[4*i+1] = 255;
                _coloredDepthBuffer[4*i+2] = 0;
                break;
            case 3:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 255;
                _coloredDepthBuffer[4*i+2] = lowerByte;
                break;
            case 4:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 255-lowerByte;
                _coloredDepthBuffer[4*i+2] = 255;
                break;
            case 5:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 0;
                _coloredDepthBuffer[4*i+2] = 255-lowerByte;
                break;
            default:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 0;
                _coloredDepthBuffer[4*i+2] = 0;
                break;
        }
         */
    }
}

// デプスフレームをレンダリング　（深度データそのままだとカラフルな画像にはならないので）
- (void)renderDepthFrame:(STDepthFrame *)depthFrame
{
    size_t cols = depthFrame.width;         // 列
    size_t rows = depthFrame.height;        // 行
    
    if (_linearizeBuffer == NULL || _normalsBuffer == NULL)
    {
        [self populateLinearizeBuffer];
        _coloredDepthBuffer = (uint8_t*)malloc(cols * rows * 4);       // 縦x横x4バイトのメモリ空間を動的に確保
    }
    
    // Conversion of 16-bit non-linear shift depth values to 32-bit RGBA
    //
    // Adapted from: https://github.com/OpenKinect/libfreenect/blob/master/examples/glview.c
    //
    // １６ビット非線形シフト深度値の32bit RGBAへの変換
    [self convertShiftToRGBA:depthFrame.shiftData depthValuesCount:cols * rows];        // 深度値をRGBAの色相に変換 結果は、_coloredDepthBufferに格納される
    
    //汎用またはデバイス依存の色空間の生成
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();     // カラースペースを管理する構造体
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaNoneSkipLast;       // アルファ値がなく、RGBー（つまりーBGR）
    bitmapInfo |= kCGBitmapByteOrder32Big;                      // バイトオーダーが32bit Big endian?
    
    /*
    ポインタpixelから始まるメモリのCFDataRefを作る
    CFDataからCGDataProviderRefを作る
    CGDataProviderRefからCGImageRefを作る
    CGImageからUIImageを作る
     CFなんとか、CGなんとかで始まる関数や型はC言語ベースで、自動的にリリースされないのでご注意ください。
     http://extendevernote.blogspot.jp/2012/02/iphone-2.html
     */
    NSData *data = [NSData dataWithBytes:_coloredDepthBuffer length:cols * rows * 4];  // 色付けした深度データを、Obj-Cで扱いやすい型の一時限数値配列に変換？
    // NSオブジェクトとCFオブジェクトとの構造は同じであるためオーバーヘッド無しにキャストできる。これをToll-Free Bridge(交通量無料の橋)と呼ぶ。
    // http://fernweh.jp/b/arc-__bridge/
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data); //toll-free ARC bridging
    
    
    CGImageRef imageRef = CGImageCreate(cols,                       //width
                                       rows,                        //height
                                       8,                           //bits per component
                                       8 * 4,                       //bits per pixel
                                       cols * 4,                    //bytes per row
                                       colorSpace,                  //Quartz color space
                                       bitmapInfo,                  //Bitmap info (alpha channel?, order, etc)
                                       provider,                    //Source of data for bitmap
                                       NULL,                        //decode
                                       false,                       //pixel interpolation
                                       kCGRenderingIntentDefault);  //rendering intent
    
    // Assign CGImage to UIImage
    _depthImageView.image = [UIImage imageWithCGImage:imageRef];
    
    CGImageRelease(imageRef);               // 後処理としてつくった画像データを解放
    CGDataProviderRelease(provider);        // 後処理としてつくった画像データを解放
    CGColorSpaceRelease(colorSpace);        // カラースペースを解放
    
}

// 法線フレームをレンダリング
- (void) renderNormalsFrame: (STDepthFrame*) depthFrame
{
    // Estimate surface normal direction from depth float values
    // 深度データの不動小数点値から、面の法線方向を概算する
    STNormalFrame *normalsFrame = [_normalsEstimator calculateNormalsWithDepthFrame:depthFrame];
    
    size_t cols = normalsFrame.width;
    size_t rows = normalsFrame.height;
    
    // Convert normal unit vectors (ranging from -1 to 1) to RGB (ranging from 0 to 255)
    // Z can be slightly positive in some cases too!
    if (_normalsBuffer == NULL)
    {
        _normalsBuffer = (uint8_t*)malloc(cols * rows * 4);
    }
    for (size_t i = 0; i < cols * rows; i++)
    {
        _normalsBuffer[4*i+0] = (uint8_t)( ( ( normalsFrame.normals[i].x / 2 ) + 0.5 ) * 255);
        _normalsBuffer[4*i+1] = (uint8_t)( ( ( normalsFrame.normals[i].y / 2 ) + 0.5 ) * 255);
        _normalsBuffer[4*i+2] = (uint8_t)( ( ( normalsFrame.normals[i].z / 2 ) + 0.5 ) * 255);
    }
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;
    bitmapInfo |= kCGBitmapByteOrder32Little;
    
    NSData *data = [NSData dataWithBytes:_normalsBuffer length:cols * rows * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(cols,
                                        rows,
                                        8,
                                        8 * 4,
                                        cols * 4,
                                        colorSpace,
                                        bitmapInfo,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    
    _normalsImageView.image = [[UIImage alloc] initWithCGImage:imageRef];
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);

}

// -----------------------------------------------------------------
// レンダリング　カラー画像フレームを　（毎回呼ばれる）
- (void)renderColorFrame:(CMSampleBufferRef)sampleBuffer
{

    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    size_t cols = CVPixelBufferGetWidth(pixelBuffer);
    size_t rows = CVPixelBufferGetHeight(pixelBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    unsigned char *ptr = (unsigned char *) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    
    NSData *data = [[NSData alloc] initWithBytes:ptr length:rows*cols*4];
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;
    bitmapInfo |= kCGBitmapByteOrder32Little;
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(cols,
                                        rows,
                                        8,
                                        8 * 4,
                                        cols*4,
                                        colorSpace,
                                        bitmapInfo,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    
    _colorImageView.image = [[UIImage alloc] initWithCGImage:imageRef];     // ビューに画像をセット
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
}



#pragma mark -  AVFoundation
// カメラ使用の認証が得られていないときは認証を求める
- (bool)queryCameraAuthorizationStatusAndNotifyUserIfNotGranted
{
    const NSUInteger numCameras = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
    
    if (0 == numCameras)
        return false; // This can happen even on devices that include a camera, when camera access is restricted globally.

    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (authStatus != AVAuthorizationStatusAuthorized)
    {
        NSLog(@"Not authorized to use the camera!");
        
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL granted)
         {
             // This block fires on a separate thread, so we need to ensure any actions here
             // are sent to the right place.
             
             // If the request is granted, let's try again to start an AVFoundation session. Otherwise, alert
             // the user that things won't go well.
             if (granted)
             {
                 
                 dispatch_async(dispatch_get_main_queue(), ^(void) {
                     
                     [self startColorCamera];
                     
                     _appStatus.colorCameraIsAuthorized = true;
                     [self updateAppStatusMessage];
                     
                 });
                 
             }
             
         }];
        
        return false;
    }

    return true;
    
}

// カラー画像カメラのセットアップ
- (void)setupColorCamera
{
    // If already setup, skip it
    if (_avCaptureSession)
        return;
    
    bool cameraAccessAuthorized = [self queryCameraAuthorizationStatusAndNotifyUserIfNotGranted];
    
    if (!cameraAccessAuthorized)
    {
        _appStatus.colorCameraIsAuthorized = false;
        [self updateAppStatusMessage];
        return;
    }
    
    // Use VGA color.
    NSString *sessionPreset = AVCaptureSessionPreset640x480;
    
    // Set up Capture Session.
    _avCaptureSession = [[AVCaptureSession alloc] init];
    [_avCaptureSession beginConfiguration];
    
    // Set preset session size.
    [_avCaptureSession setSessionPreset:sessionPreset];
    
    // Create a video device and input from that Device.  Add the input to the capture session.
    _videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (_videoDevice == nil)
        assert(0);
    
    // Configure Focus, Exposure, and White Balance
    NSError *error;
    
    // Use auto-exposure, and auto-white balance and set the focus to infinity.
    if([_videoDevice lockForConfiguration:&error])
    {
        // Allow exposure to change
        if ([_videoDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        
        // Allow white balance to change
        if ([_videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
            [_videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        
        // Set focus at the maximum position allowable (e.g. "near-infinity") to get the
        // best color/depth alignment.
        [_videoDevice setFocusModeLockedWithLensPosition:1.0f completionHandler:nil];
        
        [_videoDevice unlockForConfiguration];
    }
    
    //  Add the device to the session.
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
    if (error)
    {
        NSLog(@"Cannot initialize AVCaptureDeviceInput");
        assert(0);
    }
    
    [_avCaptureSession addInput:input]; // After this point, captureSession captureOptions are filled.
    
    //  Create the output for the capture session.
    AVCaptureVideoDataOutput* dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // We don't want to process late frames.
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    // Use BGRA pixel format.
    [dataOutput setVideoSettings:[NSDictionary
                                  dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                  forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    // Set dispatch to be on the main thread so OpenGL can do things with the data
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_avCaptureSession addOutput:dataOutput];
    
    if([_videoDevice lockForConfiguration:&error])
    {
        [_videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice unlockForConfiguration];
    }
    
    [_avCaptureSession commitConfiguration];
}

- (void)startColorCamera
{
    if (_avCaptureSession && [_avCaptureSession isRunning])
        return;
    
    // Re-setup so focus is lock even when back from background
    if (_avCaptureSession == nil)
        [self setupColorCamera];
    
    // Start streaming color images.
    [_avCaptureSession startRunning];
}

// カメラ停止
- (void)stopColorCamera
{
    if ([_avCaptureSession isRunning])
    {
        // Stop the session
        [_avCaptureSession stopRunning];
    }
    
    _avCaptureSession = nil;
    _videoDevice = nil;
}

// キャプチャした画像を最終的に出力する？
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // Pass into the driver. The sampleBuffer will return later with a synchronized depth or IR pair.
    [_sensorController frameSyncNewColorBuffer:sampleBuffer];
}


@end

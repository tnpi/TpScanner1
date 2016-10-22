/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "ViewController+Camera.h"
#import "ViewController+Sensor.h"
#import "ViewController+SLAM.h"

#import <Structure/Structure.h>
#import <Structure/StructureSLAM.h>

@implementation ViewController (Camera)

#pragma mark -  Color Camera


// カメラ使用の認証の要求
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
             
             // If the request is granted, let's try again to start an AVFoundation session.
             // Otherwise, alert the user that things won't go well.
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


// キャプチャフォーマットの選択
- (void)selectCaptureFormat:(NSDictionary*)demandFormat
{
    AVCaptureDeviceFormat * selectedFormat = nil;
    
    for (AVCaptureDeviceFormat* format in self.videoDevice.formats)
    {
        double formatMaxFps = ((AVFrameRateRange *)[format.videoSupportedFrameRateRanges objectAtIndex:0]).maxFrameRate;
        
        CMFormatDescriptionRef formatDesc = format.formatDescription;
        FourCharCode fourCharCode = CMFormatDescriptionGetMediaSubType(formatDesc);
        
        CMVideoFormatDescriptionRef videoFormatDesc = formatDesc;
        CMVideoDimensions formatDims = CMVideoFormatDescriptionGetDimensions(videoFormatDesc);
        
        NSNumber * widthNeeded  = demandFormat[@"width"];
        NSNumber * heightNeeded = demandFormat[@"height"];
        
        if ( widthNeeded && widthNeeded .intValue!= formatDims.width )
            continue;
        
        if( heightNeeded && heightNeeded.intValue != formatDims.height )
            continue;
        
        // we only support full range YCbCr for now
        if(fourCharCode != (FourCharCode)'420f')
            continue;

        
        selectedFormat = format;
        break;
    }
    
    self.videoDevice.activeFormat = selectedFormat;
}


// レンズポジションの設定
- (void)setLensPositionWithValue:(float)value lockVideoDevice:(bool)lockVideoDevice
{
    if(!self.videoDevice) return; // Abort if there's no videoDevice yet.
    
    if(lockVideoDevice && ![self.videoDevice lockForConfiguration:nil]) {
        return; // Abort early if we cannot lock and are asked to.
    }
    
    [self.videoDevice setFocusModeLockedWithLensPosition:value completionHandler:nil];

    if(lockVideoDevice)
        [self.videoDevice unlockForConfiguration];
}


// カラーカメラのセットアップ
- (void)setupColorCamera
{
    // If already setup, skip it
    if (self.avCaptureSession)
        return;
    
    bool cameraAccessAuthorized = [self queryCameraAuthorizationStatusAndNotifyUserIfNotGranted];
    
    if (!cameraAccessAuthorized)
    {
        _appStatus.colorCameraIsAuthorized = false;
        [self updateAppStatusMessage];
        return;
    }
    
    // Set up Capture Session.
    self.avCaptureSession = [[AVCaptureSession alloc] init];
    [self.avCaptureSession beginConfiguration];
    
    // InputPriority allows us to select a more precise format (below)
    [self.avCaptureSession setSessionPreset:AVCaptureSessionPresetInputPriority];
    
    // Create a video device and input from that Device.  Add the input to the capture session.
    self.videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (self.videoDevice == nil)
        assert(0);
    
    // Configure Focus, Exposure, and White Balance
    NSError *error;
    
    if([self.videoDevice lockForConfiguration:&error])
    {
        int imageWidth = -1;
        int imageHeight = -1;
        
        if (self.enableHighResolutionColorSwitch.on)
        {
            // High-resolution uses 2592x1936, which is close to a 4:3 aspect ratio.
            // Other aspect ratios such as 720p or 1080p are not yet supported.
            imageWidth = 2592;
            imageHeight = 1936;
        }
        else
        {
            // Low resolution uses VGA.
            imageWidth = 640;
            imageHeight = 480;
        }
        
        // Select capture format
        [self selectCaptureFormat:@{ @"width": @(imageWidth),
                                     @"height": @(imageHeight)}];
        
        // Allow exposure to initially change
        if ([self.videoDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        
        // Allow white balance to initially change
        if ([self.videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
            [self.videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];

        // Apply to specified focus position.
        [self setLensPositionWithValue:_options.lensPosition lockVideoDevice:false];
        
        [self.videoDevice unlockForConfiguration];
    }
    
    //  Add the device to the session.
    // 入力デバイスを取得
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
    if (error)
    {
        NSLog(@"Cannot initialize AVCaptureDeviceInput");
        assert(0);
    }
    
    // AVキャプチャセッションに入力デバイスを追加
    [self.avCaptureSession addInput:input]; // After this point, captureSession captureOptions are filled.
    
    // Create the output for the capture session.
    // 出力を生成
    AVCaptureVideoDataOutput* dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // We don't want to process late frames.
    // 取得したビデオフレームは後で使わないので常に捨てるように設定
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    // Use YCbCr pixel format.
    // YCbCrピクセルフォーマットを使用
    [dataOutput setVideoSettings:[NSDictionary
                                  dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                                  forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    // Set dispatch to be on the main thread so OpenGL can do things with the data
    // OpenGLがデータを処理できるように、メインスレッドにディスパッチを登録
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [self.avCaptureSession addOutput:dataOutput];
    
    // Force the framerate to 30 FPS, to be in sync with Structure Sensor.
    // フレームレートを強制的に30FPSにして、3Dセンサと同期させる
    if([self.videoDevice lockForConfiguration:&error])
    {
        CMTime targetFrameDuration = CMTimeMake(1,30);
        
        // >0 if min duration > desired duration, in which case we need to increase our duration to the minimum
        // or else the camera will throw an exception.
        if(CMTimeCompare(self.videoDevice.activeVideoMinFrameDuration, targetFrameDuration) > 0)
        {
            // In firmware <= 1.1, we can only support frame sync with 30 fps or 15 fps.
            targetFrameDuration = CMTimeMake(1, 15);
        }
        
        [self.videoDevice setActiveVideoMaxFrameDuration:targetFrameDuration];
        [self.videoDevice setActiveVideoMinFrameDuration:targetFrameDuration];
        [self.videoDevice unlockForConfiguration];
    }
    
    [self.avCaptureSession commitConfiguration];
}

// カラーカメラの開始
- (void)startColorCamera
{
    if (self.avCaptureSession && [self.avCaptureSession isRunning])
        return;
    
    // Re-setup so focus is lock even when back from background
    // ロックやバックグラウンド処理から戻ってきた時はフォーカスを再設定
    if (self.avCaptureSession == nil)
        [self setupColorCamera];
    
    // Start streaming color images.
    // カラー画像の連続取得を開始
    [self.avCaptureSession startRunning];
}

- (void)stopColorCamera
{
    if ([self.avCaptureSession isRunning])
    {
        // Stop the session
        [self.avCaptureSession stopRunning];
    }
    
    self.avCaptureSession = nil;
    self.videoDevice = nil;
}

// 初期化のためにカラーカメラのパラメータを設定
- (void)setColorCameraParametersForInit
{
    NSError *error;
    
    [self.videoDevice lockForConfiguration:&error];
    
    // Auto-exposure
    if ([self.videoDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
        [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    
    // Auto-white balance.
    if ([self.videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
        [self.videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
    
    [self.videoDevice unlockForConfiguration];
    
}

// スキャニングのためにカラーカメラのパラメータを設定
- (void)setColorCameraParametersForScanning
{
    NSError *error;
    
    [self.videoDevice lockForConfiguration:&error];
    
    // Exposure locked to its current value.
    if ([self.videoDevice isExposureModeSupported:AVCaptureExposureModeLocked])
        [self.videoDevice setExposureMode:AVCaptureExposureModeLocked];
    
    // White balance locked to its current value.
    if ([self.videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked])
        [self.videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeLocked];
    
    [self.videoDevice unlockForConfiguration];
}

// センサーコントローラーにキャプチャしたものを出力
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // Pass color buffers directly to the driver, which will then produce synchronized depth/color pairs.
    // カラーバッファを通してドライバに直接、それはデプスとカラーのペアのシンクロが生成されるだろう時？
    [_sensorController frameSyncNewColorBuffer:sampleBuffer];
}

@end
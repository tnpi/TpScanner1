/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "ViewController+OpenGL.h"

#import <Structure/Structure.h>
#import <Structure/StructureSLAM.h>


#pragma mark - Utilities

namespace // anonymous namespace for local functions
{
    
    // 微小回転角度と姿勢の間を度で？？
    float deltaRotationAngleBetweenPosesInDegrees (const GLKMatrix4& previousPose, const GLKMatrix4& newPose)
    {
        GLKMatrix4 deltaPose = GLKMatrix4Multiply(newPose,
                                                  // Transpose is equivalent to inverse since we will only use the rotation part.
                                                  GLKMatrix4Transpose(previousPose));
        
        // Get the rotation component of the delta pose
        GLKQuaternion deltaRotationAsQuaternion = GLKQuaternionMakeWithMatrix4(deltaPose);
        
        // Get the angle of the rotation
        const float angleInDegree = GLKQuaternionAngle(deltaRotationAsQuaternion)/M_PI*180;
        
        return angleInDegree;
    }
}



@implementation ViewController (SLAM)

#pragma mark - SLAM

// Set up SLAM related objects.
// SLAM関係のオブジェクトのセットアップ
- (void)setupSLAM
{
    if (_slamState.initialized)
        return;
    
    // Initialize the scene.
    // シーンの初期化
    _slamState.scene = [[STScene alloc] initWithContext:_display.context
                                      freeGLTextureUnit:GL_TEXTURE2];
    
    // Initialize the camera pose tracker.
    // カメラ姿勢トラッカーの初期化
    NSDictionary* trackerOptions = @{
                                     kSTTrackerTypeKey: self.enableNewTrackerSwitch.on ? @(STTrackerDepthAndColorBased) : @(STTrackerDepthBased),
                                     kSTTrackerTrackAgainstModelKey: @TRUE, // tracking against the model is much better for close range scanning.
                                     kSTTrackerQualityKey: @(STTrackerQualityAccurate),
                                     kSTTrackerBackgroundProcessingEnabledKey: @TRUE
                                     };
    
    NSError* trackerInitError = nil;
    
    // Initialize the camera pose tracker.
    // カメラ姿勢トラッカーの初期化
    _slamState.tracker = [[STTracker alloc] initWithScene:_slamState.scene options:trackerOptions error:&trackerInitError];
    
    if (trackerInitError != nil)
    {
        NSLog(@"Error during STTracker initialization: `%@'.", [trackerInitError localizedDescription]);
    }
    
    NSAssert (_slamState.tracker != nil, @"Could not create a tracker.");
    
    
    // Initialize the mapper.
    // マッパーオプションの指定（主にボリュームサイズ）
    NSDictionary* mapperOptions =
    @{
      kSTMapperVolumeResolutionKey: @[@(round(_options.initialVolumeSizeInMeters.x / _options.initialVolumeResolutionInMeters)),
                                      @(round(_options.initialVolumeSizeInMeters.y / _options.initialVolumeResolutionInMeters)),
                                      @(round(_options.initialVolumeSizeInMeters.z / _options.initialVolumeResolutionInMeters))]
      };
    
    // マッパーの初期化
    _slamState.mapper = [[STMapper alloc] initWithScene:_slamState.scene
                                                options:mapperOptions];
    
    // We need it for the TrackAgainstModel tracker, and for live rendering.
    // 私たちはこれを必要とする　トラック背景モデルトラッカーのために、そしてライブレンダリングのために
    _slamState.mapper.liveTriangleMeshEnabled = true;       // これが三角形のメッシュを表示・モデリングする tanaka important
    
    // Default volume size set in options struct
    // デフォルトのボリュームサイズを設定
    _slamState.mapper.volumeSizeInMeters = _options.initialVolumeSizeInMeters;
    
    // Setup the cube placement initializer.
    // キューブ設置初期化lizerをセットアップ
    NSError* cameraPoseInitializerError = nil;
    _slamState.cameraPoseInitializer = [[STCameraPoseInitializer alloc]
                                        initWithVolumeSizeInMeters:_slamState.mapper.volumeSizeInMeters
                                        options:@{kSTCameraPoseInitializerStrategyKey: @(STCameraPoseInitializerStrategyTableTopCube)}
                                        error:&cameraPoseInitializerError];
    NSAssert (cameraPoseInitializerError == nil, @"Could not initialize STCameraPoseInitializer: %@", [cameraPoseInitializerError localizedDescription]);
    
    // Set up the cube renderer with the current volume size.
    // 現在のボリュームサイズでキューブレンダラーをセットアップ
    _display.cubeRenderer = [[STCubeRenderer alloc] initWithContext:_display.context];
    
    // Set up the initial volume size.
    // 初期ボリュームサイズをセットアップ
    [self adjustVolumeSize:_slamState.mapper.volumeSizeInMeters];
    
    // Start with cube placement mode
    // キューブ設置モードで開始
    [self enterCubePlacementState];
    
    // キーフレームマネージャーのオプションを設定
    NSDictionary* keyframeManagerOptions = @{
                                             kSTKeyFrameManagerMaxSizeKey: @(_options.maxNumKeyFrames),
                                             kSTKeyFrameManagerMaxDeltaTranslationKey: @(_options.maxKeyFrameTranslation),
                                             kSTKeyFrameManagerMaxDeltaRotationKey: @(_options.maxKeyFrameRotation), // 20 degrees.
                                             };
    
    NSError* keyFrameManagerInitError = nil;
    
    // キーフレームマネージャーの初期化
    _slamState.keyFrameManager = [[STKeyFrameManager alloc] initWithOptions:keyframeManagerOptions error:&keyFrameManagerInitError];
    
    // エラーだった場合はログに表示
    NSAssert (keyFrameManagerInitError == nil, @"Could not initialize STKeyFrameManger: %@", [keyFrameManagerInitError localizedDescription]);
    
    // 深度データをRGBAとして可視化するオブジェクトの初期化
    _depthAsRgbaVisualizer = [[STDepthToRgba alloc] initWithOptions:@{kSTDepthToRgbaStrategyKey: @(STDepthToRgbaStrategyGray)}
                                                              error:nil];
    
    // SLAMが初期化されたフラグをセット
    _slamState.initialized = true;
    

}


- (void)resetSLAM
{
    _slamState.prevFrameTimeStamp = -1.0;
    [_slamState.mapper reset];
    [_slamState.tracker reset];
    [_slamState.scene clear];
    [_slamState.keyFrameManager clear];
    
    [self enterCubePlacementState];
}


- (void)clearSLAM
{
    _slamState.initialized = false;
    _slamState.scene = nil;
    _slamState.tracker = nil;
    _slamState.mapper = nil;
    _slamState.keyFrameManager = nil;
}


// デプスフレームとカラーフレームの処理
- (void)processDepthFrame:(STDepthFrame *)depthFrame
          colorFrameOrNil:(STColorFrame*)colorFrame
{
    
    // Upload the new color image for next rendering.
    // 次のレンダリングのために新しいカラーイメージをアップロード
    if (_useColorCamera && colorFrame != nil)
    {
        // GLカラーテクスチャをアップロード
        [self uploadGLColorTexture: colorFrame];
    }
    else if(!_useColorCamera)
    {
        // カラーカメラを使っていない場合、デプスフレームをGLカラーテクスチャにアップロード
        [self uploadGLColorTextureFromDepth:depthFrame];
    }
    
    // Update the projection matrices since we updated the frames.
    // 行列の投影(ProjectionMatrix)を更新する、フレームの更新のために
    {
        _display.depthCameraGLProjectionMatrix = [depthFrame glProjectionMatrix];
        
        // カラーフレームがある場合
        if (colorFrame)
            _display.colorCameraGLProjectionMatrix = [colorFrame glProjectionMatrix];
    }
    
    switch (_slamState.scannerState)
    {

        // スキャナの状態が、キューブ配置のとき
        case ScannerStateCubePlacement:
        {
            // Provide the new depth frame to the cube renderer for ROI highlighting.
            // 新しいデプスフレームを提供する　キューブレンダラーに　ROIハイライトのために（Region Of Interest 奥行きのカラー表示？）
            [_display.cubeRenderer setDepthFrame:_useColorCamera?[depthFrame registeredToColorFrame:colorFrame]:depthFrame];
            
            // Estimate the new scanning volume position.
            // 新しいスキャンボリュームポジションを概算する
            if (GLKVector3Length(_lastGravity) > 1e-5f)
            {
                bool success = [_slamState.cameraPoseInitializer updateCameraPoseWithGravity:_lastGravity depthFrame:depthFrame error:nil];
                NSAssert (success, @"Camera pose initializer error.");
            }
            
            // Tell the cube renderer whether there is a support plane or not.
            // それがサポートプレーンかそうでないかをキューブレンダラーに教える
            [_display.cubeRenderer setCubeHasSupportPlane:_slamState.cameraPoseInitializer.hasSupportPlane];
            
            // Enable the scan button if the pose initializer could estimate a pose.
            // スキャンボタンを有効にする　ポーズ位にシャラいざがポーズを概算できるなら
            self.scanButton.enabled = _slamState.cameraPoseInitializer.hasValidPose;
            break;
        }

        // スキャナの状態が、スキャン中のとき
        case ScannerStateScanning:
        {
            
            // First try to estimate the 3D pose of the new frame.
            // 新しいフレームの3D姿勢概算のための最初の試行
            NSError* trackingError = nil;
            
            // トラッキング前のデプスカメラ姿勢
            GLKMatrix4 depthCameraPoseBeforeTracking = [_slamState.tracker lastFrameCameraPose];
            
            // カメラ姿勢の更新
            
            BOOL trackingOk = [_slamState.tracker updateCameraPoseWithDepthFrame:depthFrame colorFrame:colorFrame error:&trackingError];
            
            // Integrate it into the current mesh estimate if tracking was successful.
            // そrを現在のメッシュへ統合する　概算　トラッキングが成功した時
            if (trackingOk)
            {
                // トラッキング後のデプスカメラ姿勢
                GLKMatrix4 depthCameraPoseAfterTracking = [_slamState.tracker lastFrameCameraPose];

                if (scanFrameCount % scanFrameTime == 0) {
                    
                    // データストア配列にデータを追加・保存する
                    //STMesh tMesh = [[_slamState.scene lockAndGetSceneMesh] copy];
                    //[recordMeshList addObject:tMesh];
                    
                    //STMesh *tMesh = [_slamState.scene lockAndGetSceneMesh];
                    //[recordMeshList addObject:tMesh];
                    STMesh* sceneMesh = [[STMesh alloc] initWithMesh:[_slamState.scene lockAndGetSceneMesh]];
                    
                    scanNowDate = [NSDate date];
                    [scanFrameDateList addObject:scanNowDate];      // １コマ スキャンし終わった日時を保存しておく
                    
                    [recordMeshList addObject:sceneMesh];
                    
                    [_slamState.scene unlockSceneMesh];     // ロック解除
                    
                    recordMeshNum++;
                    
                    
                    //self.recFramesValueLabel.text = [NSString stringWithFormat:@"%d", recordMeshNum];
                    // ラベル更新
                    NSUInteger elements = [recordMeshList count];
                    self.recFramesValueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)elements];
                    
                    
                    [_slamState.mapper reset];      // リアルタイム3Dスキャンにする！ add by tanaka important
                }
                
                scanFrameCount++;
                _useColorCamera = true;
                
                //_renderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
                
                // マッパーがカメラ姿勢とデプスフレームを統合する
                [_slamState.mapper integrateDepthFrame:depthFrame cameraPose:depthCameraPoseAfterTracking];
                
                // カラーフレームがある時
                if (colorFrame)
                {
                    // Make sure the pose is in color camera coordinates in case we are not using registered depth.
                    // 姿勢がカラーカメラ座標にあるようにする？ 登録されたデプスを使用しない場合？
                    GLKMatrix4 colorCameraPoseInDepthCoordinateSpace;
                    [depthFrame colorCameraPoseInDepthCoordinateFrame:colorCameraPoseInDepthCoordinateSpace.m];
                    GLKMatrix4 colorCameraPoseAfterTracking = GLKMatrix4Multiply(depthCameraPoseAfterTracking,
                                                                                 colorCameraPoseInDepthCoordinateSpace);
                    

                    bool showHoldDeviceStill = false;
                    
                    // Check if the viewpoint has moved enough to add a new keyframe
                    // 新しいキーフレームを追加するために、視点が十分に移動されたかどうかをチェックする
                    if ([_slamState.keyFrameManager wouldBeNewKeyframeWithColorCameraPose:colorCameraPoseAfterTracking])
                    {
                        const bool isFirstFrame = (_slamState.prevFrameTimeStamp < 0.);
                        bool canAddKeyframe = false;
                        
                        if (isFirstFrame) // always add the first frame.　初回のフレームはいつも追加する
                        {
                            canAddKeyframe = true;
                        }
                        
                        else // for others, check the speed.　初回でない場合はスピードをチェックする
                        {
                            float deltaAngularSpeedInDegreesPerSecond = FLT_MAX;
                            NSTimeInterval deltaSeconds = depthFrame.timestamp - _slamState.prevFrameTimeStamp;
                            
                            // If deltaSeconds is 2x longer than the frame duration of the active video device, do not use it either
                            CMTime frameDuration = self.videoDevice.activeVideoMaxFrameDuration;
                            if (deltaSeconds < (float)frameDuration.value/frameDuration.timescale*2.f)
                            {
                                // Compute angular speed
                                deltaAngularSpeedInDegreesPerSecond = deltaRotationAngleBetweenPosesInDegrees (depthCameraPoseBeforeTracking, depthCameraPoseAfterTracking)/deltaSeconds;
                            }
                            
                            // If the camera moved too much since the last frame, we will likely end up
                            // with motion blur and rolling shutter, especially in case of rotation. This
                            // checks aims at not grabbing keyframes in that case.
                            if (deltaAngularSpeedInDegreesPerSecond < _options.maxKeyframeRotationSpeedInDegreesPerSecond)
                            {
                                canAddKeyframe = true;
                            }
                        }
                        
                        // キーフレームを追加できるならば
                        if (canAddKeyframe)
                        {

                            // キーフレーム候補者を処理する　カラーカメラ姿勢とともに
                            // important
                             [_slamState.keyFrameManager processKeyFrameCandidateWithColorCameraPose:colorCameraPoseAfterTracking
                             colorFrame:colorFrame
                             depthFrame:nil];

                            // tanaka add   こっちにするとカラービューでも色がつかない
                            /*
                            [_slamState.keyFrameManager clear];
                            [_slamState.keyFrameManager processKeyFrameCandidateWithColorCameraPose:colorCameraPoseAfterTracking
                                                                                         colorFrame:colorFrame
                                                                                         depthFrame:nil];
                             */
                             
                        }
                        else
                        {
                            // Moving too fast. Hint the user to slow down to capture a keyframe
                            // without rolling shutter and motion blur.
                            // 早く移動しすぎている時、キーフレームのキャプチャをゆっくりさせるため、ユーザにヒントを出す
                            showHoldDeviceStill = true;
                        }
                    }
                    
                    // 早く移動しすぎている時、キーフレームのキャプチャをゆっくりさせるため、ユーザにヒントを出す
                    if (showHoldDeviceStill)
                        [self showTrackingMessage:@"Please hold still so we can capture a keyframe..."];
                    else
                        [self hideTrackingErrorMessage];
                }
                else
                {
                    // トラッキングエラーメッセージを隠す
                    [self hideTrackingErrorMessage];
                }
                
            }
            
            // トラッキングエラーの内容の表示処理
            else if (trackingError.code == STErrorTrackerLostTrack)
            {
                [self showTrackingMessage:@"Tracking Lost! Please Realign or Press Reset."];
            }
            
            else if (trackingError.code == STErrorTrackerPoorQuality)
            {
                switch ([_slamState.tracker status])
                {
                    case STTrackerStatusDodgyForUnknownReason:
                    {
                        NSLog(@"STTracker Tracker quality is bad, but we don't know why.");
                        // Don't show anything on screen since this can happen often.
                        break;
                    }
                        
                    case STTrackerStatusFastMotion:
                    {
                        NSLog(@"STTracker Camera moving too fast.");
                        // Don't show anything on screen since this can happen often.
                        break;
                    }
                        
                    case STTrackerStatusTooClose:
                    {
                        NSLog(@"STTracker Too close to the model.");
                        [self showTrackingMessage:@"Too close to the scene! Please step back."];
                        break;
                    }
                        
                    case STTrackerStatusTooFar:
                    {
                        NSLog(@"STTracker Too far from the model.");
                        [self showTrackingMessage:@"Please get closer to the model."];
                        break;
                    }
                        
                    case STTrackerStatusRecovering:
                    {
                        NSLog(@"STTracker Recovering.");
                        [self showTrackingMessage:@"Recovering, please move gently."];
                        break;
                    }
                        
                    case STTrackerStatusModelLost:
                    {
                        NSLog(@"STTracker model not in view.");
                        [self showTrackingMessage:@"Please put the model back in view."];
                        break;
                    }
                    default:
                        NSLog(@"STTracker unknown quality.");
                }
            }
            else
            {
                NSLog(@"[Structure] STTracker Error: %@.", [trackingError localizedDescription]);
            }
            
            _slamState.prevFrameTimeStamp = depthFrame.timestamp;
            
            break;
        }
            
        // スキャナーの状態がビューイングモードの時は、MeshViewControllerがこの部分にあたる仕事をする（ので、ここでは何もしない）
        case ScannerStateViewing:
        default:
        {} // Do nothing, the MeshViewController will take care of this.
    }
}

@end
/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "ViewController+Camera.h"
#import "ViewController+Sensor.h"
#import "ViewController+SLAM.h"
#import "ViewController+OpenGL.h"
#import <Structure/Structure.h>


#include <cmath>

// Needed to determine platform string
#include <sys/types.h>
#include <sys/sysctl.h>

#pragma mark - Utilities



/*
@implementation STMesh {
    
    - (void)viewDidLoad {
        [super viewDidLoad];
        [self testMethod];
    }
    
    - (void)testMethod {
        // SampleClass2の初期化
        SampleClass2 *sample2 = [[SampleClass2 alloc] init];
        // SampleClass2で定義されたsample2Methodを実行
        [sample2 sample2Method];
        // スーパークラスであるSampleClassのsampleMethodを実行
        [sample2 sampleMethod];
    }
    
    @end
    [self sampleMethod];
}
*/

namespace // anonymous namespace for local functions.
{

    BOOL isIpadAir2()
    {
        const char* kernelStringName = "hw.machine";
        NSString* deviceModel;
        {
            size_t size;
            sysctlbyname(kernelStringName, NULL, &size, NULL, 0); // Get the size first
            
            char *stringNullTerminated = (char*)malloc(size);
            sysctlbyname(kernelStringName, stringNullTerminated, &size, NULL, 0); // Now, get the string itself
            
            deviceModel = [NSString stringWithUTF8String:stringNullTerminated];
            free(stringNullTerminated);
        }
        
        if ([deviceModel isEqualToString:@"iPad5,3"]) return YES; // Wi-Fi
        if ([deviceModel isEqualToString:@"iPad5,4"]) return YES; // Wi-Fi + LTE
        return NO;
    }
    
    BOOL getDefaultHighResolutionSettingForCurrentDevice()
    {
        // iPad Air 2 can handle 30 FPS high-resolution, so enable it by default.
        if (isIpadAir2())
            return TRUE;
        
        // Older devices can only handle 15 FPS high-resolution, so keep it disabled by default
        // to avoid showing a low framerate.
        return FALSE;
    }
    
} // anonymous



#pragma mark - ViewController Setup

@implementation ViewController {
    UITableView *loadListTableView;
    UILabel *loadListLabelView;
    NSArray *loadListArray;
}

- (void)dealloc
{
    [self.avCaptureSession stopRunning];
    
    if ([EAGLContext currentContext] == _display.context)
    {
        [EAGLContext setCurrentContext:nil];
    }
}


// 画面のインスタンスが初期化される時、一回だけ
// アプリを起動して、画面を読み込み終わった時
// important
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    scanFrameTime = 1;      // add by tanaka
    scanFrameCount = 0;      // add by tanaka
    recordMeshNum = 0;      // add by tanaka
    recordMeshList = [NSMutableArray array];
    scanFrameDateList = [NSMutableArray array];     // add 2016.6
    
    basePath = @"";
    fileManager = [[NSFileManager alloc] init];
    //filePath = [[NSBundle mainBundle] bundlePath];
    filePath = @"Documents/artdkt_structure3d";
    
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
    
    NSLog(@"filePathScan: %s", [filePath UTF8String] );
    for (NSString *content in [fileManager contentsOfDirectoryAtPath:filePath error:nil ]) {
        const char *chars = [content UTF8String];
        NSLog(@"filePathList: %s", chars);
    }
    
    
    // UI setting part -------------------------------------- add by tanaka
    loadListLabelView = [[UILabel alloc] init];
    loadListLabelView.text = @"いらっしゃいませ。";
    [loadListLabelView sizeToFit];
    
    loadListArray = [NSMutableArray arrayWithObjects: nil];//;[NSArray arrayWithObjects:@"乗用車", @"トラック", @"オープンカー", @"タクシー", nil];
    
    loadListTableView = [[UITableView alloc] init] ;
    loadListTableView.frame = CGRectMake(0, 0, 500,500);
    
    loadListTableView.center = self.view.center;
    loadListTableView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
    UIViewAutoresizingFlexibleRightMargin |
    UIViewAutoresizingFlexibleTopMargin |
    UIViewAutoresizingFlexibleBottomMargin |
    UIViewAutoresizingFlexibleWidth;
    
    loadListTableView.dataSource = self;
    loadListTableView.delegate = self;
    
    self.view.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:loadListLabelView];
    [self.view addSubview:loadListTableView];
    
    loadListLabelView.hidden = YES;
    loadListTableView.hidden = YES;

    // ---------------------------------------------------------------
    
    
    //UIViewに重なる。;
    _calibrationOverlay = nil;

    
    [self setupGL];
    
    [self setupUserInterface];
    
    [self setupMeshViewController];
    
    [self setupGestures];
    
    [self setupIMU];
    
    [self setupStructureSensor];
    
    // Later, we’ll set this true if we have a device-specific calibration
    _useColorCamera = [STSensorController approximateCalibrationGuaranteedForDevice];
    
    // Make sure we get notified when the app becomes active to start/restore the sensor state if necessary.
    // アプリがアクティブになったときにセンサを復旧するために通知を取得できるようにする
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    

    // ogawa add
    // Do any additional setup after loading the view, typically from a nib.
    MyUdpConnection *udp = [[MyUdpConnection alloc]initWithDelegate:self portNum:5555];
    [udp bind];

}


- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
    return loadListArray.count;
}

- (UITableViewCell*)tableView:(UITableView *)tableView
        cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell
    = [loadListTableView dequeueReusableCellWithIdentifier:@"cell"];
    if(cell == nil){
        cell
        = [[UITableViewCell alloc]
           initWithStyle:UITableViewCellStyleDefault
           reuseIdentifier:@"cell"];
    }
    
    
    loadListArray = fileList;
    cell.textLabel.text = [loadListArray objectAtIndex:indexPath.row];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *str = [loadListArray objectAtIndex:indexPath.row];
    loadListLabelView.text = [NSString stringWithFormat:@"%@ですね。", str];
    [loadListLabelView sizeToFit];
}



// ビューが表示される時、毎回 	（画面が表示された後に呼び出される）
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // The framebuffer will only be really ready with its final size after the view appears.
    // ビューが表示準備されたあとの最終的なサイズ
    [(EAGLView *)self.view setFramebuffer];
    
    [self setupGLViewport];

    [self updateAppStatusMessage];
    
    // We will connect to the sensor when we receive appDidBecomeActive.
    // appDidBecomeActiveを受け取ったあとにセンサに接続します
}

// アプリがアクティブになったら
- (void)appDidBecomeActive
{
    NSLog(@"appDidBecomeActive start");
    
    // 3Dセンサに接続して開始
    if ([self currentStateNeedsSensor])
        [self connectToStructureSensorAndStartStreaming];
    
    // Abort the current scan if we were still scanning before going into background since we
    // are not likely to recover well.
    if (_slamState.scannerState == ScannerStateScanning)
    {
        
        NSLog(@"appDidBecomeActive resetButtonPressed");
        [self resetButtonPressed:self];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    [self respondToMemoryWarning];
}

// UIのセットアップ
- (void)setupUserInterface
{
    // Make sure the status bar is hidden.
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    
    // Fully transparent message label, initially.
    // 最初はメッセージラベルを透明表示（非表示）にする
    self.appStatusMessageLabel.alpha = 0;
    
    // Make sure the label is on top of everything else.
    // メッセージラベルをいつも最上位に表示する
    self.appStatusMessageLabel.layer.zPosition = 100;
    
    // Set the default value for the high resolution switch. If set, will use 2592x1968 as color input.
    // 高解像度スイッチのデフォルト値をセットする
    self.enableHighResolutionColorSwitch.on = getDefaultHighResolutionSettingForCurrentDevice();
}

// Make sure the status bar is disabled (iOS 7+)
- (BOOL)prefersStatusBarHidden
{
    return YES;
}

// ジェスチャーのセットアップ
- (void)setupGestures
{
    // Register pinch gesture for volume scale adjustment.
    // スケール設定のための"ピンチ"ジェスチャーの登録
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGesture:)];
    [pinchGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchGesture];
}

// メッシュビューコントローラーのセットアップ
- (void)setupMeshViewController
{
    // The mesh viewer will be used after scanning.
    // このメッシュビューアーはスキャンし終わったあとに使われる
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        _meshViewController = [[MeshViewController alloc] initWithNibName:@"MeshView_iPhone" bundle:nil];
    } else {
        _meshViewController = [[MeshViewController alloc]  initWithNibName:@"MeshView_iPad" bundle:nil];
    }
    _meshViewController.delegate = self;
    _meshViewNavigationController = [[UINavigationController alloc] initWithRootViewController:_meshViewController];
    
}

// メッシュビューワーを表示する
- (void)presentMeshViewer:(STMesh *)mesh
{
    NSLog(@"ViewController presentMeshViewer() start");
    _meshViewController.recordMeshNum = recordMeshNum;
    _meshViewController.playbackRecordTimeValueLabel.text = [NSString stringWithFormat:@"%d", recordMeshNum];

    [_meshViewController setupGL:_display.context];
    
    
    NSLog(@"ViewController presentMeshViewer() _useColorCamera");
    
    _meshViewController.colorEnabled = _useColorCamera;
    NSLog(@"ViewController presentMeshViewer .mesh=mesh start");
    _meshViewController.mesh = mesh;        // ここでsetMeshが呼ばれる？
    NSLog(@"ViewController presentMeshViewer .mesh=mesh end");
    [_meshViewController setCameraProjectionMatrix:_display.depthCameraGLProjectionMatrix];
    
    GLKVector3 volumeCenter = GLKVector3MultiplyScalar([_slamState.mapper volumeSizeInMeters], 0.5);
    [_meshViewController resetMeshCenter:volumeCenter];
    
    [self presentViewController:_meshViewNavigationController animated:YES completion:^{}];
}

- (IBAction)loadButtonPressed:(id)sender {
    
    loadListLabelView.hidden = NO;
    loadListTableView.hidden = NO;
    
}

// 立方体調整モード状態に入る時に実行する処理（ボタンの表示非表示の変更など）

- (void)enterCubePlacementState
{
    // Switch to the Scan button.
    self.scanButton.hidden = NO;
    self.doneButton.hidden = YES;
    self.resetButton.hidden = YES;
    
    // We'll enable the button only after we get some initial pose.
    self.scanButton.enabled = NO;
    
    // Cannot be lost in cube placement mode.
    _trackingLostLabel.hidden = YES;
    
    [self setColorCameraParametersForInit];
    
    _slamState.scannerState = ScannerStateCubePlacement;
    
    [self updateIdleTimer];
    
}

// スキャニング状態に入る時に実行する処理（ボタンの表示非表示の変更など）
- (void)enterScanningState
{
    
    NSLog(@"enterScanningState start");
    
    // Switch to the Done button.
    self.scanButton.hidden = YES;
    self.doneButton.hidden = NO;
    self.resetButton.hidden = NO;

    scanStartDate = [NSDate date];
    
    // Simulate a full reset to force a creation of a new tracker.
    /*
    [self resetButtonPressed:self.resetButton];
    [self clearSLAM];
    [self setupSLAM];
    */
    
    //[self clearSLAM];           // add by tanaka
    /*
    scanFrameCount = 0;           // add by tanaka
    recordMeshNum = 0;           // add by tanaka
    scanFrameTime = 0;           // add by tanaka
    [recordMeshList removeAllObjects];           // add by tanaka
    */
    
    
    // Tell the mapper if we have a support plane so that it can optimize for it.
    [_slamState.mapper setHasSupportPlane:_slamState.cameraPoseInitializer.hasSupportPlane];
    
    _slamState.tracker.initialCameraPose = _slamState.cameraPoseInitializer.cameraPose;
    
    // We will lock exposure during scanning to ensure better coloring.
    [self setColorCameraParametersForScanning];
    
    _slamState.scannerState = ScannerStateScanning;
    
    NSLog(@"enterScanningState end");
}

// 閲覧状態に実行する処理（ボタンの表示非表示の変更など）
- (void)enterViewingState
{
    NSLog(@"enterViewingState() start");          // この時点でsetMesh->uploadMeshが実行される？
    // UI -------------------------------------
    // Cannot be lost in view mode.
    [self hideTrackingErrorMessage];
    
    _appStatus.statusMessageDisabled = true;
    [self updateAppStatusMessage];
    
    // Hide the Scan/Done/Reset button.
    self.scanButton.hidden = YES;
    self.doneButton.hidden = YES;
    self.resetButton.hidden = YES;
    
    // stop sensor -----------------------------------------
    
    [_sensorController stopStreaming];

    if (_useColorCamera)
        [self stopColorCamera];
    
    // ----------------------------------------------------------
    
    [_slamState.mapper finalizeTriangleMeshWithSubsampling:1];           // tanaka //if not 1 light weight data
    
    
    STMesh *mesh = [_slamState.scene lockAndGetSceneMesh];   //original
    //[mvcRecordMeshList objectAtIndex:tIndex];
    
    //STMesh *mesh = [recordMeshList objectAtIndex:[recordMeshList count]-2];
    NSLog(@"enterViewingState set mesh start?");          // この時点でsetMesh->uploadMeshが実行される？
    [self presentMeshViewer:mesh];
    NSLog(@"enterViewingState set mesh end ?");          // この時点でsetMesh->uploadMeshが実行される？
    
    [_slamState.scene unlockSceneMesh];
    
    _slamState.scannerState = ScannerStateViewing;
    
    [self updateIdleTimer];
    
    /*
    // 最初の２コマがなぜかゴミデータなので取り除いてから次に移動させる
    [recordMeshList removeObjectsInRange:NSMakeRange(0, 2)];
    */
    
    [_meshViewController setRecordMeshList:recordMeshList]; //add by tanaka
    [_meshViewController setScanFrameDateList:scanFrameDateList]; //add by tanaka add 2016.6
    [_meshViewController setRecordMeshNum:(int)[recordMeshList count]];//add by tanaka
    [_meshViewController setScanStartDate:scanStartDate ];//add by tanaka
    
}

namespace { // anonymous namespace for utility function.
    
    float keepInRange(float value, float minValue, float maxValue)
    {
        if (isnan (value))
            return minValue;
        
        if (value > maxValue)
            return maxValue;
        
        if (value < minValue)
            return minValue;
        
        return value;
    }
    
}

// ボリュームサイズの調整
- (void)adjustVolumeSize:(GLKVector3)volumeSize
{
    // Make sure the volume size remains between 10 centimeters and 10 meters.
    // スキャンのボリュームサイズを10cmから10mの間にさせる
    volumeSize.x = keepInRange (volumeSize.x, 0.1, 10.f);
    volumeSize.y = keepInRange (volumeSize.y, 0.1, 10.f);
    volumeSize.z = keepInRange (volumeSize.z, 0.1, 10.f);
    
    _slamState.mapper.volumeSizeInMeters = volumeSize;
    
    _slamState.cameraPoseInitializer.volumeSizeInMeters = volumeSize;
    [_display.cubeRenderer adjustCubeSize:_slamState.mapper.volumeSizeInMeters
                         volumeResolution:_slamState.mapper.volumeResolution];
    
    
    // ラベル更新
    NSUInteger elements = [recordMeshList count];
    self.recFramesValueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)elements];
}

#pragma mark -  Structure Sensor Management

-(BOOL)currentStateNeedsSensor
{
    switch (_slamState.scannerState)
    {
        // Initialization and scanning need the sensor.
        case ScannerStateCubePlacement:
        case ScannerStateScanning:
            return TRUE;
            
        // Other states don't need the sensor.
        default:
            return FALSE;
    }
}

#pragma mark - IMU

// モーションセンサのセットアップ
- (void)setupIMU
{
    _lastGravity = GLKVector3Make (0,0,0);
    
    // 60 FPS is responsive enough for motion events.
    const float fps = 60.0;
    _motionManager = [[CMMotionManager alloc] init];
    _motionManager.accelerometerUpdateInterval = 1.0/fps;
    _motionManager.gyroUpdateInterval = 1.0/fps;
    
    // Limiting the concurrent ops to 1 is a simple way to force serial execution
    _imuQueue = [[NSOperationQueue alloc] init];
    [_imuQueue setMaxConcurrentOperationCount:1];
    
    __weak ViewController *weakSelf = self;
    CMDeviceMotionHandler dmHandler = ^(CMDeviceMotion *motion, NSError *error)
    {
        // Could be nil if the self is released before the callback happens.
        if (weakSelf) {
            [weakSelf processDeviceMotion:motion withError:error];
        }
    };
    
    [_motionManager startDeviceMotionUpdatesToQueue:_imuQueue withHandler:dmHandler];
}

- (void)processDeviceMotion:(CMDeviceMotion *)motion withError:(NSError *)error
{
    if (_slamState.scannerState == ScannerStateCubePlacement)
    {
        // Update our gravity vector, it will be used by the cube placement initializer.
        _lastGravity = GLKVector3Make (motion.gravity.x, motion.gravity.y, motion.gravity.z);
    }
    
    if (_slamState.scannerState == ScannerStateCubePlacement || _slamState.scannerState == ScannerStateScanning)
    {
        // The tracker is more robust to fast moves if we feed it with motion data.
        [_slamState.tracker updateCameraPoseWithMotion:motion];
    }
}

#pragma mark - UI Callbacks

// 新しいトラッカーを使うスイッチを有効にした時
- (IBAction)enableNewTrackerSwitchChanged:(id)sender
{
    // Save the volume size.
    GLKVector3 previousVolumeSize = _options.initialVolumeSizeInMeters;
    if (_slamState.initialized)
        previousVolumeSize = _slamState.mapper.volumeSizeInMeters;
    
    // Simulate a full reset to force a creation of a new tracker.
    [self resetButtonPressed:self.resetButton];
    [self clearSLAM];
    [self setupSLAM];
    
    // Restore the volume size cleared by the full reset.
    _slamState.mapper.volumeSizeInMeters = previousVolumeSize;
    [self adjustVolumeSize:_slamState.mapper.volumeSizeInMeters];
}

// 高解像度カメラを使うスイッチを有効にした時
- (IBAction)enableHighResolutionColorSwitchChanged:(id)sender
{
    if (self.avCaptureSession)
    {
        [self stopColorCamera];
        if (_useColorCamera)
            [self startColorCamera];
    }
    
    // Force a scan reset since we cannot changing the image resolution during the scan is not
    // supported by STColorizer.
    [self resetButtonPressed:self.resetButton];
}


// SCANボタンを押した時
- (IBAction)scanButtonPressed:(id)sender
{
    [self enterScanningState];
}

// リロードボタンを押した時
- (IBAction)resetButtonPressed:(id)sender
{
    recordMeshNum = 0;
    [recordMeshList removeAllObjects];
    [scanFrameDateList removeAllObjects];       // add 2016.6
    
    [self resetSLAM];

    NSUInteger elements = [recordMeshList count];
    self.recFramesValueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)elements];
}

// スキャン停止ボタン押した時
- (IBAction)doneButtonPressed:(id)sender
{
    [self enterViewingState];
}

// voxelResolutionスライダーを動かしたとき tanaka add
- (IBAction)voxelResolutionSliderChanged:(UISlider *)sender {
    int val = (int)(sender.value*1000);
    
    self.voxelResolutonValueLabel.text = [NSString stringWithFormat: @"%d", val];
    _options.initialVolumeResolutionInMeters = (float)val / 1000;
    
    
}

// scanTimesPerFrameスライダーを動かしたとき tanaka add
- (IBAction)scanTimesSliderChanged:(UISlider *)sender {
    self.scanTimesValueLabel.text = [NSString stringWithFormat: @"%d", (int)sender.value];
    
    int val = (int)(sender.value);
    scanFrameTime = val;

}


/*
// voxelResolutionスライダーを動かしたとき
- (IBAction)voxelResolutionSliderChanged:(UISlider *)sender {
}

// scanTimesPerFrameスライダーを動かしたとき
- (IBAction)scanTimesPerFrameSliderChanged:(UISlider *)sender {
}
*/


// Manages whether we can let the application sleep.
-(void)updateIdleTimer
{
    if ([self isStructureConnectedAndCharged] && [self currentStateNeedsSensor])
    {
        // Do not let the application sleep if we are currently using the sensor data.
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    }
    else
    {
        // Let the application sleep if we are only viewing the mesh or if no sensors are connected.
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    }
}

// トラッキングに関するメッセージを表示
- (void)showTrackingMessage:(NSString*)message
{
    self.trackingLostLabel.text = message;
    self.trackingLostLabel.hidden = NO;
}

- (void)hideTrackingErrorMessage
{
    self.trackingLostLabel.hidden = YES;
}

// アプリの状態に関するメッセージを表示
- (void)showAppStatusMessage:(NSString *)msg
{
    _appStatus.needsDisplayOfStatusMessage = true;
    [self.view.layer removeAllAnimations];
    
    [self.appStatusMessageLabel setText:msg];
    [self.appStatusMessageLabel setHidden:NO];
    
    // Progressively show the message label.
    // ふわっとラベル表示
    [self.view setUserInteractionEnabled:false];
    [UIView animateWithDuration:0.5f animations:^{
        self.appStatusMessageLabel.alpha = 1.0f;
    }completion:nil];
}

// アプリの状態に関するメッセージを隠す
- (void)hideAppStatusMessage
{
    if (!_appStatus.needsDisplayOfStatusMessage)
        return;
    
    _appStatus.needsDisplayOfStatusMessage = false;
    [self.view.layer removeAllAnimations];
    
    __weak ViewController *weakSelf = self;
    [UIView animateWithDuration:0.5f
                     animations:^{
                         weakSelf.appStatusMessageLabel.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         // If nobody called showAppStatusMessage before the end of the animation, do not hide it.
                         if (!_appStatus.needsDisplayOfStatusMessage)
                         {
                             // Could be nil if the self is released before the callback happens.
                             if (weakSelf) {
                                 [weakSelf.appStatusMessageLabel setHidden:YES];
                                 [weakSelf.view setUserInteractionEnabled:true];
                             }
                         }
     }];
}

// アプリの状態に関するメッセージを更新
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

// ピンチジェスチャーをした時の処理
- (void)pinchGesture:(UIPinchGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
    {
        if (_slamState.scannerState == ScannerStateCubePlacement)
        {
            _volumeScale.initialPinchScale = _volumeScale.currentScale / [gestureRecognizer scale];
        }
    }
    else if ([gestureRecognizer state] == UIGestureRecognizerStateChanged)
    {
        if(_slamState.scannerState == ScannerStateCubePlacement)
        {
            // In some special conditions the gesture recognizer can send a zero initial scale.
            if (!isnan (_volumeScale.initialPinchScale))
            {
                _volumeScale.currentScale = [gestureRecognizer scale] * _volumeScale.initialPinchScale;
                
                // Don't let our scale multiplier become absurd
                _volumeScale.currentScale = keepInRange(_volumeScale.currentScale, 0.01, 1000.f);
                
                GLKVector3 newVolumeSize = GLKVector3MultiplyScalar(_options.initialVolumeSizeInMeters, _volumeScale.currentScale);
                
                [self adjustVolumeSize:newVolumeSize];
            }
        }
    }
}

#pragma mark - MeshViewController delegates

// メッシュビューを片付ける
- (void)meshViewWillDismiss
{
    // If we are running colorize work, we should cancel it.
    if (_naiveColorizeTask)
    {
        [_naiveColorizeTask cancel];
        _naiveColorizeTask = nil;
    }
    if (_enhancedColorizeTask)
    {
        [_enhancedColorizeTask cancel];
        _enhancedColorizeTask = nil;
    }
    
    [_meshViewController hideMeshViewerMessage];
}

// メッシュビューを片付けおわったとき
- (void)meshViewDidDismiss
{
    _appStatus.statusMessageDisabled = false;
    [self updateAppStatusMessage];
    
    [self connectToStructureSensorAndStartStreaming];
    [self resetSLAM];
}

// バックグラウンドのタスクの進捗表示を更新
- (void)backgroundTask:(STBackgroundTask *)sender didUpdateProgress:(double)progress
{
    if (sender == _naiveColorizeTask)   // ネイティブの色づけタスク
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_meshViewController showMeshViewerMessage:[NSString stringWithFormat:@"Processing: % 3d%%", int(progress*20)]];
        });
    }
    else if (sender == _enhancedColorizeTask)       // 高度な色づけタスク
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_meshViewController showMeshViewerMessage:[NSString stringWithFormat:@"Processing: % 3d%%", int(progress*80)+20]];
        });
    }
}

// メッシュビューが色づけ処理を要求した時の処理
// important
- (BOOL)meshViewDidRequestColorizing:(STMesh*)mesh previewCompletionHandler:(void (^)())previewCompletionHandler enhancedCompletionHandler:(void (^)())enhancedCompletionHandler
{
    
    // ネイティブの色付け処理がすでに実行中だったら何もしない
    if (_naiveColorizeTask) // already one running?
    {
        NSLog(@"Already one colorizing task running!");
        return FALSE;
    }

    
    _naiveColorizeTask = [STColorizer
                     newColorizeTaskWithMesh:mesh
                     scene:_slamState.scene
                     keyframes:[_slamState.keyFrameManager getKeyFrames]
                     completionHandler: ^(NSError *error)
                     {
                         if (error != nil) {
                             NSLog(@"Error during colorizing: %@", [error localizedDescription]);
                         }
                         else
                         {
                             
                             /*
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 previewCompletionHandler();
                                 _meshViewController.mesh = mesh;
                                 
                                 // [self performEnhancedColorize:(STMesh*)mesh enhancedCompletionHandler:enhancedCompletionHandler];  //comment out by tanaka 
                             });
                             */
                             
                             _naiveColorizeTask = nil;
                         }
                     }
                          /*
                     options:@{kSTColorizerTypeKey: @(STColorizerPerVertex),
                               kSTColorizerPrioritizeFirstFrameColorKey: @(_options.prioritizeFirstFrameColor)}
                           */
                          
                          options:@{kSTColorizerTypeKey: @(STColorizerTextureMapForObject),
                                    kSTColorizerPrioritizeFirstFrameColorKey: @(_options.prioritizeFirstFrameColor),
                                    kSTColorizerQualityKey: @(STColorizerNormalQuality)
                                    }

                     error:nil];
    
    /*
     typedef NS_ENUM(NSInteger, STColorizerType ) {
     STColorizerPerVertex = 0,
     STColorizerTextureMapForRoom,
     STColorizerTextureMapForObject,
     };
     typedef NS_ENUM(NSInteger, STColorizerQuality ) {
     STColorizerUltraHighQuality = 0,
     STColorizerHighQuality,
     STColorizerNormalQuality,
     };

     */

    // 色付けタスクの作成に成功していたら、タスクを実行？
    if (_naiveColorizeTask)     // 素朴な色付けタスク?
    {
        _naiveColorizeTask.delegate = self;
        [_naiveColorizeTask start];
        return TRUE;
    }
 
    
    return FALSE;
}

// さらに向上した色づけを実行
- (void)performEnhancedColorize:(STMesh*)mesh enhancedCompletionHandler:(void (^)())enhancedCompletionHandler
{
    return;
    _enhancedColorizeTask =[STColorizer
       newColorizeTaskWithMesh:mesh
       scene:_slamState.scene
       keyframes:[_slamState.keyFrameManager getKeyFrames]
       completionHandler: ^(NSError *error)
       {
           if (error != nil) {
               NSLog(@"Error during colorizing: %@", [error localizedDescription]);
           }
           else
           {
               dispatch_async(dispatch_get_main_queue(), ^{
                   enhancedCompletionHandler();
                   _meshViewController.mesh = mesh;
               });
               _enhancedColorizeTask = nil;
           }
       }
       options:@{kSTColorizerTypeKey: @(STColorizerTextureMapForObject),
                 kSTColorizerPrioritizeFirstFrameColorKey: @(_options.prioritizeFirstFrameColor),
                 kSTColorizerQualityKey: @(_options.colorizerQuality),
                 kSTColorizerTargetNumberOfFacesKey: @(_options.colorizerTargetNumFaces)} // 20k faces is enough for most objects.
       error:nil];
    
    if (_enhancedColorizeTask)
    {
        // We don't need the keyframes anymore now that the final colorizing task was started.
        // Clearing it now gives a chance to early release the keyframe memory when the colorizer
        // stops needing them.
        [_slamState.keyFrameManager clear];
        
        /* comment out by tanaka
        _enhancedColorizeTask.delegate = self;
        [_enhancedColorizeTask start];
         */
    }
}


// メモリ警告への応答
- (void) respondToMemoryWarning
{
    switch( _slamState.scannerState )
    {
        case ScannerStateViewing:
        {
            // If we are running a colorizing task, abort it
            if( _enhancedColorizeTask != nil && !_slamState.showingMemoryWarning )
            {
                _slamState.showingMemoryWarning = true;
                
                // stop the task
                [_enhancedColorizeTask cancel];
                _enhancedColorizeTask = nil;
                
                // hide progress bar
                [_meshViewController hideMeshViewerMessage];
                
                UIAlertController *alertCtrl= [UIAlertController alertControllerWithTitle:@"Memory Low"
                                                                                  message:@"Colorizing was canceled."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action)
                                           {
                                               _slamState.showingMemoryWarning = false;
                                           }];
                
                [alertCtrl addAction:okAction];
                
                // show the alert in the meshViewController
                [_meshViewController presentViewController:alertCtrl animated:YES completion:nil];
            }
            
            break;
        }
        case ScannerStateScanning:
        {
            if( !_slamState.showingMemoryWarning )
            {
                _slamState.showingMemoryWarning = true;
                
                UIAlertController *alertCtrl= [UIAlertController alertControllerWithTitle:@"Memory Low"
                                                                                  message:@"Scanning will be stopped to avoid loss."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action)
                                           {
                                               _slamState.showingMemoryWarning = false;
                                               [self enterViewingState];
                                           }];
                
                
                [alertCtrl addAction:okAction];
                
                // show the alert
                [self presentViewController:alertCtrl animated:YES completion:nil];
            }
            
            break;
        }
        default:
        {
            // not much we can do here
        }
    }
    
}


- (void)receiveUdpData:(NSData *)data {
    NSString *receivedData =  [[NSString alloc] initWithData:data
                                                    encoding:NSUTF8StringEncoding];
    // receivedDataがlength:12のデータになっているので、Length:4に変換する
    char *recvChars = (char *) [receivedData UTF8String];
    receivedData = [NSString stringWithCString: recvChars encoding:NSUTF8StringEncoding];

    NSLog(@"ViewController::receiveUdpData: %@", receivedData);

    
    //NSString *mes = [NSString stringWithFormat:@"2Received UDP: %@, A B2", receivedData];
    NSString *mes = [NSString stringWithFormat:@"2Received UDP: %@, ", receivedData];
    
    //NSLog(@"rData length: %lu", (unsigned long)[receivedData length]);
    
    _receivedMessageUDPLabel.text = mes;
    
    if ([receivedData compare:@"scan"] == NSOrderedSame){
        
        if (_slamState.scannerState == ScannerStateCubePlacement) {
            NSLog(@"Remote SCAN --------------------------");
            [self enterScanningState];
            AudioServicesPlaySystemSound(soundIdScan);
        } else {
            AudioServicesPlaySystemSound(soundIdError);
        }
        
    } else if ([receivedData compare:@"scan_stop"] == NSOrderedSame) {
        if (_slamState.scannerState == ScannerStateScanning) {
            NSLog(@"Remote SCAN_STOP --------------------------");
            [self enterViewingState];
            AudioServicesPlaySystemSound(soundIdScanStop);
        } else {
            AudioServicesPlaySystemSound(soundIdError);
        
        }
        
    } else if ([receivedData compare:@"scan_reload"] == NSOrderedSame) {
        
        if (_slamState.scannerState == ScannerStateScanning) {

            NSLog(@"Remote SCAN_RELOAD --------------------------");
            AudioServicesPlaySystemSound(soundIdScanReload);

            [self resetButtonPressed:self];

            //[self resetSLAM];
        
        } else {
            AudioServicesPlaySystemSound(soundIdError);
        }
        
    } else {
        
        if (_slamState.scannerState == ScannerStateScanning) {
            
            AudioServicesPlaySystemSound(soundIdStateScanning);
            
        } else if (_slamState.scannerState == ScannerStateCubePlacement) {
            
            AudioServicesPlaySystemSound(soundIdStateCubeSetting);
            
        } else if (_slamState.scannerState == ScannerStateViewing) {
            
            AudioServicesPlaySystemSound(soundIdStateViewing);
            
        }
        
    }

}

@end

/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolBox/AudioToolBox.h>
#define HAS_LIBCXX
#import <Structure/Structure.h>


#import "CalibrationOverlay.h"
#import "MeshViewController.h"

#import "MyUdpConnection.h" // ogawa add




/*
@interface STMeshSerial : STMesh {

}
@end
*/


// オプション情報の構造体
struct Options
{
    // The initial scanning volume size will be 0.5 x 0.5 x 0.5 meters
    // (X is left-right, Y is up-down, Z is forward-back)
    // 初期スキャニングサイズ 0.5m 角
    GLKVector3 initialVolumeSizeInMeters = GLKVector3Make (0.5f, 0.5f, 0.5f);
    
    // Volume resolution in meters
    // 初期の1voxelあたりのボリューム解像度をメートル単位で tanaka important!
    float initialVolumeResolutionInMeters = 0.006; // default: 4 mm per voxel   Max:2mm?  10mm: very fast!(Low reso)
    
    // The maximum number of keyframes saved in keyFrameManager
    int maxNumKeyFrames = 48;
    
    // Colorizer quality
    //STColorizerQuality colorizerQuality = STColorizerHiNormalHighQuality;  //default
    STColorizerQuality colorizerQuality = STColorizerUltraHighQuality;
    
    // Take a new keyframe in the rotation difference is higher than 20 degrees.
    float maxKeyFrameRotation = 20.0f * (M_PI / 180.f); // 20 degrees
    
    // Take a new keyframe if the translation difference is higher than 30 cm.
    float maxKeyFrameTranslation = 0.3; // 30cm

    // Threshold to consider that the rotation motion was small enough for a frame to be accepted
    // as a keyframe. This avoids capturing keyframes with strong motion blur / rolling shutter.
    float maxKeyframeRotationSpeedInDegreesPerSecond = 1.f;
    
    // Whether we should use depth aligned to the color viewpoint when Structure Sensor was calibrated.
    // This setting may get overwritten to false if no color camera can be used.
    bool useHardwareRegisteredDepth = true;
        
    // Whether the colorizer should try harder to preserve appearance of the first keyframe.
    // Recommended for face scans.
    bool prioritizeFirstFrameColor = true;
    
    // Target number of faces of the final textured mesh.
    int colorizerTargetNumFaces = 50000;
    
    // Focus position for the color camera (between 0 and 1). Must remain fixed one depth streaming
    // has started when using hardware registered depth.
    const float lensPosition = 0.75f;
};

// スキャナーの状態を表す定数
enum ScannerState
{
    // Defining the volume to scan
    ScannerStateCubePlacement = 0,
    
    // Scanning
    ScannerStateScanning,
    
    // Visualizing the mesh
    ScannerStateViewing,
    
    NumStates
};

// SLAM-related members.
struct SlamData
{
    SlamData ()
    : initialized (false)
    , scannerState (ScannerStateCubePlacement)
    {}
    
    BOOL initialized;
    BOOL showingMemoryWarning = false;
    
    NSTimeInterval prevFrameTimeStamp = -1.0;
    
    STScene *scene;
    STTracker *tracker;
    STMapper *mapper;
    STCameraPoseInitializer *cameraPoseInitializer;
    STKeyFrameManager *keyFrameManager;
    ScannerState scannerState;
};

// Utility struct to manage a gesture-based scale.
struct PinchScaleState
{
    PinchScaleState ()
    : currentScale (1.f)
    , initialPinchScale (1.f)
    {}
    
    float currentScale;
    float initialPinchScale;
};

// アプリの状態を格納する構造体
struct AppStatus
{
    NSString* const pleaseConnectSensorMessage = @"Please connect Structure Sensor.";
    NSString* const pleaseChargeSensorMessage = @"Please charge Structure Sensor.";
    NSString* const needColorCameraAccessMessage = @"This app requires camera access to capture color.\nAllow access by going to Settings → Privacy → Camera.";
    
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

// 表示関係の構造体のメンバ変数
// Display related members.
struct DisplayData
{
    DisplayData ()
    {
    }
    
    ~DisplayData ()
    {
        if (lumaTexture)
        {
            CFRelease (lumaTexture);
            lumaTexture = NULL;
        }
        
        if (chromaTexture)
        {
            CFRelease (chromaTexture);
            lumaTexture = NULL;
        }
        
        if (videoTextureCache)
        {
            CFRelease(videoTextureCache);
            videoTextureCache = NULL;
        }
    }
    
    // OpenGL context.
    EAGLContext *context;
    
    // OpenGL Texture reference for y images.
    CVOpenGLESTextureRef lumaTexture;
    
    // OpenGL Texture reference for color images.
    CVOpenGLESTextureRef chromaTexture;
    
    // OpenGL Texture cache for the color camera.
    CVOpenGLESTextureCacheRef videoTextureCache;
    
    // Shader to render a GL texture as a simple quad.
    STGLTextureShaderYCbCr *yCbCrTextureShader;
    STGLTextureShaderRGBA *rgbaTextureShader;
    
    GLuint depthAsRgbaTexture;
    
    // Renders the volume boundaries as a cube.
    STCubeRenderer *cubeRenderer;
    
    // OpenGL viewport.
    GLfloat viewport[4];
    
    // OpenGL projection matrix for the color camera.
    GLKMatrix4 colorCameraGLProjectionMatrix = GLKMatrix4Identity;
    
    // OpenGL projection matrix for the depth camera.
    GLKMatrix4 depthCameraGLProjectionMatrix = GLKMatrix4Identity;
};

// ビューコントローラのインターフェース宣言
@interface ViewController : UIViewController <STBackgroundTaskDelegate, MeshViewDelegate, UIPopoverControllerDelegate, UIGestureRecognizerDelegate,
    UITableViewDataSource, UITableViewDelegate  // tanaka add
    >
{
    // Structure Sensor controller.
    STSensorController *_sensorController;
    STStreamConfig _structureStreamConfig;
    
    SlamData _slamState;
    
    Options _options;
    
    // Manages the app status messages.
    AppStatus _appStatus;
    
    DisplayData _display;
    
    // Most recent gravity vector from IMU.
    GLKVector3 _lastGravity;
    
    // Scale of the scanning volume.
    PinchScaleState _volumeScale;

    // Mesh viewer controllers.
    UINavigationController *_meshViewNavigationController;
    MeshViewController *_meshViewController;
    
    // IMU handling.
    CMMotionManager *_motionManager;
    NSOperationQueue *_imuQueue;
    
    STBackgroundTask* _naiveColorizeTask;
    STBackgroundTask* _enhancedColorizeTask;
    STDepthToRgba *_depthAsRgbaVisualizer;
    
    bool _useColorCamera;
    
    CalibrationOverlay* _calibrationOverlay;
    
    
    GLuint vertexBufferID; // add by tanaka
    int scanFrameTime; // add by tanaka
    int scanFrameCount; // add by tanaka
    
    int recordMeshNum; // add by tanaka
    NSMutableArray *recordMeshList; // add by tanaka
    NSMutableArray *scanFrameDateList;
    
    //STMesh *recordMeshList;
    
    NSFileManager *fileManager;
    NSMutableArray *fileList;
    NSString *filePath;
    NSString *basePath;
    
    NSDate *scanStartDate;
    NSDate *scanNowDate;
    
    SystemSoundID soundIdScan;
    SystemSoundID soundIdScanStop;
    SystemSoundID soundIdScanReload;
    SystemSoundID soundIdPlay;
    SystemSoundID soundIdSave;
    SystemSoundID soundIdBackToScan;
    SystemSoundID soundIdError;
    SystemSoundID soundIdIcant;
    SystemSoundID soundIdStateScanning;
    SystemSoundID soundIdStateCubeSetting;
    SystemSoundID soundIdStateViewing;

}

@property (nonatomic, retain) AVCaptureSession *avCaptureSession;
@property (nonatomic, retain) AVCaptureDevice *videoDevice;

@property (weak, nonatomic) IBOutlet UILabel *appStatusMessageLabel;
@property (weak, nonatomic) IBOutlet UIButton *scanButton;
@property (weak, nonatomic) IBOutlet UIButton *resetButton;
@property (weak, nonatomic) IBOutlet UIButton *doneButton;
@property (weak, nonatomic) IBOutlet UILabel *trackingLostLabel;
@property (weak, nonatomic) IBOutlet UISwitch *enableNewTrackerSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *enableHighResolutionColorSwitch;
@property (weak, nonatomic) IBOutlet UIView *enableNewTrackerView;


// tanaka add
@property (weak, nonatomic) IBOutlet UILabel *voxelResolutonValueLabel;
@property (weak, nonatomic) IBOutlet UILabel *scanTimesValueLabel;
@property (weak, nonatomic) IBOutlet UILabel *recFramesValueLabel;
@property (weak, nonatomic) IBOutlet UILabel *debugTraceLabel;

// ogawa add
@property (weak, nonatomic) IBOutlet UILabel *renderUdpData;

@property (weak, nonatomic) IBOutlet UILabel *receivedMessageUDPLabel;


- (IBAction)voxelResolutionSliderChanged:(UISlider *)sender;
- (IBAction)scanTimesSliderChanged:(UISlider *)sender;

/*
@property (weak, nonatomic) IBOutlet UISlider *voxelResolutionSlider;
@property (weak, nonatomic) IBOutlet UISlider *scanTimesPerFrameSlider;
 */


// UI関連
- (IBAction)enableNewTrackerSwitchChanged:(id)sender;
- (IBAction)enableHighResolutionColorSwitchChanged:(id)sender;
- (IBAction)scanButtonPressed:(id)sender;
- (IBAction)resetButtonPressed:(id)sender;
- (IBAction)doneButtonPressed:(id)sender;
- (IBAction)loadButtonPressed:(id)sender;
/*
- (IBAction)voxelResolutionSliderChanged:(UISlider *)sender;
- (IBAction)scanTimesPerFrameSliderChanged:(UISlider *)sender;
 */


- (void)enterCubePlacementState;
- (void)enterScanningState;
- (void)enterViewingState;
- (void)adjustVolumeSize:(GLKVector3)volumeSize;
- (void)updateAppStatusMessage;
- (BOOL)currentStateNeedsSensor;
- (void)updateIdleTimer;
- (void)showTrackingMessage:(NSString*)message;
- (void)hideTrackingErrorMessage;
- (void)processDeviceMotion:(CMDeviceMotion *)motion withError:(NSError *)error;

// ogawa add
- (void)receiveUdpData:(NSData *)data;


@end

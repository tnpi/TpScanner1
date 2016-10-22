/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>
#import <MessageUI/MFMailComposeViewController.h>
#import <Structure/StructureSLAM.h>
#import "EAGLView.h"

#import "MyUdpConnection.h" // ogawa add


@protocol MeshViewDelegate <NSObject>
- (void)meshViewWillDismiss;
- (void)meshViewDidDismiss;
- (BOOL)meshViewDidRequestColorizing:(STMesh*)mesh
            previewCompletionHandler:(void(^)(void))previewCompletionHandler
           enhancedCompletionHandler:(void(^)(void))enhancedCompletionHandler;
@end

@interface MeshViewController : UIViewController <UIGestureRecognizerDelegate, MFMailComposeViewControllerDelegate> {

    int playMeshCounter;
    bool playbackFlag;
    int playbackFrameCounter;
    int playbackFrame;
    int savedMeshNum;
    int gestureAreaHeight;
    
    NSDate *scanStartDate;
    
    NSMutableArray *mvcRecordMeshList;
    NSMutableArray *mvcScanFrameDateList;        // add 2016.6
    
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
    
//@public
    //int recordMeshNum;
}

@property (nonatomic, assign) id<MeshViewDelegate> delegate;

@property (nonatomic) BOOL needsDisplay; // force the view to redraw.
@property (nonatomic) int recordMeshNum;
@property (nonatomic) BOOL colorEnabled;
@property (nonatomic) STMesh * mesh;

@property (weak, nonatomic) IBOutlet UISegmentedControl *displayControl;
@property (weak, nonatomic) IBOutlet UILabel *meshViewerMessageLabel;
@property (weak, nonatomic) IBOutlet UISlider *playbackRecordTimeSlider;
@property (weak, nonatomic) IBOutlet UILabel *playbackRecordTimeValueLabel;
@property (strong, nonatomic) IBOutletCollection(UILabel) NSArray *playbackRecordMaxTime;
@property (weak, nonatomic) IBOutlet UILabel *debugTraceLabelMV;
@property (weak, nonatomic) IBOutlet UILabel *saveRecordMeshNumLabel;
@property (weak, nonatomic) IBOutlet UILabel *allRecordMeshNumLabel;
@property (weak, nonatomic) IBOutlet UISwitch *loopPlaySwitch;

@property (weak, nonatomic) IBOutlet UILabel *recordMeshNumLabel;

@property (weak, nonatomic) IBOutlet UILabel *diskSpaceLabel;
@property (weak, nonatomic) IBOutlet UILabel *maxDiskSpaceLabel;
// ogawa add
@property (weak, nonatomic) IBOutlet UILabel *renderUdpData;
@property (weak, nonatomic) IBOutlet UILabel *receivedMessageUDPLabel;


- (IBAction)displayControlChanged:(id)sender;
- (IBAction)playRecordButtonPressed:(UIButton *)sender;
- (IBAction)stopRecordButtonPressed:(UIButton *)sender;
- (IBAction)backRecordButtonPressed:(UIButton *)sender;
- (IBAction)playbackRecordTimeSliderChange:(UISlider *)sender;
- (IBAction)mvcSaveButtonPressed:(id)sender;

- (IBAction)loopPlaySwitchPressed:(id)sender;

- (void)updateFrame:(NSTimer*)timer;
- (void)showMeshViewerMessage:(NSString *)msg;
- (void)hideMeshViewerMessage;

- (void)setCameraProjectionMatrix:(GLKMatrix4)projRt;
- (void)resetMeshCenter:(GLKVector3)center;

- (void)setupGL:(EAGLContext*)context;
- (void)setRecordMeshList:(NSMutableArray*)context;
- (void)setScanFrameDateList:(NSMutableArray*)context;  // add 2016.6
- (void)setScanStartDate:(NSDate*)date;
//- (void)setMeshB:(STMesh *)meshRef;

// ogawa add
- (void)receiveUdpData:(NSData *)data;


@end

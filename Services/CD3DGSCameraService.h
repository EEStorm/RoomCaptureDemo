#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^CD3DGSCameraPermissionResult)(BOOL granted, NSError * _Nullable error);
typedef void(^CD3DGSCameraBlurStatusHandler)(NSInteger blurState, double blurVariance);
FOUNDATION_EXPORT NSString * const CD3DGSCameraDidFinishRecordingNotification;
FOUNDATION_EXPORT NSString * const CD3DGSCameraRecordingURLKey;

@interface CD3DGSCameraService : NSObject

@property (nonatomic, readonly) BOOL isRecording;
@property (nonatomic, readonly) NSTimeInterval recordingDuration;
@property (nonatomic, readonly) NSArray<NSURL *> *recordedVideos;
@property (nonatomic, readonly) BOOL parametersLocked;
@property (nonatomic, copy, readonly) NSString *parametersLockSummary;
@property (nonatomic, copy, nullable) CD3DGSCameraBlurStatusHandler blurStatusHandler;

+ (instancetype)shared;

- (void)checkCameraPermissionWithResult:(CD3DGSCameraPermissionResult)result;
- (AVCaptureVideoPreviewLayer * _Nullable)setupCamera;
- (void)startSession;
- (void)startSessionWithCompletion:(void(^ _Nullable)(void))completion;
- (void)stopSession;
- (void)stopSessionWithCompletion:(void(^ _Nullable)(void))completion;
- (void)teardownCameraWithCompletion:(void(^ _Nullable)(void))completion;
- (void)startRecording;
- (void)stopRecording;
- (void)deleteVideoAtURL:(NSURL *)url;
- (void)deleteAllVideos;

@end

NS_ASSUME_NONNULL_END

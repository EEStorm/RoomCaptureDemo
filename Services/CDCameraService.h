#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^CDCameraPermissionResult)(BOOL granted, NSError * _Nullable error);

@interface CDCameraService : NSObject

@property (nonatomic, readonly) BOOL isRecording;
@property (nonatomic, readonly) NSTimeInterval recordingDuration;
@property (nonatomic, readonly) NSArray<NSURL *> *recordedVideos;

+ (instancetype)shared;

- (void)checkCameraPermissionWithResult:(CDCameraPermissionResult)result;
- (AVCaptureVideoPreviewLayer * _Nullable)setupCamera;
- (void)startSession;
- (void)stopSession;
- (void)startRecording;
- (void)stopRecording;
- (void)deleteVideoAtURL:(NSURL *)url;
- (void)deleteAllVideos;
- (NSURL *)getVideoDirectory;

@end

NS_ASSUME_NONNULL_END

#import "CDCameraService.h"
#import <AVFoundation/AVFoundation.h>

@interface CDCameraService () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDevice *videoDevice;
@property (nonatomic, strong) AVCaptureMovieFileOutput *videoOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) NSTimer *recordingTimer;
@property (nonatomic, strong, nullable) NSURL *currentVideoURL;

@property (nonatomic, assign) int32_t targetFrameRate;
@property (nonatomic, assign) float whiteBalanceTemperature;
@property (nonatomic, assign) CMTime shutterDuration;
@property (nonatomic, assign) float targetISO;

@end

@implementation CDCameraService

+ (instancetype)shared {
    static CDCameraService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CDCameraService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _targetFrameRate = 30;
        _whiteBalanceTemperature = 4500.0f;
        _shutterDuration = CMTimeMake(1, 250);
        _targetISO = 320.0f;
        [self loadRecordedVideos];
    }
    return self;
}

- (AVCaptureVideoPreviewLayer *)setupCamera {
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];

    if ([session canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        session.sessionPreset = AVCaptureSessionPreset1920x1080;
    }

    AVCaptureDevice *device = [self findCameraDevice];
    if (!device) {
        NSLog(@"Error: cannot find camera");
        return nil;
    }
    self.videoDevice = device;

    [self configureDevice:device];

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error) {
        NSLog(@"Error adding input: %@", error.localizedDescription);
        return nil;
    }
    if ([session canAddInput:input]) {
        [session addInput:input];
    }

    AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
    if ([session canAddOutput:output]) {
        [session addOutput:output];
    }
    self.videoOutput = output;

    [session commitConfiguration];

    AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
    preview.videoGravity = AVLayerVideoGravityResizeAspectFill;

    self.captureSession = session;
    self.previewLayer = preview;

    NSLog(@"Camera setup complete. Device: %@", device.localizedName);
    NSLog(@"ISO range: [%.0f, %.0f]", device.activeFormat.minISO, device.activeFormat.maxISO);

    return preview;
}

- (AVCaptureDevice *)findCameraDevice {
    AVCaptureDevice *device = nil;

    // Try to find ultra-wide camera (0.5x)
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInUltraWideCamera]
        mediaType:AVMediaTypeVideo
        position:AVCaptureDevicePositionBack];

    if (discovery.devices.count > 0) {
        device = discovery.devices.firstObject;
        NSLog(@"Found ultra-wide camera: %@", device.localizedName);
    }

    // Fallback to wide-angle camera
    if (!device) {
        device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                    mediaType:AVMediaTypeVideo
                                                 position:AVCaptureDevicePositionBack];
        NSLog(@"Using wide-angle camera: %@", device.localizedName);
    }

    return device;
}

- (void)configureDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    [device lockForConfiguration:&error];
    if (error) {
        NSLog(@"lockForConfiguration error: %@", error.localizedDescription);
        return;
    }

    // Set frame rate
    CMTime frameDuration = CMTimeMake(1, self.targetFrameRate);
    device.activeVideoMinFrameDuration = frameDuration;
    device.activeVideoMaxFrameDuration = frameDuration;

    // Set shutter and ISO
    float minISO = device.activeFormat.minISO;
    float maxISO = device.activeFormat.maxISO;
    float iso = self.targetISO;
    if (iso < minISO) iso = minISO;
    if (iso > maxISO) iso = maxISO;

    if ([device isExposureModeSupported:AVCaptureExposureModeCustom]) {
        [device setExposureModeCustomWithDuration:self.shutterDuration ISO:iso completionHandler:nil];
    }

    // Set white balance
    if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
        AVCaptureWhiteBalanceTemperatureAndTintValues tempAndTint;
        tempAndTint.temperature = self.whiteBalanceTemperature;
        tempAndTint.tint = 0;
        AVCaptureWhiteBalanceGains gains = [device deviceWhiteBalanceGainsForTemperatureAndTintValues:tempAndTint];
        float maxGain = device.maxWhiteBalanceGain;
        gains.redGain = MAX(1.0f, MIN(maxGain, gains.redGain));
        gains.greenGain = MAX(1.0f, MIN(maxGain, gains.greenGain));
        gains.blueGain = MAX(1.0f, MIN(maxGain, gains.blueGain));
        [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:nil];
    }

    // Lock focus
    if ([device isFocusModeSupported:AVCaptureFocusModeLocked]) {
        device.focusMode = AVCaptureFocusModeLocked;
    }

    [device unlockForConfiguration];

    NSLog(@"Camera configured: 1920x1080, %dfps, WB=%.0fK, ISO=%.0f",
          self.targetFrameRate, self.whiteBalanceTemperature, iso);
}

- (void)startSession {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.captureSession startRunning];
    });
}

- (void)stopSession {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.captureSession stopRunning];
    });
}

- (BOOL)isRecording {
    BOOL recording = [self.videoOutput isRecording];
    NSLog(@"isRecording check: %d", recording);
    return recording;
}

- (void)startRecording {
    NSLog(@"startRecording called, isRecording: %d", [self.videoOutput isRecording]);
    if ([self.videoOutput isRecording]) {
        NSLog(@"Already recording, ignoring");
        return;
    }

    if (!self.videoOutput) {
        NSLog(@"ERROR: videoOutput is nil!");
        return;
    }

    NSURL *videosDir = [self getVideoDirectory];
    [[NSFileManager defaultManager] createDirectoryAtURL:videosDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSString *fileName = [NSString stringWithFormat:@"CAP_%lld.mp4", (long long)timestamp];
    NSURL *fileURL = [videosDir URLByAppendingPathComponent:fileName];
    self.currentVideoURL = fileURL;

    [self.videoOutput startRecordingToOutputFileURL:fileURL recordingDelegate:self];

    self->_recordingDuration = 0;
    [self startRecordingTimer];
}

- (void)stopRecording {
    NSLog(@"stopRecording called, currently recording: %d", [self.videoOutput isRecording]);
    if (![self.videoOutput isRecording]) {
        NSLog(@"Not recording, ignoring stop");
        return;
    }
    NSLog(@"Calling stopRecording on videoOutput");
    [self.videoOutput stopRecording];
    [self stopRecordingTimer];
    NSLog(@"stopRecording completed");
}

- (void)startRecordingTimer {
    self.recordingTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                           target:self
                                                         selector:@selector(updateDuration)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)stopRecordingTimer {
    [self.recordingTimer invalidate];
    self.recordingTimer = nil;
}

- (void)updateDuration {
    self->_recordingDuration += 0.1;
}

- (void)captureOutput:(AVCaptureFileOutput *)output
didFinishRecordingToOutputFileAtURL:(NSURL *)fileURL
        fromConnections:(NSArray<AVCaptureConnection *> *)connections
                  error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"captureOutput callback, error: %@", error);
        if (error) {
            NSLog(@"Recording error: %@", error.localizedDescription);
        } else {
            NSLog(@"Recording saved: %@", fileURL);
            [self loadRecordedVideos];
        }
    });
}

- (void)loadRecordedVideos {
    NSURL *videosDir = [self getVideoDirectory];
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:videosDir
                                                          includingPropertiesForKeys:nil
                                                                     options:0
                                                                       error:&error];
    if (error) {
        _recordedVideos = @[];
        return;
    }

    NSMutableArray *videos = [NSMutableArray array];
    for (NSURL *url in files) {
        if ([[url pathExtension] isEqualToString:@"mp4"]) {
            [videos addObject:url];
        }
    }

    _recordedVideos = [videos sortedArrayUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
        NSDate *d1 = [self creationDate:url1];
        NSDate *d2 = [self creationDate:url2];
        return [d2 compare:d1];
    }];
}

- (NSDate *)creationDate:(NSURL *)url {
    NSDate *date = nil;
    [url getResourceValue:&date forKey:NSURLCreationDateKey error:nil];
    return date ?: [NSDate distantPast];
}

- (void)deleteVideoAtURL:(NSURL *)url {
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    NSMutableArray *arr = [self.recordedVideos mutableCopy];
    [arr removeObject:url];
    _recordedVideos = arr;
}

- (void)deleteAllVideos {
    NSURL *videosDir = [self getVideoDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:videosDir
                                                  includingPropertiesForKeys:nil
                                                                     options:0
                                                                       error:nil];
    for (NSURL *url in files) {
        if ([[url pathExtension] isEqualToString:@"mp4"]) {
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        }
    }
    _recordedVideos = @[];
}

- (NSURL *)getVideoDirectory {
    NSURL *docURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                             inDomains:NSUserDomainMask] firstObject];
    return [docURL URLByAppendingPathComponent:@"Videos" isDirectory:YES];
}

@end

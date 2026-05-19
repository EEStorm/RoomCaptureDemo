#import "CD3DGSCameraService.h"
#import "CaptureDemo-Swift.h"
#import <AVFoundation/AVFoundation.h>

static NSString * const kCD3DGSCameraDidReloadNotification = @"CD3DGSCameraDidReload";
static NSString * const kCD3DGSCameraExposureDidAutoLockNotification = @"CD3DGSCameraExposureDidAutoLock";
static NSString * const kCD3DGSCameraParametersLockDidChangeNotification = @"CD3DGSCameraParametersLockDidChange";
NSString * const CD3DGSCameraDidFinishRecordingNotification = @"CD3DGSCameraDidFinishRecordingNotification";
NSString * const CD3DGSCameraRecordingURLKey = @"CD3DGSCameraRecordingURLKey";

@interface CD3DGSCameraService () <AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDevice *videoDevice;
@property (nonatomic, strong) AVCaptureMovieFileOutput *videoOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) NSTimer *recordingTimer;
@property (nonatomic, strong) NSTimer *lockMonitorTimer;
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) CD3DGSBlurMonitor *blurMonitor;
@property (nonatomic, assign) NSInteger currentBlurState;
@property (nonatomic, assign) NSUInteger blurAnalysisFrameCount;
@property (nonatomic, strong, nullable) NSURL *currentVideoURL;

@property (nonatomic, assign) int32_t targetFrameRate;
@property (nonatomic, assign) float whiteBalanceTemperature;
@property (nonatomic, assign) CMTime shutterDuration;
@property (nonatomic, assign) float targetISO;
@property (nonatomic, assign) NSInteger exposureMode;
@property (nonatomic, assign) NSTimeInterval autoLockSettleSeconds;
@property (nonatomic, assign) NSInteger currentCameraLens;
@property (nonatomic, assign) NSUInteger exposureAutoLockGeneration;

@property (nonatomic, assign) BOOL parametersLocked;
@property (nonatomic, copy) NSString *parametersLockSummary;

@end

@implementation CD3DGSCameraService

+ (instancetype)shared {
    static CD3DGSCameraService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CD3DGSCameraService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _parametersLocked = YES;
        _parametersLockSummary = @"参数已应用";
        [self loadSettings];
        [self loadRecordedVideos];
        _blurAnalysisFrameCount = 0;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(settingsDidChange:)
                                                     name:@"CDCameraSettingsDidChange"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.lockMonitorTimer invalidate];
}

- (void)checkCameraPermissionWithResult:(CD3DGSCameraPermissionResult)result {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        result(YES, nil);
        return;
    }
    if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) {
        NSError *error = [NSError errorWithDomain:@"CD3DGSCameraService"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Camera permission denied"}];
        result(NO, error);
        return;
    }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            result(granted, granted ? nil : [NSError errorWithDomain:@"CD3DGSCameraService"
                                                               code:2
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Camera permission not granted"}]);
        });
    }];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _targetFrameRate = (int32_t)[defaults integerForKey:@"CDSettingsFrameRate"];
    if (_targetFrameRate == 0) _targetFrameRate = 30;

    _whiteBalanceTemperature = [defaults floatForKey:@"CDSettingsWhiteBalance"];
    if (_whiteBalanceTemperature == 0) _whiteBalanceTemperature = 4500.0f;

    float shutterSpeed = [defaults floatForKey:@"CDSettingsShutterSpeed"];
    if (shutterSpeed == 0) shutterSpeed = 250;
    _shutterDuration = CMTimeMake(1, (int32_t)shutterSpeed);

    _targetISO = [defaults floatForKey:@"CDSettingsISO"];
    if (_targetISO == 0) _targetISO = 320.0f;

    id exposureModeObj = [defaults objectForKey:@"CDSettingsExposureMode"];
    if (exposureModeObj == nil) {
        BOOL legacyISOAuto = [defaults boolForKey:@"CDSettingsISOAuto"];
        _exposureMode = legacyISOAuto ? 1 : 0;
    } else {
        _exposureMode = [defaults integerForKey:@"CDSettingsExposureMode"];
    }

    _autoLockSettleSeconds = [defaults doubleForKey:@"CDSettingsAutoLockSettleSeconds"];
    if (_autoLockSettleSeconds <= 0) _autoLockSettleSeconds = 1.0;

    _currentCameraLens = [defaults integerForKey:@"CDSettingsCameraLens"];
}

- (void)settingsDidChange:(NSNotification *)notification {
    NSInteger oldLens = self.currentCameraLens;
    [self loadSettings];
    NSInteger newLens = self.currentCameraLens;

    if (oldLens != newLens) {
        [self reloadCamera];
    } else if (self.captureSession && self.videoDevice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self configureDevice:self.videoDevice];
            [[NSNotificationCenter defaultCenter] postNotificationName:kCD3DGSCameraDidReloadNotification object:nil];
        });
    }
}

- (void)reloadCamera {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.captureSession stopRunning];

        for (AVCaptureInput *input in self.captureSession.inputs) {
            [self.captureSession removeInput:input];
        }

        AVCaptureDevice *newDevice = [self findCameraDevice];
        if (!newDevice) {
            NSLog(@"Error: cannot find camera device");
            return;
        }

        NSError *error = nil;
        AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&error];
        if (error) {
            NSLog(@"Error creating input: %@", error.localizedDescription);
            return;
        }

        [self.captureSession beginConfiguration];
        if ([self.captureSession canAddInput:newInput]) {
            [self.captureSession addInput:newInput];
        }
        [self.captureSession commitConfiguration];

        self.videoDevice = newDevice;
        [self.captureSession startRunning];

        [self configureDevice:newDevice];

        [[NSNotificationCenter defaultCenter] postNotificationName:kCD3DGSCameraDidReloadNotification object:nil];
        NSLog(@"3DGS camera reloaded with lens: %@", newDevice.localizedName);
    });
}

- (AVCaptureVideoPreviewLayer *)setupCamera {
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];

    // Keep consistent with existing demo capability (1080P preset).
    if ([session canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        session.sessionPreset = AVCaptureSessionPreset1920x1080;
    }

    AVCaptureDevice *device = [self findCameraDevice];
    if (!device) {
        NSLog(@"Error: cannot find camera");
        return nil;
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error) {
        NSLog(@"Error creating input: %@", error.localizedDescription);
        return nil;
    }
    if ([session canAddInput:input]) {
        [session addInput:input];
    }

    AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([session canAddOutput:movieOutput]) {
        [session addOutput:movieOutput];
    }

    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    videoDataOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
    self.videoDataOutputQueue = dispatch_queue_create("com.roomcapture.blur-output", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    if ([session canAddOutput:videoDataOutput]) {
        [session addOutput:videoDataOutput];
        self.videoDataOutput = videoDataOutput;
    }

    [session commitConfiguration];

    self.videoDevice = device;
    [self configureDevice:device];
    self.videoOutput = movieOutput;
    self.blurMonitor = [[CD3DGSBlurMonitor alloc] init];
    self.currentBlurState = NSIntegerMin;

    AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
    preview.videoGravity = AVLayerVideoGravityResizeAspectFill;

    self.captureSession = session;
    self.previewLayer = preview;

    NSLog(@"3DGS camera setup complete. Device: %@", device.localizedName);
    return preview;
}

- (AVCaptureDevice *)findCameraDevice {
    AVCaptureDevice *device = nil;

    if (self.currentCameraLens == 0) {
        AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInUltraWideCamera]
            mediaType:AVMediaTypeVideo
            position:AVCaptureDevicePositionBack];

        if (discovery.devices.count > 0) {
            device = discovery.devices.firstObject;
            NSLog(@"Found ultra-wide camera: %@", device.localizedName);
        }
    }

    if (!device) {
        device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                    mediaType:AVMediaTypeVideo
                                                     position:AVCaptureDevicePositionBack];
        NSLog(@"Using wide-angle camera: %@", device.localizedName);
    }

    return device;
}

- (int32_t)resolvedFrameRateForDevice:(AVCaptureDevice *)device preferredFrameRate:(int32_t)preferredFrameRate {
    if (!device || preferredFrameRate <= 0) {
        return 30;
    }

    AVCaptureDeviceFormat *format = device.activeFormat;
    int32_t fallbackFrameRate = 30;

    for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
        int32_t minFrameRate = MAX(1, (int32_t)ceil(range.minFrameRate));
        int32_t maxFrameRate = MAX(minFrameRate, (int32_t)floor(range.maxFrameRate));
        fallbackFrameRate = MAX(fallbackFrameRate, maxFrameRate);

        if (preferredFrameRate >= minFrameRate && preferredFrameRate <= maxFrameRate) {
            return preferredFrameRate;
        }
    }

    return fallbackFrameRate;
}

- (void)persistResolvedFrameRateIfNeeded:(int32_t)resolvedFrameRate {
    if (resolvedFrameRate <= 0 || resolvedFrameRate == self.targetFrameRate) {
        return;
    }
    self.targetFrameRate = resolvedFrameRate;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:resolvedFrameRate forKey:@"CDSettingsFrameRate"];
    [defaults synchronize];
}

- (void)configureDevice:(AVCaptureDevice *)device {
    if (!device) return;

    int32_t resolvedFrameRate = [self resolvedFrameRateForDevice:device preferredFrameRate:self.targetFrameRate];
    [self persistResolvedFrameRateIfNeeded:resolvedFrameRate];

    NSError *error = nil;
    BOOL locked = [device lockForConfiguration:&error];
    if (error || !locked) {
        NSLog(@"lockForConfiguration error: %@", error.localizedDescription);
        return;
    }

    CMTime frameDuration = CMTimeMake(1, resolvedFrameRate);
    device.activeVideoMinFrameDuration = frameDuration;
    device.activeVideoMaxFrameDuration = frameDuration;

    self.exposureAutoLockGeneration += 1;
    NSUInteger autoLockGeneration = self.exposureAutoLockGeneration;

    CMTime minExposureDuration = device.activeFormat.minExposureDuration;
    CMTime maxExposureDuration = device.activeFormat.maxExposureDuration;
    CMTime desiredDuration = self.shutterDuration;
    if (CMTIME_IS_VALID(minExposureDuration) && CMTIME_COMPARE_INLINE(desiredDuration, <, minExposureDuration)) {
        desiredDuration = minExposureDuration;
    }
    if (CMTIME_IS_VALID(maxExposureDuration) && CMTIME_COMPARE_INLINE(desiredDuration, >, maxExposureDuration)) {
        desiredDuration = maxExposureDuration;
    }

    float minISO = device.activeFormat.minISO;
    float maxISO = device.activeFormat.maxISO;
    float iso = self.targetISO;
    if (iso < minISO) iso = minISO;
    if (iso > maxISO) iso = maxISO;

    if ([device respondsToSelector:@selector(setActiveMaxExposureDuration:)]) {
        device.activeMaxExposureDuration = maxExposureDuration;
    }

    if (self.exposureMode == 0) {
        if ([device isExposureModeSupported:AVCaptureExposureModeCustom]) {
            [device setExposureModeCustomWithDuration:desiredDuration ISO:iso completionHandler:nil];
        }
    } else if (self.exposureMode == 1) {
        if ([device respondsToSelector:@selector(setActiveMaxExposureDuration:)]) {
            device.activeMaxExposureDuration = desiredDuration;
        }
        if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
    } else if (self.exposureMode == 2) {
        if ([device respondsToSelector:@selector(setActiveMaxExposureDuration:)]) {
            device.activeMaxExposureDuration = desiredDuration;
        }
        if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
        NSTimeInterval settle = MAX(0.1, self.autoLockSettleSeconds);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(settle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (autoLockGeneration != self.exposureAutoLockGeneration) return;
            if (self.videoDevice != device) return;
            if (![device isExposureModeSupported:AVCaptureExposureModeCustom]) return;

            CMTime currentDuration = device.exposureDuration;
            float currentISO = device.ISO;
            float clampedISO = MIN(MAX(currentISO, device.activeFormat.minISO), device.activeFormat.maxISO);

            NSError *innerError = nil;
            BOOL innerLocked = [device lockForConfiguration:&innerError];
            if (innerError || !innerLocked) {
                NSLog(@"lockForConfiguration (auto-lock) error: %@", innerError.localizedDescription);
                return;
            }

            [device setExposureModeCustomWithDuration:currentDuration ISO:clampedISO completionHandler:nil];
            [device unlockForConfiguration];

            NSTimeInterval lockedSeconds = CMTimeGetSeconds(currentDuration);
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setDouble:lockedSeconds forKey:@"CDLastLockedExposureSeconds"];
            [defaults setFloat:clampedISO forKey:@"CDLastLockedISO"];
            [defaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"CDLastLockedTimestamp"];
            [defaults synchronize];
            [[NSNotificationCenter defaultCenter] postNotificationName:kCD3DGSCameraExposureDidAutoLockNotification object:nil];
        });
    }

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

    if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    } else if ([device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        device.focusMode = AVCaptureFocusModeAutoFocus;
    } else if ([device isFocusModeSupported:AVCaptureFocusModeLocked]) {
        device.focusMode = AVCaptureFocusModeLocked;
    }

    [device unlockForConfiguration];

    NSLog(@"3DGS camera configured: 1920x1080, %dfps, WB=%.0fK, exposureMode=%ld",
          resolvedFrameRate, self.whiteBalanceTemperature, (long)self.exposureMode);
}

- (void)startSession {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.captureSession startRunning];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startLockMonitorIfNeeded];
    });
}

- (void)stopSession {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.captureSession stopRunning];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopLockMonitor];
    });
}

- (BOOL)isRecording {
    return [self.videoOutput isRecording];
}

- (void)startRecording {
    if ([self.videoOutput isRecording]) {
        return;
    }
    if (!self.videoOutput) {
        return;
    }

    [self resetBlurAnalysis];

    NSURL *videosDir = [self getVideoDirectory];
    [[NSFileManager defaultManager] createDirectoryAtURL:videosDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSString *fileName = [NSString stringWithFormat:@"3DGS_%lld.mp4", (long long)timestamp];
    NSURL *fileURL = [videosDir URLByAppendingPathComponent:fileName];
    self.currentVideoURL = fileURL;

    [self.videoOutput startRecordingToOutputFileURL:fileURL recordingDelegate:self];

    self->_recordingDuration = 0;
    [self startRecordingTimer];
}

- (void)stopRecording {
    if (![self.videoOutput isRecording]) {
        return;
    }
    [self.videoOutput stopRecording];
    [self stopRecordingTimer];
}

- (void)resetBlurAnalysis {
    [self.blurMonitor reset];
    self.currentBlurState = NSIntegerMin;
    self.blurAnalysisFrameCount = 0;
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
        if (error) {
            NSLog(@"3DGS recording error: %@", error.localizedDescription);
        } else {
            NSLog(@"3DGS recording saved: %@", fileURL);
            [self loadRecordedVideos];
            self.currentVideoURL = nil;
            [[NSNotificationCenter defaultCenter] postNotificationName:CD3DGSCameraDidFinishRecordingNotification
                                                                object:self
                                                              userInfo:@{ CD3DGSCameraRecordingURLKey: fileURL }];
        }
    });
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (output != self.videoDataOutput) {
        return;
    }
    if (![self.videoOutput isRecording]) {
        return;
    }

    self.blurAnalysisFrameCount += 1;
    if ((self.blurAnalysisFrameCount % 4) != 0) {
        return;
    }

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer || !self.blurStatusHandler) {
        return;
    }

    CGFloat variance = [CD3DGSBlurMonitor laplacianVarianceForPixelBuffer:pixelBuffer];
    CD3DGSBlurState state = [self.blurMonitor updateWithLaplacianVariance:variance];
    self.currentBlurState = state;

    CD3DGSCameraBlurStatusHandler handler = self.blurStatusHandler;
    if (!handler) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        handler(state, (double)variance);
    });
}

- (void)startLockMonitorIfNeeded {
    if (self.lockMonitorTimer) {
        return;
    }
    self.lockMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                             target:self
                                                           selector:@selector(tickLockMonitor)
                                                           userInfo:nil
                                                            repeats:YES];
}

- (void)stopLockMonitor {
    [self.lockMonitorTimer invalidate];
    self.lockMonitorTimer = nil;
}

- (void)tickLockMonitor {
    AVCaptureDevice *device = self.videoDevice;
    if (!device) return;

    BOOL locked = YES;
    NSString *summary = @"参数已应用";

    // Zoom should stay at 1.0x for 3DGS capture.
    if (fabs(device.videoZoomFactor - 1.0) > 0.01) {
        locked = NO;
        summary = @"变焦已变化";
    }

    if (locked) {
        // White balance should be locked.
        if (device.whiteBalanceMode != AVCaptureWhiteBalanceModeLocked) {
            locked = NO;
            summary = @"白平衡未锁定";
        }
    }

    if (locked) {
        // Exposure mode should match selected strategy.
        if (self.exposureMode == 0) {
            locked = (device.exposureMode == AVCaptureExposureModeCustom);
            summary = locked ? summary : @"曝光未锁定";
        } else if (self.exposureMode == 1) {
            locked = (device.exposureMode == AVCaptureExposureModeContinuousAutoExposure);
            summary = locked ? summary : @"曝光模式异常";
        } else if (self.exposureMode == 2) {
            // Allow either AE settling or custom lock.
            locked = (device.exposureMode == AVCaptureExposureModeContinuousAutoExposure || device.exposureMode == AVCaptureExposureModeCustom);
            summary = locked ? summary : @"曝光模式异常";
        }
    }

    if (locked != self.parametersLocked || ![summary isEqualToString:self.parametersLockSummary]) {
        self.parametersLocked = locked;
        self.parametersLockSummary = summary;
        [[NSNotificationCenter defaultCenter] postNotificationName:kCD3DGSCameraParametersLockDidChangeNotification object:nil];
    }
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
    return [docURL URLByAppendingPathComponent:@"3DGS_Videos" isDirectory:YES];
}

@end

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
@property (nonatomic, assign) NSInteger exposureMode;
@property (nonatomic, assign) NSTimeInterval autoLockSettleSeconds;
@property (nonatomic, assign) NSInteger currentCameraLens;
@property (nonatomic, assign) NSUInteger exposureAutoLockGeneration;

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
        [self loadSettings];
        [self loadRecordedVideos];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(settingsDidChange:)
                                                     name:@"CDCameraSettingsDidChange"
                                                   object:nil];
    }
    return self;
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _targetFrameRate = [defaults integerForKey:@"CDSettingsFrameRate"];
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
        // Camera lens changed, need to reload camera
        [self reloadCamera];
    } else if (self.captureSession && self.videoDevice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self configureDevice:self.videoDevice];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CDCameraDidReload" object:nil];
        });
    }
}

- (void)reloadCamera {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.captureSession stopRunning];

        // Remove existing input
        for (AVCaptureInput *input in self.captureSession.inputs) {
            [self.captureSession removeInput:input];
        }

        // Find new device
        AVCaptureDevice *newDevice = [self findCameraDevice];
        if (!newDevice) {
            NSLog(@"Error: cannot find camera device");
            return;
        }

        NSLog(@"Switching to camera: %@", newDevice.localizedName);

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

        // Configure device after session starts
        [self configureDevice:newDevice];

        [[NSNotificationCenter defaultCenter] postNotificationName:@"CDCameraDidReload" object:nil];
        NSLog(@"Camera reloaded with lens: %@", newDevice.localizedName);
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error) {
        NSLog(@"Error creating input: %@", error.localizedDescription);
        return nil;
    }
    if ([session canAddInput:input]) {
        [session addInput:input];
    }

    AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
    if ([session canAddOutput:output]) {
        [session addOutput:output];
    }

    [session commitConfiguration];

    // Configure device AFTER adding to session
    self.videoDevice = device;
    [self configureDevice:device];
    self.videoOutput = output;

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

    if (self.currentCameraLens == 0) {
        // Ultra-wide camera (0.5x)
        AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInUltraWideCamera]
            mediaType:AVMediaTypeVideo
            position:AVCaptureDevicePositionBack];

        if (discovery.devices.count > 0) {
            device = discovery.devices.firstObject;
            NSLog(@"Found ultra-wide camera: %@", device.localizedName);
        }
    }

    // Fallback or wide-angle (1.0x)
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

    // Set frame rate
    CMTime frameDuration = CMTimeMake(1, resolvedFrameRate);
    device.activeVideoMinFrameDuration = frameDuration;
    device.activeVideoMaxFrameDuration = frameDuration;

    // Set shutter and ISO
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

    // Reset exposure duration limit unless the chosen mode needs it.
    if ([device respondsToSelector:@selector(setActiveMaxExposureDuration:)]) {
        device.activeMaxExposureDuration = maxExposureDuration;
    }

    if (self.exposureMode == 0) {
        // Manual: fixed shutter + fixed ISO.
        if ([device isExposureModeSupported:AVCaptureExposureModeCustom]) {
            [device setExposureModeCustomWithDuration:desiredDuration ISO:iso completionHandler:nil];
        }
    } else if (self.exposureMode == 1) {
        // Shutter-priority: lock exposure duration upper bound, let ISO adapt (AE).
        if ([device respondsToSelector:@selector(setActiveMaxExposureDuration:)]) {
            device.activeMaxExposureDuration = desiredDuration;
        }
        if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
    } else if (self.exposureMode == 2) {
        // Auto settle then lock: run AE (optionally with max duration cap), then lock current (duration + ISO).
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
            NSLog(@"Auto-settle lock applied: duration=%.4fs, ISO=%.0f", lockedSeconds, clampedISO);

            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setDouble:lockedSeconds forKey:@"CDLastLockedExposureSeconds"];
            [defaults setFloat:clampedISO forKey:@"CDLastLockedISO"];
            [defaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"CDLastLockedTimestamp"];
            [defaults synchronize];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CDCameraExposureDidAutoLock" object:nil];
        });
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

    // Use continuous auto focus for better clarity
    if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    } else if ([device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        device.focusMode = AVCaptureFocusModeAutoFocus;
    } else if ([device isFocusModeSupported:AVCaptureFocusModeLocked]) {
        device.focusMode = AVCaptureFocusModeLocked;
    }

    [device unlockForConfiguration];

    if (self.exposureMode == 0) {
        NSLog(@"Camera configured: 1920x1080, %dfps, WB=%.0fK, 1/%.0f, ISO=%.0f",
              resolvedFrameRate, self.whiteBalanceTemperature, (double)self.shutterDuration.timescale, iso);
    } else if (self.exposureMode == 1) {
        NSLog(@"Camera configured: 1920x1080, %dfps, WB=%.0fK, shutter<=1/%.0f, ISO:auto",
              resolvedFrameRate, self.whiteBalanceTemperature, (double)self.shutterDuration.timescale);
    } else if (self.exposureMode == 2) {
        NSLog(@"Camera configured: 1920x1080, %dfps, WB=%.0fK, AE settle %.1fs then lock (shutter<=1/%.0f)",
              resolvedFrameRate, self.whiteBalanceTemperature, self.autoLockSettleSeconds, (double)self.shutterDuration.timescale);
    }
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

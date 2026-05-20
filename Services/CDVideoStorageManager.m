#import "CDVideoStorageManager.h"

@interface CDVideoStorageManager ()

@property (nonatomic, strong) NSURL *videoStorageRoot;

@end

@implementation CDVideoStorageManager

+ (instancetype)shared {
    static CDVideoStorageManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CDVideoStorageManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupVideoStorageRoot];
    }
    return self;
}

- (void)setupVideoStorageRoot {
    NSURL *docURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                             inDomains:NSUserDomainMask] firstObject];
    _videoStorageRoot = [docURL URLByAppendingPathComponent:@"CaptureDemoVideos" isDirectory:YES];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:_videoStorageRoot
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        NSLog(@"CDVideoStorageManager: Failed to create storage directory: %@", error.localizedDescription);
    }
}

- (NSURL *)videoStorageRoot {
    return _videoStorageRoot;
}

#pragma mark - Public Methods

- (NSArray<NSURL *> *)allSavedVideos {
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_videoStorageRoot
                                                  includingPropertiesForKeys:@[NSURLCreationDateKey]
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                       error:&error];
    if (error) {
        NSLog(@"CDVideoStorageManager: Failed to list videos: %@", error.localizedDescription);
        return @[];
    }

    NSMutableArray<NSURL *> *videos = [NSMutableArray array];
    for (NSURL *url in files) {
        if ([[url pathExtension] isEqualToString:@"mp4"] || [[url pathExtension] isEqualToString:@"mov"]) {
            [videos addObject:url];
        }
    }

    // 按创建时间倒序排列
    return [videos sortedArrayUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
        NSDate *d1 = [self creationDateForVideoAtURL:url1];
        NSDate *d2 = [self creationDateForVideoAtURL:url2];
        return [d2 compare:d1];
    }];
}

- (NSArray<NSURL *> *)videosForRoomName:(NSString *)roomName {
    if (!roomName || roomName.length == 0) {
        return [self allSavedVideos];
    }

    NSArray<NSURL *> *allVideos = [self allSavedVideos];
    NSMutableArray<NSURL *> *filtered = [NSMutableArray array];

    for (NSURL *url in allVideos) {
        NSString *fileName = [url lastPathComponent];
        if ([fileName containsString:roomName]) {
            [filtered addObject:url];
        }
    }

    return filtered;
}

- (void)saveVideoToDocuments:(NSURL *)sourceURL
                    roomName:(NSString *)roomName
                  completion:(void(^)(NSURL * _Nullable savedURL, NSError * _Nullable error))completion {

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (!sourceURL || ![[NSFileManager defaultManager] fileExistsAtPath:sourceURL.path]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    NSError *error = [NSError errorWithDomain:@"CDVideoStorageManager"
                                                        code:1
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Source file does not exist"}];
                    completion(nil, error);
                }
            });
            return;
        }

        // 创建以房间命名的子目录
        NSString *sanitizedRoomName = [self sanitizeFileName:roomName ?: @"Default"];
        NSString *subDirName = [NSString stringWithFormat:@"%@_Videos", sanitizedRoomName];
        NSURL *roomDir = [_videoStorageRoot URLByAppendingPathComponent:subDirName isDirectory:YES];

        NSError *dirError = nil;
        [[NSFileManager defaultManager] createDirectoryAtURL:roomDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&dirError];
        if (dirError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, dirError);
                }
            });
            return;
        }

        // 生成带时间戳的文件名
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyyMMdd_HHmmss";
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        NSString *extension = [sourceURL pathExtension] ?: @"mp4";
        NSString *fileName = [NSString stringWithFormat:@"%@_%@.%@", sanitizedRoomName, timestamp, extension];
        NSURL *destURL = [roomDir URLByAppendingPathComponent:fileName];

        // 复制文件
        NSError *copyError = nil;
        [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
        BOOL success = [[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:destURL error:&copyError];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success ? destURL : nil, copyError);
            }
        });
    });
}

- (void)saveVideoToPhotoLibrary:(NSURL *)videoURL
                     completion:(void(^)(BOOL success, NSError * _Nullable error))completion {

    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    NSError *error = [NSError errorWithDomain:@"CDVideoStorageManager"
                                                        code:2
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Photo library access denied"}];
                    completion(NO, error);
                }
            });
            return;
        }

        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(success, error);
                }
            });
        }];
    }];
}

- (void)saveVideosToPhotoLibrary:(NSArray<NSURL *> *)videoURLs
                      completion:(void(^)(NSInteger savedCount, NSError * _Nullable error))completion {

    if (videoURLs.count == 0) {
        if (completion) {
            completion(0, nil);
        }
        return;
    }

    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    NSError *error = [NSError errorWithDomain:@"CDVideoStorageManager"
                                                        code:2
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Photo library access denied"}];
                    completion(0, error);
                }
            });
            return;
        }

        __block NSInteger savedCount = 0;
        __block NSInteger totalCount = videoURLs.count;
        __block NSError *lastError = nil;

        dispatch_group_t group = dispatch_group_create();

        for (NSURL *url in videoURLs) {
            dispatch_group_enter(group);

            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (success) {
                    savedCount++;
                } else {
                    lastError = error;
                }
                dispatch_group_leave(group);
            }];
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (completion) {
                completion(savedCount, lastError);
            }
        });
    }];
}

- (BOOL)deleteVideoAtURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] removeItemAtURL:url error:&error];
    if (!success) {
        NSLog(@"CDVideoStorageManager: Failed to delete video: %@", error.localizedDescription);
    }
    return success;
}

- (void)deleteAllVideos {
    NSArray<NSURL *> *videos = [self allSavedVideos];
    for (NSURL *url in videos) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    }
    NSLog(@"CDVideoStorageManager: Deleted all %lu videos", (unsigned long)videos.count);
}

- (unsigned long long)storageSize {
    NSArray<NSURL *> *videos = [self allSavedVideos];
    unsigned long long totalSize = 0;

    for (NSURL *url in videos) {
        NSError *error = nil;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:&error];
        if (!error && attrs) {
            totalSize += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }

    return totalSize;
}

- (NSDate *)creationDateForVideoAtURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    NSDate *date = nil;
    [url getResourceValue:&date forKey:NSURLCreationDateKey error:nil];
    return date;
}

#pragma mark - Private Methods

- (NSString *)sanitizeFileName:(NSString *)fileName {
    if (!fileName || fileName.length == 0) {
        return @"Unknown";
    }

    // 移除不允许作为文件名的字符
    NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSString *sanitized = [[fileName componentsSeparatedByCharactersInSet:invalidChars] componentsJoinedByString:@"_"];
    return sanitized.length > 0 ? sanitized : @"Unknown";
}

@end
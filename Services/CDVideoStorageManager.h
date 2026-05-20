#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

/// 视频存储管理器 - 处理视频的持久化存储
@interface CDVideoStorageManager : NSObject

/// 单例
+ (instancetype)shared;

/// 获取视频存储根目录（Documents/Videos）
@property (nonatomic, readonly) NSURL *videoStorageRoot;

/// 获取所有已保存的视频
- (NSArray<NSURL *> *)allSavedVideos;

/// 按房间名称获取视频
- (NSArray<NSURL *> *)videosForRoomName:(NSString *)roomName;

/// 保存视频到持久化目录（Documents）
/// @param sourceURL 视频源文件URL
/// @param roomName 房间名称（用于组织文件）
/// @param completion 完成回调，返回保存后的文件URL
- (void)saveVideoToDocuments:(NSURL *)sourceURL
                    roomName:(NSString *)roomName
                  completion:(void(^)(NSURL * _Nullable savedURL, NSError * _Nullable error))completion;

/// 保存视频到相册
/// @param videoURL 视频文件URL
/// @param completion 完成回调
- (void)saveVideoToPhotoLibrary:(NSURL *)videoURL
                     completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

/// 批量保存视频到相册
/// @param videoURLs 视频URL数组
/// @param completion 完成回调，返回成功数量
- (void)saveVideosToPhotoLibrary:(NSArray<NSURL *> *)videoURLs
                      completion:(void(^)(NSInteger savedCount, NSError * _Nullable error))completion;

/// 删除指定视频
- (BOOL)deleteVideoAtURL:(NSURL *)url;

/// 删除所有已保存的视频
- (void)deleteAllVideos;

/// 获取视频存储目录大小（字节）
- (unsigned long long)storageSize;

/// 获取视频创建时间
- (nullable NSDate *)creationDateForVideoAtURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
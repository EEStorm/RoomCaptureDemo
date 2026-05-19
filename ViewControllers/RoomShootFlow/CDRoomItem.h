#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDRoomItem : NSObject
@property (nonatomic, copy) NSString *roomId;
@property (nonatomic, copy) NSString *roomName;
@property (nonatomic, assign) BOOL captureComplete; // 是否完成采集（完成后才会进入审核队列）
@property (nonatomic, assign) NSInteger auditStatus; // 0:未进入审核 1:审核中 2:通过 3:未通过
@property (nonatomic, copy) NSString *auditReason;
@end

NS_ASSUME_NONNULL_END


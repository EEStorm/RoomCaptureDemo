#import <UIKit/UIKit.h>

@class CDRoomItem;

NS_ASSUME_NONNULL_BEGIN

@interface CDRoomVideoReviewViewController : UIViewController
- (instancetype)initWithRoom:(CDRoomItem *)room;
- (instancetype)initWithRoom:(CDRoomItem *)room videoURLs:(NSArray<NSURL *> *)videoURLs;
- (instancetype)initWithRoom:(CDRoomItem *)room videoURLs:(NSArray<NSURL *> *)videoURLs singleRoomDemoFlow:(BOOL)singleRoomDemoFlow;
@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CD3DGSTrainingResultSummary;

@interface CD3DGSTrainingResultViewController : UIViewController

- (instancetype)initWithSummary:(CD3DGSTrainingResultSummary *)summary;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

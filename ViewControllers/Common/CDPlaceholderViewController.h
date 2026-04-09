#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDPlaceholderViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

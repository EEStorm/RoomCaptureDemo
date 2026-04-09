#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef UIViewController * _Nonnull (^CDDestinationBuilder)(void);

@interface CDFeatureHomeViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                  buttonTitle:(NSString *)buttonTitle
             destinationBuilder:(CDDestinationBuilder)destinationBuilder NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

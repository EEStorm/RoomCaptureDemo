#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef UIViewController * _Nonnull (^CDDestinationBuilder)(void);

typedef NS_ENUM(NSInteger, CDFeatureHomeEntryStyle) {
    CDFeatureHomeEntryStyleDisabled = 0,
    CDFeatureHomeEntryStyleBrand = 1,
    CDFeatureHomeEntryStyleSuccess = 2,
    CDFeatureHomeEntryStyleWarning = 3
};

@interface CDFeatureHomeEntry : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, assign) CDFeatureHomeEntryStyle style;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *badge;
@property (nonatomic, copy, nullable) CDDestinationBuilder destinationBuilder;

+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                         style:(CDFeatureHomeEntryStyle)style
                       enabled:(BOOL)enabled
                         badge:(nullable NSString *)badge
           destinationBuilder:(nullable CDDestinationBuilder)destinationBuilder;
@end

@interface CDFeatureHomeViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                  buttonTitle:(NSString *)buttonTitle
             destinationBuilder:(CDDestinationBuilder)destinationBuilder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTitle:(NSString *)title
                      entries:(NSArray<CDFeatureHomeEntry *> *)entries;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

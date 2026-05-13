#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CD3DGSTrafficLight) {
    CD3DGSTrafficLightUnavailable = 0,
    CD3DGSTrafficLightGreen = 1,
    CD3DGSTrafficLightYellow = 2,
    CD3DGSTrafficLightRed = 3,
};

NS_ASSUME_NONNULL_BEGIN

@interface CD3DGSMetrics : NSObject

+ (CD3DGSTrafficLight)translationTrafficLightForRatio:(double)ratio;
+ (CD3DGSTrafficLight)rotationTrafficLightForDegreesPerSecond:(double)degreesPerSecond;
+ (BOOL)isTranslationEstimationAllowedForRotationDegreesPerSecond:(double)degreesPerSecond;

@end

NS_ASSUME_NONNULL_END


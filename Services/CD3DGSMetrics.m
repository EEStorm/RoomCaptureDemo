#import "CD3DGSMetrics.h"

@implementation CD3DGSMetrics

+ (CD3DGSTrafficLight)translationTrafficLightForRatio:(double)ratio {
    if (!(ratio >= 0)) return CD3DGSTrafficLightUnavailable;
    if (ratio > 0.60) return CD3DGSTrafficLightRed;
    if (ratio >= 0.30) return CD3DGSTrafficLightYellow;
    return CD3DGSTrafficLightGreen;
}

+ (CD3DGSTrafficLight)rotationTrafficLightForDegreesPerSecond:(double)degreesPerSecond {
    if (!(degreesPerSecond >= 0)) return CD3DGSTrafficLightUnavailable;
    if (degreesPerSecond > 18.0) return CD3DGSTrafficLightRed;
    if (degreesPerSecond >= 12.0) return CD3DGSTrafficLightYellow;
    return CD3DGSTrafficLightGreen;
}

+ (BOOL)isTranslationEstimationAllowedForRotationDegreesPerSecond:(double)degreesPerSecond {
    if (!(degreesPerSecond >= 0)) return NO;
    return degreesPerSecond < 30.0;
}

@end

#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDSpatialAimSequence : NSObject

@property (nonatomic, copy, readonly) NSArray<NSValue *> *positions;
@property (nonatomic, assign, readonly) NSInteger currentIndex;
@property (nonatomic, assign, readonly, getter=isComplete) BOOL complete;

- (instancetype)initWithPointCount:(NSInteger)pointCount
                            radius:(CGFloat)radius
                      holdDuration:(NSTimeInterval)holdDuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Returns YES exactly once when the current point advances.
- (BOOL)updateCentered:(BOOL)centered timestamp:(NSTimeInterval)timestamp;
- (void)reset;

@end

NS_ASSUME_NONNULL_END

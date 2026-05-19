#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CD3DGSCaptureGuidanceState : NSObject

@property (nonatomic, assign, readonly) NSInteger currentStepIndex;
@property (nonatomic, copy, readonly) NSString *currentInstruction;
@property (nonatomic, assign, readonly) BOOL canMoveToPreviousStep;
@property (nonatomic, assign, readonly) BOOL canMoveToNextStep;
@property (nonatomic, assign, readonly) BOOL isComplete;
@property (nonatomic, copy, readonly) NSArray<NSURL *> *completedVideoURLs;
@property (nonatomic, copy, readonly) NSString *guideVideoResourceName;
@property (nonatomic, copy, readonly) NSString *currentToastText;

- (void)moveToPreviousStep;
- (void)moveToNextStep;
- (void)completeCurrentStepWithVideoURL:(NSURL *)videoURL;

@end

NS_ASSUME_NONNULL_END

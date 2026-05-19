#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CD3DGSTrainingRoomResultStatus) {
    CD3DGSTrainingRoomResultStatusPassed = 0,
    CD3DGSTrainingRoomResultStatusNeedsReview
};

@interface CD3DGSTrainingRoomResult : NSObject

@property (nonatomic, copy, readonly) NSString *roomName;
@property (nonatomic, copy, readonly) NSString *coverageText;
@property (nonatomic, assign, readonly) CD3DGSTrainingRoomResultStatus status;
@property (nonatomic, copy, readonly) NSString *statusText;

+ (instancetype)resultWithRoomName:(NSString *)roomName
                      coverageText:(NSString *)coverageText
                            status:(CD3DGSTrainingRoomResultStatus)status;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface CD3DGSTrainingResultSummary : NSObject

@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *statusTitle;
@property (nonatomic, copy, readonly) NSString *statusSubtitle;
@property (nonatomic, copy, readonly) NSString *deliveryTagText;
@property (nonatomic, assign, readonly) NSInteger score;
@property (nonatomic, assign, readonly) NSInteger coveragePercent;
@property (nonatomic, assign, readonly) NSInteger clearFramePercent;
@property (nonatomic, copy, readonly) NSString *generatedAtText;
@property (nonatomic, copy, readonly) NSString *riskText;
@property (nonatomic, copy, readonly) NSArray<CD3DGSTrainingRoomResult *> *roomResults;
@property (nonatomic, assign, readonly) BOOL hasReviewRisk;

+ (instancetype)demoSummary;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#import "CD3DGSTrainingResultSummary.h"

@interface CD3DGSTrainingRoomResult ()

@property (nonatomic, copy, readwrite) NSString *roomName;
@property (nonatomic, copy, readwrite) NSString *coverageText;
@property (nonatomic, assign, readwrite) CD3DGSTrainingRoomResultStatus status;

@end

@implementation CD3DGSTrainingRoomResult

+ (instancetype)resultWithRoomName:(NSString *)roomName
                      coverageText:(NSString *)coverageText
                            status:(CD3DGSTrainingRoomResultStatus)status {
    CD3DGSTrainingRoomResult *result = [[CD3DGSTrainingRoomResult alloc] initPrivate];
    result.roomName = roomName;
    result.coverageText = coverageText;
    result.status = status;
    return result;
}

- (instancetype)initPrivate {
    self = [super init];
    return self;
}

- (NSString *)statusText {
    switch (self.status) {
        case CD3DGSTrainingRoomResultStatusPassed:
            return @"通过";
        case CD3DGSTrainingRoomResultStatusNeedsReview:
            return @"需复核";
    }
}

@end

@interface CD3DGSTrainingResultSummary ()

@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *statusTitle;
@property (nonatomic, copy, readwrite) NSString *statusSubtitle;
@property (nonatomic, copy, readwrite) NSString *deliveryTagText;
@property (nonatomic, assign, readwrite) NSInteger score;
@property (nonatomic, assign, readwrite) NSInteger coveragePercent;
@property (nonatomic, assign, readwrite) NSInteger clearFramePercent;
@property (nonatomic, copy, readwrite) NSString *generatedAtText;
@property (nonatomic, copy, readwrite) NSString *riskText;
@property (nonatomic, copy, readwrite) NSArray<CD3DGSTrainingRoomResult *> *roomResults;

@end

@implementation CD3DGSTrainingResultSummary

+ (instancetype)demoSummary {
    CD3DGSTrainingResultSummary *summary = [[CD3DGSTrainingResultSummary alloc] initPrivate];
    summary.title = @"训练结果";
    summary.statusTitle = @"高斯训练完成";
    summary.statusSubtitle = @"本次结果可用于线上预览，请确认后提交交付";
    summary.deliveryTagText = @"可交付";
    summary.score = 92;
    summary.coveragePercent = 96;
    summary.clearFramePercent = 89;
    summary.generatedAtText = @"生成时间 12:36";
    summary.riskText = @"次卧存在局部低纹理区域，建议打开预览确认是否影响漫游体验。";
    summary.roomResults = @[
        [CD3DGSTrainingRoomResult resultWithRoomName:@"客厅" coverageText:@"覆盖 96%" status:CD3DGSTrainingRoomResultStatusPassed],
        [CD3DGSTrainingRoomResult resultWithRoomName:@"主卧" coverageText:@"覆盖 94%" status:CD3DGSTrainingRoomResultStatusPassed],
        [CD3DGSTrainingRoomResult resultWithRoomName:@"次卧" coverageText:@"覆盖 82%" status:CD3DGSTrainingRoomResultStatusNeedsReview],
        [CD3DGSTrainingRoomResult resultWithRoomName:@"厨房" coverageText:@"覆盖 91%" status:CD3DGSTrainingRoomResultStatusPassed]
    ];
    return summary;
}

- (instancetype)initPrivate {
    self = [super init];
    return self;
}

- (BOOL)hasReviewRisk {
    for (CD3DGSTrainingRoomResult *roomResult in self.roomResults) {
        if (roomResult.status == CD3DGSTrainingRoomResultStatusNeedsReview) {
            return YES;
        }
    }
    return NO;
}

@end

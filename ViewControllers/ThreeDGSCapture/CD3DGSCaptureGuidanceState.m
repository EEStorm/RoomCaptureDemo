#import "CD3DGSCaptureGuidanceState.h"

@interface CD3DGSCaptureGuidanceState ()

@property (nonatomic, assign, readwrite) NSInteger currentStepIndex;
@property (nonatomic, copy, readwrite) NSString *currentInstruction;
@property (nonatomic, assign, readwrite) BOOL canMoveToPreviousStep;
@property (nonatomic, assign, readwrite) BOOL canMoveToNextStep;
@property (nonatomic, assign, readwrite) BOOL isComplete;
@property (nonatomic, copy, readwrite) NSArray<NSURL *> *completedVideoURLs;
@property (nonatomic, copy, readwrite) NSString *guideVideoResourceName;
@property (nonatomic, copy, readwrite) NSString *currentToastText;
@property (nonatomic, copy) NSArray<NSString *> *instructions;
@property (nonatomic, copy) NSArray<NSString *> *guideVideoResourceNames;
@property (nonatomic, copy) NSArray<NSString *> *toastTexts;
@property (nonatomic, strong) NSMutableArray<NSURL *> *mutableCompletedVideoURLs;

@end

@implementation CD3DGSCaptureGuidanceState

- (instancetype)init {
    self = [super init];
    if (self) {
        _instructions = @[
            @"第一步：空间环绕扫描",
            @"第二步：全域推进拍摄",
            @"第三步：消除盲区拍摄",
            @"第四步：关键物品细节拍摄"
        ];
        _guideVideoResourceNames = @[
            @"step01",
            @"step02",
            @"step03",
            @"step04"
        ];
        _toastTexts = @[
            @"第一步，空间环绕扫描：分客厅、卧室依次进行。全程手机保持水平不晃动，镜头始终对准房间中心；沿墙边匀速平移，卧室拐角处停留2-3秒，保持镜头对准房间中心，完整扫描布局即可。",
            @"第二步，分区纵深推进：手机保持水平不晃动，缓慢匀速推进，从区域一端沿可通行路线推至另一端；如遇障碍物缓慢调整方向，绕开障碍时镜头始终朝前，不遗漏任何区域。",
            @"第三步，盲区补录+家具拍摄：盲区对准死角，手机平稳上下平移，每处拍3-5秒；家具以其为中心，缓慢环绕一周，拍摄正面、侧面及边角细节",
            @"第四步，MR效果生成：拍摄完成后，系统自动同步数据、生成点云，前置校验是否满足重建要求"
        ];
        _mutableCompletedVideoURLs = [NSMutableArray array];
        _completedVideoURLs = @[];
        _currentStepIndex = 0;
        [self updateDerivedState];
    }
    return self;
}

- (void)moveToPreviousStep {
    if (self.currentStepIndex <= 0) {
        return;
    }
    self.currentStepIndex -= 1;
    [self updateDerivedState];
}

- (void)moveToNextStep {
    if (self.currentStepIndex >= (NSInteger)self.instructions.count - 1) {
        return;
    }
    self.currentStepIndex += 1;
    [self updateDerivedState];
}

- (void)completeCurrentStepWithVideoURL:(NSURL *)videoURL {
    if (!videoURL || self.isComplete) {
        return;
    }
    if (self.mutableCompletedVideoURLs.count > (NSUInteger)self.currentStepIndex) {
        self.mutableCompletedVideoURLs[(NSUInteger)self.currentStepIndex] = videoURL;
    } else {
        [self.mutableCompletedVideoURLs addObject:videoURL];
    }
    self.completedVideoURLs = [self.mutableCompletedVideoURLs copy];

    if (self.currentStepIndex >= (NSInteger)self.instructions.count - 1) {
        self.isComplete = YES;
        [self updateDerivedState];
        return;
    }
    self.currentStepIndex += 1;
    [self updateDerivedState];
}

- (void)updateDerivedState {
    self.currentInstruction = self.instructions[(NSUInteger)self.currentStepIndex];
    self.guideVideoResourceName = self.guideVideoResourceNames[(NSUInteger)self.currentStepIndex];
    self.currentToastText = self.toastTexts[(NSUInteger)self.currentStepIndex];
    self.canMoveToPreviousStep = self.currentStepIndex > 0 && !self.isComplete;
    self.canMoveToNextStep = self.currentStepIndex < (NSInteger)self.instructions.count - 1 && !self.isComplete;
}

@end

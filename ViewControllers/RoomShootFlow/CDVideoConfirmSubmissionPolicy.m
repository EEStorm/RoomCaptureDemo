#import "CDVideoConfirmSubmissionPolicy.h"

@implementation CDVideoConfirmSubmissionPolicy

+ (BOOL)canSubmitInDemo {
    return YES;
}

+ (NSString *)demoSubmitHint {
    return @"Demo流程：可直接提交查看高斯训练结果";
}

@end

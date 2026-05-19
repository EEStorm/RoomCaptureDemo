#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDVideoConfirmSubmissionPolicy : NSObject

+ (BOOL)canSubmitInDemo;
+ (NSString *)demoSubmitHint;

@end

NS_ASSUME_NONNULL_END

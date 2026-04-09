#import "CDPlaceholderViewController.h"

@interface CDPlaceholderViewController ()

@property (nonatomic, copy) NSString *displayTitle;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, strong) UILabel *messageLabel;

@end

@implementation CDPlaceholderViewController

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _displayTitle = [title copy];
        _message = [message copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.text = self.message;
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    self.messageLabel.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:self.messageLabel];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width - 48.0;
    self.messageLabel.frame = CGRectMake(24.0, CGRectGetMidY(self.view.bounds) - 40.0, width, 80.0);
}

@end

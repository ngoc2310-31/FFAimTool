// ViewController.m — FF AimTool control panel UI
// Giao diện: dark gaming theme, toggle aim đầu/cổ, FOV slider, status

#import "ViewController.h"
#import "AimEngine.h"
#import <UIKit/UIKit.h>

@interface ViewController ()

// UI elements
@property (nonatomic, strong) UIView       *cardMain;
@property (nonatomic, strong) UILabel      *lblTitle;
@property (nonatomic, strong) UILabel      *lblStatus;
@property (nonatomic, strong) UISwitch     *switchAim;
@property (nonatomic, strong) UILabel      *lblSwitchAim;
@property (nonatomic, strong) UISegmentedControl *segTarget;
@property (nonatomic, strong) UISlider     *sliderFov;
@property (nonatomic, strong) UILabel      *lblFov;
@property (nonatomic, strong) UIButton     *btnConnect;
@property (nonatomic, strong) UILabel      *lblInstructions;

// Status timer
@property (nonatomic, strong) NSTimer      *uiTimer;

@end

@implementation ViewController

// ── Color palette ──────────────────────────────────────────────────────────
static UIColor* clrBg()     { return [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:1]; }
static UIColor* clrCard()   { return [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:1]; }
static UIColor* clrGreen()  { return [UIColor colorWithRed:0.18 green:0.90 blue:0.44 alpha:1]; }
static UIColor* clrRed()    { return [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1]; }
static UIColor* clrBlue()   { return [UIColor colorWithRed:0.25 green:0.55 blue:1.00 alpha:1]; }
static UIColor* clrDim()    { return [UIColor colorWithWhite:0.5 alpha:1]; }
static UIColor* clrWhite()  { return UIColor.whiteColor; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildUI];
    
    // Cập nhật status mỗi 0.5s
    self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
        target:self selector:@selector(refreshStatus) userInfo:nil repeats:YES];
    
    [[AimEngine shared] startAimLoop];
}

// ── Build UI ──────────────────────────────────────────────────────────────
- (void)buildUI {
    self.view.backgroundColor = clrBg();
    
    CGFloat W = self.view.bounds.size.width;
    CGFloat pad = 20;
    CGFloat cardW = W - pad*2;
    CGFloat y = 80;
    
    // ── Title ──────────────────────────────────────────────────────────
    self.lblTitle = [self label:@"FF AimTool"
                           font:[UIFont boldSystemFontOfSize:28]
                          color:clrGreen()
                          frame:CGRectMake(pad, y, cardW, 36)];
    self.lblTitle.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.lblTitle];
    y += 44;
    
    UILabel *sub = [self label:@"Free Fire Aimlock Controller"
                          font:[UIFont systemFontOfSize:13]
                         color:clrDim()
                         frame:CGRectMake(pad, y, cardW, 20)];
    sub.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:sub];
    y += 36;
    
    // ── Status card ────────────────────────────────────────────────────
    UIView *statusCard = [self card:CGRectMake(pad, y, cardW, 56)];
    [self.view addSubview:statusCard];
    
    self.lblStatus = [self label:@"⚪ Chưa kết nối"
                            font:[UIFont systemFontOfSize:14]
                           color:clrDim()
                           frame:CGRectMake(12, 8, cardW-24, 40)];
    self.lblStatus.textAlignment = NSTextAlignmentCenter;
    self.lblStatus.numberOfLines = 2;
    [statusCard addSubview:self.lblStatus];
    y += 68;
    
    // ── Connect button ─────────────────────────────────────────────────
    self.btnConnect = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btnConnect.frame = CGRectMake(pad, y, cardW, 48);
    self.btnConnect.backgroundColor = clrBlue();
    self.btnConnect.layer.cornerRadius = 12;
    [self.btnConnect setTitle:@"🔗  Kết nối Free Fire" forState:UIControlStateNormal];
    [self.btnConnect setTitleColor:clrWhite() forState:UIControlStateNormal];
    self.btnConnect.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.btnConnect addTarget:self action:@selector(onConnect) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btnConnect];
    y += 60;
    
    // ── Main control card ──────────────────────────────────────────────
    self.cardMain = [self card:CGRectMake(pad, y, cardW, 220)];
    [self.view addSubview:self.cardMain];
    
    CGFloat cy = 16;
    
    // Aim ON/OFF switch
    UILabel *lSwitch = [self label:@"AIMLOCK"
                              font:[UIFont boldSystemFontOfSize:13]
                             color:clrWhite()
                             frame:CGRectMake(16, cy, 120, 28)];
    [self.cardMain addSubview:lSwitch];
    
    self.switchAim = [[UISwitch alloc] initWithFrame:CGRectMake(cardW-80, cy, 51, 28)];
    self.switchAim.onTintColor = clrGreen();
    [self.switchAim addTarget:self action:@selector(onToggleAim:) forControlEvents:UIControlEventValueChanged];
    [self.cardMain addSubview:self.switchAim];
    cy += 48;
    
    // Divider
    UIView *div1 = [[UIView alloc] initWithFrame:CGRectMake(16, cy, cardW-32, 1)];
    div1.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.cardMain addSubview:div1];
    cy += 12;
    
    // Target selection
    UILabel *lTarget = [self label:@"Vị trí ngắm"
                              font:[UIFont systemFontOfSize:13]
                             color:clrDim()
                             frame:CGRectMake(16, cy, 120, 24)];
    [self.cardMain addSubview:lTarget];
    cy += 28;
    
    self.segTarget = [[UISegmentedControl alloc]
                      initWithItems:@[@"🎯  ĐẦU", @"🎯  CỔ"]];
    self.segTarget.frame = CGRectMake(16, cy, cardW-32, 40);
    self.segTarget.selectedSegmentIndex = 0;
    self.segTarget.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    [self.segTarget setTitleTextAttributes:@{NSForegroundColorAttributeName: clrWhite()}
                                  forState:UIControlStateNormal];
    [self.segTarget setTitleTextAttributes:@{NSForegroundColorAttributeName: clrBg()}
                                  forState:UIControlStateSelected];
    [self.segTarget addTarget:self action:@selector(onTargetChange:)
             forControlEvents:UIControlEventValueChanged];
    [self.cardMain addSubview:self.segTarget];
    cy += 52;
    
    // Divider
    UIView *div2 = [[UIView alloc] initWithFrame:CGRectMake(16, cy, cardW-32, 1)];
    div2.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.cardMain addSubview:div2];
    cy += 12;
    
    // FOV slider
    self.lblFov = [self label:@"FOV: 30°"
                         font:[UIFont systemFontOfSize:13]
                        color:clrDim()
                        frame:CGRectMake(16, cy, cardW-32, 24)];
    [self.cardMain addSubview:self.lblFov];
    cy += 28;
    
    self.sliderFov = [[UISlider alloc] initWithFrame:CGRectMake(16, cy, cardW-32, 28)];
    self.sliderFov.minimumValue = 5;
    self.sliderFov.maximumValue = 90;
    self.sliderFov.value        = 30;
    self.sliderFov.minimumTrackTintColor = clrGreen();
    self.sliderFov.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1];
    [self.sliderFov addTarget:self action:@selector(onFovChange:)
             forControlEvents:UIControlEventValueChanged];
    [self.cardMain addSubview:self.sliderFov];
    
    y += 232;
    
    // ── Instructions ───────────────────────────────────────────────────
    NSString *instrText =
        @"Hướng dẫn:\n"
        @"1. Mở Free Fire trước\n"
        @"2. Nhấn 'Kết nối Free Fire'\n"
        @"3. Bật Aimlock → chọn Đầu hoặc Cổ\n"
        @"4. Vào game, aim tự động bật\n\n"
        @"⚠️ Yêu cầu: FF đã inject AimLock.dylib";
    
    UIView *instrCard = [self card:CGRectMake(pad, y, cardW, 160)];
    [self.view addSubview:instrCard];
    
    self.lblInstructions = [self label:instrText
                                  font:[UIFont systemFontOfSize:12]
                                 color:clrDim()
                                 frame:CGRectMake(16, 12, cardW-32, 136)];
    self.lblInstructions.numberOfLines = 0;
    [instrCard addSubview:self.lblInstructions];
}

// ── Actions ───────────────────────────────────────────────────────────────
- (void)onConnect {
    [self.btnConnect setTitle:@"⏳  Đang kết nối..." forState:UIControlStateNormal];
    self.btnConnect.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        BOOL ok = [[AimEngine shared] attachToFreefire];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.btnConnect.enabled = YES;
            [self.btnConnect setTitle:@"🔗  Kết nối Free Fire"
                             forState:UIControlStateNormal];
            self.btnConnect.backgroundColor = ok ? clrGreen() : clrRed();
            [self refreshStatus];
        });
    });
}

- (void)onToggleAim:(UISwitch *)sw {
    [AimEngine shared].enabled = sw.isOn;
    [self refreshStatus];
}

- (void)onTargetChange:(UISegmentedControl *)seg {
    [AimEngine shared].targetBone = (AimTarget)seg.selectedSegmentIndex;
    [self refreshStatus];
}

- (void)onFovChange:(UISlider *)sl {
    float v = roundf(sl.value);
    [AimEngine shared].fovDegrees = v;
    self.lblFov.text = [NSString stringWithFormat:@"FOV: %.0f°", v];
}

- (void)refreshStatus {
    NSString *s = [AimEngine shared].status;
    self.lblStatus.text = s;
    
    BOOL on = [AimEngine shared].enabled;
    self.lblStatus.textColor = on ? clrGreen() : clrDim();
    self.switchAim.on = on;
}

// ── Helpers ───────────────────────────────────────────────────────────────
- (UILabel *)label:(NSString *)text
               font:(UIFont *)font
              color:(UIColor *)color
              frame:(CGRect)frame {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text      = text;
    l.font      = font;
    l.textColor = color;
    l.backgroundColor = UIColor.clearColor;
    return l;
}

- (UIView *)card:(CGRect)frame {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor    = clrCard();
    v.layer.cornerRadius = 16;
    v.layer.borderWidth  = 1;
    v.layer.borderColor  = [UIColor colorWithWhite:0.2 alpha:0.5].CGColor;
    return v;
}

- (void)dealloc {
    [self.uiTimer invalidate];
    [[AimEngine shared] detach];
}

@end

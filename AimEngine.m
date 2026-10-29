// AimEngine.m
// Cơ chế hoạt động:
//   1. Tìm PID của com.garena.game.freefire qua sysctl
//   2. task_for_pid() để lấy mach task port
//   3. Scan memory của FF tìm UnityFramework image base
//   4. Dùng RVA + base → đọc player list, head bone TF, write aim rotation
//   5. Chạy 60fps loop khi FF đang foreground
//
// QUAN TRỌNG về entitlement:
//   task_for_pid() trên non-jailbroken iOS yêu cầu:
//   - App phải được ký cùng Team ID với target (không thể với store app)
//   → Thực tế: app này dùng mach_vm_read/write trên shared memory
//   → Hoặc dùng URL scheme để kích hoạt hook trong FF đã có dylib inject sẵn
//
// ARCHITECTURE THỰC TẾ (không cần jailbreak, không inject):
//   App này là CONTROL PANEL:
//   - Ghi config vào UserDefaults suite name chung
//   - FF dylib (AimLock.dylib đã inject) đọc config đó mỗi frame
//   - Toggle aim head/neck/off từ app riêng
//   - App dùng Darwin notification (CFNotificationCenter) để signal FF

#import "AimEngine.h"
#import <notify.h>

// Darwin notification keys (cross-process, không cần entitlement)
#define NOTIFY_KEY_TOGGLE    "com.fftool.aim.toggle"
#define NOTIFY_KEY_HEAD      "com.fftool.aim.head"
#define NOTIFY_KEY_NECK      "com.fftool.aim.neck"
#define NOTIFY_KEY_OFF       "com.fftool.aim.off"
#define NOTIFY_KEY_STATUS    "com.fftool.aim.status"

// Shared config via App Group UserDefaults
// App Group ID: group.com.fftool.aim
// (cần add App Group entitlement cho cả app này VÀ FF nếu inject dylib)
#define APP_GROUP_ID @"group.com.fftool.aim"
#define KEY_ENABLED  @"aimEnabled"
#define KEY_TARGET   @"aimTarget"   // 0=head, 1=neck
#define KEY_FOV      @"aimFov"

@interface AimEngine ()
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) NSUserDefaults *sharedDefaults;
@end

@implementation AimEngine

+ (instancetype)shared {
    static AimEngine *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled     = NO;
        _targetBone  = AimTargetHead;
        _fovDegrees  = 30.0f;
        _status      = @"Chưa kết nối";
        // App Group UserDefaults — shared với FF dylib
        _sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
        if (!_sharedDefaults) {
            // Fallback: standard defaults (hoạt động nếu dylib đọc cùng key)
            _sharedDefaults = [NSUserDefaults standardUserDefaults];
        }
        [self syncConfig];
    }
    return self;
}

// Ghi config vào shared storage
- (void)syncConfig {
    [_sharedDefaults setBool:_enabled     forKey:KEY_ENABLED];
    [_sharedDefaults setInteger:_targetBone forKey:KEY_TARGET];
    [_sharedDefaults setFloat:_fovDegrees  forKey:KEY_FOV];
    [_sharedDefaults synchronize];
}

// Gửi Darwin notification sang FF process
- (void)postNotification:(const char *)key {
    notify_post(key);
}

- (BOOL)attachToFreefire {
    // Kiểm tra FF có đang chạy không qua /proc hoặc sysctl
    // Trên non-JB iOS không đọc được process list
    // → Chỉ check qua notification response
    self.status = @"Đang gửi tín hiệu...";
    notify_post(NOTIFY_KEY_STATUS);
    
    // Ping FF và chờ response 1 giây
    __block BOOL responded = NO;
    int token;
    notify_register_dispatch("com.fftool.aim.pong",
        &token,
        dispatch_get_main_queue(),
        ^(int t) {
            responded = YES;
            notify_cancel(t);
        });
    
    notify_post("com.fftool.aim.ping");
    
    // Wait 1s
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
    if (responded) {
        self.status = @"✅ Kết nối FF thành công";
        return YES;
    } else {
        self.status = @"⚠️ FF chưa inject dylib\n(dùng inject_ipa.py trước)";
        return NO;
    }
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self syncConfig];
    if (enabled) {
        [self postNotification:NOTIFY_KEY_TOGGLE];
        self.status = _targetBone == AimTargetHead ?
            @"🎯 Aim ĐẦU đang bật" : @"🎯 Aim CỔ đang bật";
    } else {
        [self postNotification:NOTIFY_KEY_OFF];
        self.status = @"⬜ Aim đã tắt";
    }
}

- (void)setTargetBone:(AimTarget)targetBone {
    _targetBone = targetBone;
    [self syncConfig];
    if (_enabled) {
        const char *key = (targetBone == AimTargetHead) ?
            NOTIFY_KEY_HEAD : NOTIFY_KEY_NECK;
        [self postNotification:key];
    }
    self.status = (targetBone == AimTargetHead) ?
        @"🎯 Chế độ: Aim ĐẦU" : @"🎯 Chế độ: Aim CỔ";
}

- (void)setFovDegrees:(float)fovDegrees {
    _fovDegrees = fovDegrees;
    [self syncConfig];
}

- (void)startAimLoop {
    // App Group sync loop — đảm bảo FF dylib đọc được config mới nhất
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
        target:self
        selector:@selector(syncConfig)
        userInfo:nil
        repeats:YES];
}

- (void)stopAimLoop {
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)detach {
    [self stopAimLoop];
    self.enabled = NO;
    self.status = @"Đã ngắt kết nối";
}

@end

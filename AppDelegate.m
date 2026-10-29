// AppDelegate.m
#import "AppDelegate.h"
#import "ViewController.h"
#import "AimEngine.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[ViewController alloc] init];
    self.window.backgroundColor = [UIColor colorWithRed:0.06 green:0.06
                                                   blue:0.08 alpha:1];
    [self.window makeKeyAndVisible];
    return YES;
}

// Giữ app chạy background (cần entitlement audio/location để thực sự background)
// Với foreground only: mỗi lần mở app re-sync config là đủ
- (void)applicationDidEnterBackground:(UIApplication *)app {
    [[AimEngine shared] syncConfig];
}

- (void)applicationWillEnterForeground:(UIApplication *)app {
    [[AimEngine shared] startAimLoop];
}

@end

// main.m — FF AimTool standalone iOS app
// Build: Xcode, target iOS 13+, bundle ID: com.fftool.aim
// Cơ chế: dùng task_for_pid() để đọc/ghi memory process FF
// KHÔNG cần jailbreak nếu cùng developer cert (same team ID)
// Nếu khác cert: cần entitlement com.apple.developer.kernel.increased-memory-limit
// hoặc dùng chế độ GCDAsyncSocket để trigger qua URL scheme

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}

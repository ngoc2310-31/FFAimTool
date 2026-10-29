// AimEngine.h — core memory read/write engine targeting Free Fire process
// Không cần jailbreak: dùng task_for_pid với same-team-ID signing
// Hoặc dùng mach_vm_read trên shared memory region

#import <Foundation/Foundation.h>
#import <mach/mach.h>

typedef enum : NSInteger {
    AimTargetHead = 0,
    AimTargetNeck = 1,
} AimTarget;

typedef struct {
    float x, y, z, w;
} Quaternion;

typedef struct {
    float x, y, z;
} Vector3;

@interface AimEngine : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) AimTarget targetBone;  // head hoặc neck
@property (nonatomic, assign) float fovDegrees;       // default 30°
@property (nonatomic, copy)   NSString *status;

+ (instancetype)shared;
- (BOOL)attachToFreefire;   // tìm và attach vào process FF
- (void)startAimLoop;       // bắt đầu vòng lặp aim (60fps timer)
- (void)stopAimLoop;
- (void)detach;

@end

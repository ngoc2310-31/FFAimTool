// AimLock_v2.mm — dylib inject vào Free Fire
// Phiên bản 2: lắng nghe Darwin notification từ app riêng (FFAimTool)
// + đọc config từ App Group UserDefaults
//
// language: Objective-C++, target: iOS ARM64
// build: clang++ -arch arm64 -std=c++17 -ObjC++ -framework Foundation
//        -framework UIKit -framework CoreMotion -L. -ldobby
//        -shared -o AimLock.dylib AimLock_v2.mm

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <notify.h>
#include <unordered_set>
#include <cmath>

extern "C" {
    int DobbyHook(void* address, void* replace_fn, void** original_fn);
}

// ── Value types ───────────────────────────────────────────────────────────
struct Vector3   { float x, y, z; };
struct Quaternion{ float x, y, z, w; };

static inline Vector3 v3_sub(Vector3 a, Vector3 b){ return {a.x-b.x,a.y-b.y,a.z-b.z}; }
static inline float   v3_dot(Vector3 a, Vector3 b){ return a.x*b.x+a.y*b.y+a.z*b.z; }
static inline float   v3_len(Vector3 a)            { return sqrtf(v3_dot(a,a)); }
static inline Vector3 v3_norm(Vector3 a) {
    float l=v3_len(a); return l>1e-5f?Vector3{a.x/l,a.y/l,a.z/l}:Vector3{0,0,1};
}

static Quaternion look_rotation(Vector3 fwd, Vector3 up={0,1,0}) {
    fwd=v3_norm(fwd);
    Vector3 right=v3_norm({up.y*fwd.z-up.z*fwd.y, up.z*fwd.x-up.x*fwd.z, up.x*fwd.y-up.y*fwd.x});
    up={fwd.y*right.z-fwd.z*right.y, fwd.z*right.x-fwd.x*right.z, fwd.x*right.y-fwd.y*right.x};
    float trace=right.x+up.y+fwd.z; Quaternion q;
    if(trace>0){ float s=0.5f/sqrtf(trace+1); q.w=0.25f/s; q.x=(up.z-fwd.y)*s; q.y=(fwd.x-right.z)*s; q.z=(right.y-up.x)*s; }
    else if(right.x>up.y&&right.x>fwd.z){ float s=2*sqrtf(1+right.x-up.y-fwd.z); q.w=(up.z-fwd.y)/s; q.x=0.25f*s; q.y=(right.y+up.x)/s; q.z=(fwd.x+right.z)/s; }
    else if(up.y>fwd.z){ float s=2*sqrtf(1+up.y-right.x-fwd.z); q.w=(fwd.x-right.z)/s; q.x=(right.y+up.x)/s; q.y=0.25f*s; q.z=(up.z+fwd.y)/s; }
    else{ float s=2*sqrtf(1+fwd.z-right.x-up.y); q.w=(right.y-up.x)/s; q.x=(fwd.x+right.z)/s; q.y=(up.z+fwd.y)/s; q.z=0.25f*s; }
    return q;
}

// ── IL2CPP function pointers ──────────────────────────────────────────────
typedef Vector3    (*Transform_GetPos_f)(void*,void*);
typedef Vector3    (*Transform_GetFwd_f)(void*,void*);
typedef void*      (*Player_GetHeadBoneTF_f)(void*,void*);
typedef void*      (*Player_GetHeadTF_f)(void*,void*);
typedef void*      (*Player_GetCamTF_f)(void*,void*);
typedef Quaternion (*Player_GetAimRot_f)(void*,void*);
typedef void       (*Player_SetAimRot_f)(void*,Quaternion,void*);
typedef void       (*Player_UpdateAiming_f)(void*,void*);
typedef void       (*MatchGame_OnAddPlayer_f)(void*,void*,void*);
typedef void       (*MatchGame_OnDelPlayer_f)(void*,void*,void*);

// ── RVAs (từ ff-offsets.zip) ──────────────────────────────────────────────
static const uintptr_t kRVA_UpdateAiming    = 0x6F8EE08;
static const uintptr_t kRVA_GetHeadBoneTF  = 0x6F2F4B8;
static const uintptr_t kRVA_GetHeadTF      = 0x6FAE37C;
static const uintptr_t kRVA_SetAimRotation = 0x6F2C794;
static const uintptr_t kRVA_GetCamTF       = 0x6F26C3C;
static const uintptr_t kRVA_OnAddPlayer    = 0x731F164;
static const uintptr_t kRVA_OnDelPlayer    = 0x731F1BC;
static const uintptr_t kRVA_Transform_GetPos= 0x9FE5A68;
static const uintptr_t kRVA_Transform_GetFwd= 0x9FE6040;

// ── Player field offsets ──────────────────────────────────────────────────
static const ptrdiff_t kOff_IsFrozenKnockDown = 0x0B0;
static const ptrdiff_t kOff_MainCamTF         = 0x3E8;
static const ptrdiff_t kOff_TeamModeID        = 0x434;
static const ptrdiff_t kOff_IsKnockedDownBleed= 0x1258;
static const ptrdiff_t kOff_CurrentAimRot     = 0x1A8C;

// ── Config keys (đồng bộ với FFAimTool app) ──────────────────────────────
#define APP_GROUP   @"group.com.fftool.aim"
#define KEY_ENABLED @"aimEnabled"
#define KEY_TARGET  @"aimTarget"   // 0=head, 1=neck
#define KEY_FOV     @"aimFov"

// ── Global state ──────────────────────────────────────────────────────────
static uintptr_t  g_base         = 0;
static void*      g_localPlayer  = nullptr;
static pthread_mutex_t g_playersMtx = PTHREAD_MUTEX_INITIALIZER;
static std::unordered_set<void*> g_players;

// Config — đọc từ App Group / Darwin notify
static volatile bool  g_enabled    = false;
static volatile int   g_targetBone = 0;    // 0=head, 1=neck(fallback=head)
static volatile float g_fovDeg     = 30.0f;
static UILabel*       g_hud        = nil;

// Function pointers
static Transform_GetPos_f      fp_GetPos      = nullptr;
static Transform_GetFwd_f      fp_GetFwd      = nullptr;
static Player_GetHeadBoneTF_f  fp_GetHeadBoneTF= nullptr;
static Player_GetHeadTF_f      fp_GetHeadTF   = nullptr;
static Player_GetCamTF_f       fp_GetCamTF    = nullptr;
static Player_SetAimRot_f      fp_SetAimRot   = nullptr;

// Original hooks
static Player_UpdateAiming_f    orig_UpdateAiming = nullptr;
static MatchGame_OnAddPlayer_f  orig_OnAddPlayer  = nullptr;
static MatchGame_OnDelPlayer_f  orig_OnDelPlayer  = nullptr;

// ── Read config from App Group UserDefaults ───────────────────────────────
static void read_config() {
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP];
    if (ud) {
        g_enabled    = [ud boolForKey:KEY_ENABLED];
        g_targetBone = (int)[ud integerForKey:KEY_TARGET];
        float fov    = [ud floatForKey:KEY_FOV];
        g_fovDeg     = (fov > 0) ? fov : 30.0f;
    }
}

// ── Update HUD ────────────────────────────────────────────────────────────
static void update_hud() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_hud) return;
        if (!g_enabled) {
            g_hud.text      = @"⬜ OFF";
            g_hud.textColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];
        } else {
            NSString *mode  = (g_targetBone == 0) ? @"ĐẦU" : @"CỔ";
            g_hud.text      = [NSString stringWithFormat:@"🎯 %@", mode];
            g_hud.textColor = [UIColor colorWithRed:0.18 green:0.90 blue:0.44 alpha:1];
        }
    });
}

// ── Darwin notification handlers ──────────────────────────────────────────
static void setup_notifications() {
    // Lắng nghe lệnh từ FFAimTool app
    int token_toggle, token_head, token_neck, token_off, token_ping;

    notify_register_dispatch("com.fftool.aim.toggle",
        &token_toggle, dispatch_get_global_queue(0,0), ^(int t) {
        g_enabled = !g_enabled; read_config(); update_hud();
    });
    notify_register_dispatch("com.fftool.aim.head",
        &token_head, dispatch_get_global_queue(0,0), ^(int t) {
        g_targetBone = 0; g_enabled = true; read_config(); update_hud();
    });
    notify_register_dispatch("com.fftool.aim.neck",
        &token_neck, dispatch_get_global_queue(0,0), ^(int t) {
        g_targetBone = 1; g_enabled = true; read_config(); update_hud();
    });
    notify_register_dispatch("com.fftool.aim.off",
        &token_off, dispatch_get_global_queue(0,0), ^(int t) {
        g_enabled = false; update_hud();
    });
    // Ping/pong: app hỏi "FF có dylib không?" — dylib trả lời
    notify_register_dispatch("com.fftool.aim.ping",
        &token_ping, dispatch_get_global_queue(0,0), ^(int t) {
        notify_post("com.fftool.aim.pong");
    });
}

// ── Helper ────────────────────────────────────────────────────────────────
static inline bool   pl_bool(void* p,ptrdiff_t o){ return *reinterpret_cast<bool*>   ((char*)p+o); }
static inline int32_t pl_i32(void* p,ptrdiff_t o){ return *reinterpret_cast<int32_t*>((char*)p+o); }
static inline void*  pl_ptr(void* p,ptrdiff_t o) { return *reinterpret_cast<void**>  ((char*)p+o); }

// ── Core aimlock ─────────────────────────────────────────────────────────
static bool do_aimlock(void* self) {
    if (!fp_GetCamTF||!fp_GetPos||!fp_GetHeadBoneTF||!fp_SetAimRot) return false;

    void* camTF = pl_ptr(self, kOff_MainCamTF);
    if (!camTF) camTF = fp_GetCamTF(self, nullptr);
    if (!camTF) return false;

    Vector3 camPos = fp_GetPos(camTF, nullptr);
    Vector3 camFwd = fp_GetFwd(camTF, nullptr);
    int32_t myTeam = pl_i32(self, kOff_TeamModeID);
    float   maxFov = g_fovDeg * (float)M_PI / 180.0f;

    float bestAngle = maxFov;
    void* bestTarget= nullptr;
    Vector3 bestDir = {};

    pthread_mutex_lock(&g_playersMtx);
    for (void* p : g_players) {
        if (p==self) continue;
        if (pl_bool(p,kOff_IsFrozenKnockDown)) continue;
        if (pl_bool(p,kOff_IsKnockedDownBleed)) continue;
        if (pl_i32(p,kOff_TeamModeID)==myTeam)  continue;

        // Lấy head bone (hoặc neck = head fallback vì Unity không có neck riêng)
        void* boneTF = fp_GetHeadBoneTF(p, nullptr);
        if (!boneTF && fp_GetHeadTF) boneTF = fp_GetHeadTF(p, nullptr);
        if (!boneTF) continue;

        Vector3 bonePos = fp_GetPos(boneTF, nullptr);

        // Nếu aim cổ: offset xuống một chút so với đầu (~0.15 unit)
        if (g_targetBone == 1) bonePos.y -= 0.15f;

        Vector3 dir  = v3_sub(bonePos, camPos);
        float   dist = v3_len(dir);
        if (dist < 0.1f) continue;
        dir = v3_norm(dir);

        float dot   = v3_dot(camFwd, dir);
        dot = dot>1?1:(dot<-1?-1:dot);
        float angle = acosf(dot);

        if (angle < bestAngle) {
            bestAngle  = angle;
            bestTarget = p;
            bestDir    = dir;
        }
    }
    pthread_mutex_unlock(&g_playersMtx);

    if (!bestTarget) return false;

    Quaternion q = look_rotation(bestDir, {0,1,0});
    *reinterpret_cast<Quaternion*>((char*)self+kOff_CurrentAimRot) = q;
    fp_SetAimRot(self, q, nullptr);
    return true;
}

// ── Hooks ─────────────────────────────────────────────────────────────────
static void hook_UpdateAiming(void* self, void* mi) {
    if (!g_localPlayer) g_localPlayer = self;
    if (g_enabled && self == g_localPlayer) do_aimlock(self);
    if (orig_UpdateAiming) orig_UpdateAiming(self, mi);
}

static void hook_OnAddPlayer(void* self, void* player, void* mi) {
    if (player) {
        pthread_mutex_lock(&g_playersMtx);
        g_players.insert(player);
        pthread_mutex_unlock(&g_playersMtx);
    }
    if (orig_OnAddPlayer) orig_OnAddPlayer(self, player, mi);
}

static void hook_OnDelPlayer(void* self, void* player, void* mi) {
    if (player) {
        pthread_mutex_lock(&g_playersMtx);
        g_players.erase(player);
        pthread_mutex_unlock(&g_playersMtx);
    }
    if (orig_OnDelPlayer) orig_OnDelPlayer(self, player, mi);
}

// ── Find UnityFramework base ──────────────────────────────────────────────
static uintptr_t find_unity_base() {
    for (uint32_t i=0; i<_dyld_image_count(); i++) {
        const char* n=_dyld_get_image_name(i);
        if (n && (strstr(n,"UnityFramework")||strstr(n,"Garena")||strstr(n,"FreeFire")))
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

// ── Setup HUD ─────────────────────────────────────────────────────────────
static void setup_hud() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        UIWindow* win=nil;
        for(UIScene* sc in UIApplication.sharedApplication.connectedScenes) {
            win=((UIWindowScene*)sc).windows.firstObject;
            if(win) break;
        }
        if(!win) return;
        g_hud=[[UILabel alloc] initWithFrame:CGRectMake(10,60,90,30)];
        g_hud.text=@"⬜ OFF";
        g_hud.textColor=[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];
        g_hud.font=[UIFont boldSystemFontOfSize:13];
        g_hud.backgroundColor=[UIColor colorWithWhite:0 alpha:0.5];
        g_hud.layer.cornerRadius=8; g_hud.clipsToBounds=YES;
        g_hud.textAlignment=NSTextAlignmentCenter;
        [win addSubview:g_hud];
    });
}

// ── Entry point ───────────────────────────────────────────────────────────
__attribute__((constructor))
static void al_init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),
                   dispatch_get_global_queue(0,0), ^{
        g_base = find_unity_base();
        if (!g_base) { NSLog(@"[AimLock] UnityFramework not found"); return; }

        // Đọc config ban đầu từ FFAimTool app
        read_config();

        // Resolve function pointers
        fp_GetPos        = (Transform_GetPos_f)    (g_base+kRVA_Transform_GetPos);
        fp_GetFwd        = (Transform_GetFwd_f)    (g_base+kRVA_Transform_GetFwd);
        fp_GetHeadBoneTF = (Player_GetHeadBoneTF_f)(g_base+kRVA_GetHeadBoneTF);
        fp_GetHeadTF     = (Player_GetHeadTF_f)    (g_base+kRVA_GetHeadTF);
        fp_GetCamTF      = (Player_GetCamTF_f)     (g_base+kRVA_GetCamTF);
        fp_SetAimRot     = (Player_SetAimRot_f)    (g_base+kRVA_SetAimRotation);

        // Install hooks
        DobbyHook((void*)(g_base+kRVA_UpdateAiming),
                  (void*)hook_UpdateAiming, (void**)&orig_UpdateAiming);
        DobbyHook((void*)(g_base+kRVA_OnAddPlayer),
                  (void*)hook_OnAddPlayer,  (void**)&orig_OnAddPlayer);
        DobbyHook((void*)(g_base+kRVA_OnDelPlayer),
                  (void*)hook_OnDelPlayer,  (void**)&orig_OnDelPlayer);

        // Lắng nghe lệnh từ FFAimTool app
        setup_notifications();

        // HUD trong FF
        setup_hud();

        // Sync config mỗi 1 giây (đọc lại từ App Group)
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:1.0
                target:[NSBlockOperation blockOperationWithBlock:^{ read_config(); update_hud(); }]
                selector:@selector(main)
                userInfo:nil
                repeats:YES];
        });

        NSLog(@"[AimLock v2] Loaded — chờ lệnh từ FFAimTool app");
    });
}

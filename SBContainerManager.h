#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SBAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *dataPath;
@property (nonatomic, copy, nullable) NSString *bundlePath;
@property (nonatomic, copy, nullable) NSString *executableName;
@property (nonatomic, copy, nullable) NSString *teamID;
/// groupID -> absolute path
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *groupPaths;
@property (nonatomic, assign) NSUInteger profileCount;
@property (nonatomic, copy, nullable) NSString *activeProfileID;
@property (nonatomic, strong, nullable) UIImage *icon;
@end

@interface SBProfileInfo : NSObject
@property (nonatomic, copy) NSString *profileID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
@property (nonatomic, assign) unsigned long long sizeBytes;
@property (nonatomic, assign) BOOL isActive;
/// 创建时是否重置设备识别码
@property (nonatomic, assign) BOOL resetDeviceIDs;
/// 设备 UUID 短展示（前 8 位）
@property (nonatomic, copy, nullable) NSString *deviceUUIDShort;
@end

typedef void (^SBProgressBlock)(NSString *message, double progress /* 0..1, -1 = indeterminate */);
typedef void (^SBDoneBlock)(NSError * _Nullable error);

@interface SBContainerManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSString *storeRoot;

- (NSArray<SBAppInfo *> *)listUserApps;
- (nullable SBAppInfo *)appInfoForBundleID:(NSString *)bundleID;

- (NSArray<SBProfileInfo *> *)profilesForBundleID:(NSString *)bundleID;
- (nullable NSString *)activeProfileIDForBundleID:(NSString *)bundleID;

- (void)createProfileFromCurrentForBundleID:(NSString *)bundleID
                                       name:(NSString *)name
                                  progress:(nullable SBProgressBlock)progress
                                completion:(SBDoneBlock)completion;

/// 新建空配置；可选择重置设备识别码并立刻应用到目标 App 容器
- (void)createFreshProfileForBundleID:(NSString *)bundleID
                                 name:(NSString *)name
                      resetDeviceIDs:(BOOL)resetDeviceIDs
                            progress:(nullable SBProgressBlock)progress
                          completion:(SBDoneBlock)completion;

/// 读取配置的设备识别码元数据（device.plist）
- (nullable NSDictionary *)deviceIdentityForProfile:(NSString *)profileID
                                          bundleID:(NSString *)bundleID;

/// 生成一套新的本地设备识别码种子
- (NSDictionary *)generateDeviceIdentity;

/// 规范化用户输入的识别码（UUID 大小写、OpenUDID 去横线等）
- (NSDictionary *)normalizedDeviceIdentity:(NSDictionary *)identity;

/// 保存并写入配置；可选立即应用到当前运行容器（会先关闭 App）
- (void)updateDeviceIdentity:(NSDictionary *)identity
                  forProfile:(NSString *)profileID
                    bundleID:(NSString *)bundleID
                 applyToLive:(BOOL)applyToLive
                scrubExisting:(BOOL)scrubExisting
                    progress:(nullable SBProgressBlock)progress
                  completion:(SBDoneBlock)completion;

- (void)switchToProfile:(NSString *)profileID
              bundleID:(NSString *)bundleID
     saveCurrentAsName:(nullable NSString *)autoSaveName
              progress:(nullable SBProgressBlock)progress
            completion:(SBDoneBlock)completion;

- (void)deleteProfile:(NSString *)profileID
             bundleID:(NSString *)bundleID
                error:(NSError * _Nullable * _Nullable)error;

- (void)renameProfile:(NSString *)profileID
             bundleID:(NSString *)bundleID
               toName:(NSString *)name
                error:(NSError * _Nullable * _Nullable)error;

- (BOOL)terminateApp:(NSString *)bundleID error:(NSError * _Nullable * _Nullable)error;
- (BOOL)openApp:(NSString *)bundleID error:(NSError * _Nullable * _Nullable)error;

- (NSString *)humanSize:(unsigned long long)bytes;

@end

NS_ASSUME_NONNULL_END

#import "SBContainerManager.h"
#import "SBSettings.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <dirent.h>
#import <sys/sysctl.h>
#import <sys/param.h>
#import <signal.h>
#import <unistd.h>
#import <stdlib.h>
#import <string.h>
#import <Security/Security.h>

// Private LaunchServices bits
@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
- (NSString *)itemName;
- (NSURL *)bundleURL;
- (NSURL *)dataContainerURL;
- (NSURL *)bundleContainerURL;
- (NSDictionary *)groupContainerURLs;
- (NSString *)teamID;
- (id)applicationType;
- (NSDictionary *)iconsDictionary;
- (BOOL)isPlaceholder;
- (BOOL)isRestricted;
- (BOOL)isRemovedSystemApp;
- (id)executableName; // may be NSString
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
- (void)enumerateBundlesOfType:(NSUInteger)type usingBlock:(void (^)(LSApplicationProxy *proxy))block;
@end

@implementation SBAppInfo
@end

@implementation SBProfileInfo
@end

@interface SBContainerManager ()
@property (nonatomic, copy) NSString *storeRoot;
@end

@implementation SBContainerManager

+ (instancetype)shared {
	static SBContainerManager *m;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		m = [[self alloc] init];
	});
	return m;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		// Prefer absolute path; works with no-sandbox / platform-application
		NSArray *candidates = @[
			@"/var/mobile/Library/SwitchBox",
			[NSHomeDirectory() stringByAppendingPathComponent:@"Library/SwitchBox"],
			[NSTemporaryDirectory() stringByAppendingPathComponent:@"SwitchBox"],
		];
		NSFileManager *fm = NSFileManager.defaultManager;
		NSString *chosen = nil;
		for (NSString *p in candidates) {
			NSError *err = nil;
			if ([fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:&err] || [fm fileExistsAtPath:p]) {
				// probe write
				NSString *probe = [p stringByAppendingPathComponent:@".write_test"];
				if ([@"ok" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
					[fm removeItemAtPath:probe error:nil];
					chosen = p;
					break;
				}
			}
		}
		_storeRoot = chosen ?: candidates.lastObject;
		[fm createDirectoryAtPath:_storeRoot withIntermediateDirectories:YES attributes:nil error:nil];
	}
	return self;
}

#pragma mark - Paths

- (NSString *)bundleStore:(NSString *)bundleID {
	// sanitize
	NSString *safe = [[bundleID componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]] componentsJoinedByString:@"_"];
	return [self.storeRoot stringByAppendingPathComponent:safe];
}

- (NSString *)profilesDir:(NSString *)bundleID {
	return [[self bundleStore:bundleID] stringByAppendingPathComponent:@"profiles"];
}

- (NSString *)profileDir:(NSString *)bundleID profileID:(NSString *)profileID {
	return [[self profilesDir:bundleID] stringByAppendingPathComponent:profileID];
}

- (NSString *)metaPath:(NSString *)bundleID {
	return [[self bundleStore:bundleID] stringByAppendingPathComponent:@"meta.plist"];
}

- (NSMutableDictionary *)loadMeta:(NSString *)bundleID {
	NSString *path = [self metaPath:bundleID];
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
	return d ? [d mutableCopy] : [@{ @"activeProfileID": @"", @"profiles": @{} } mutableCopy];
}

- (void)saveMeta:(NSDictionary *)meta bundleID:(NSString *)bundleID {
	NSString *dir = [self bundleStore:bundleID];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	[meta writeToFile:[self metaPath:bundleID] atomically:YES];
}

#pragma mark - Apps

- (Class)workspaceClass {
	return NSClassFromString(@"LSApplicationWorkspace");
}

- (Class)proxyClass {
	return NSClassFromString(@"LSApplicationProxy");
}

- (NSArray<SBAppInfo *> *)listUserApps {
	NSMutableArray<SBAppInfo *> *result = [NSMutableArray array];
	Class wsClass = [self workspaceClass];
	if (!wsClass) return result;

	LSApplicationWorkspace *ws = [wsClass performSelector:@selector(defaultWorkspace)];
	NSArray *apps = nil;
	if ([ws respondsToSelector:@selector(allInstalledApplications)]) {
		apps = [ws allInstalledApplications];
	}
	if (!apps.count) return result;

	NSString *selfID = NSBundle.mainBundle.bundleIdentifier ?: @"com.o2ol.switchbox";

	for (id proxy in apps) {
		@autoreleasepool {
			if (![proxy respondsToSelector:@selector(applicationIdentifier)]) continue;
			NSString *bid = [proxy applicationIdentifier];
			if (!bid.length) continue;
			if ([bid isEqualToString:selfID]) continue;
			if ([bid hasPrefix:@"com.apple."] && ![bid containsString:@"Test"]) {
				// skip most system apps; keep none by default
				NSString *type = nil;
				if ([proxy respondsToSelector:@selector(applicationType)]) {
					id t = [proxy applicationType];
					type = [t isKindOfClass:NSString.class] ? t : [t description];
				}
				if (![type isEqualToString:@"User"]) continue;
			}
			if ([proxy respondsToSelector:@selector(isPlaceholder)] && [proxy isPlaceholder]) continue;
			if ([proxy respondsToSelector:@selector(isRemovedSystemApp)] && [proxy isRemovedSystemApp]) continue;

			NSURL *dataURL = nil;
			if ([proxy respondsToSelector:@selector(dataContainerURL)]) {
				dataURL = [proxy dataContainerURL];
			}
			// Apps without data container can't be switched meaningfully
			if (!dataURL.path.length) continue;

			// Prefer User apps; include others that have real data path under Containers
			BOOL isUserPath = [dataURL.path containsString:@"/Containers/Data/Application/"];
			if (!isUserPath) continue;

			SBAppInfo *info = [SBAppInfo new];
			info.bundleID = bid;
			NSString *name = nil;
			if ([proxy respondsToSelector:@selector(localizedName)]) name = [proxy localizedName];
			if (!name.length && [proxy respondsToSelector:@selector(itemName)]) name = [proxy itemName];
			info.name = name.length ? name : bid;
			info.dataPath = dataURL.path;
			if ([proxy respondsToSelector:@selector(bundleURL)]) {
				info.bundlePath = [[proxy bundleURL] path];
			}
			if ([proxy respondsToSelector:@selector(executableName)]) {
				id ex = [proxy executableName];
				if ([ex isKindOfClass:NSString.class]) info.executableName = ex;
			}
			if (!info.executableName.length && info.bundlePath.length) {
				NSDictionary *ip = [NSDictionary dictionaryWithContentsOfFile:[info.bundlePath stringByAppendingPathComponent:@"Info.plist"]];
				info.executableName = ip[@"CFBundleExecutable"];
			}
			info.profileCount = [self profilesForBundleID:bid].count;
			info.activeProfileID = [self activeProfileIDForBundleID:bid];
			info.icon = [self iconForProxy:proxy];
			[self fillExtraInfo:info fromProxy:proxy];
			[result addObject:info];
		}
	}

	[result sortUsingComparator:^NSComparisonResult(SBAppInfo *a, SBAppInfo *b) {
		if (a.profileCount != b.profileCount) {
			return a.profileCount > b.profileCount ? NSOrderedAscending : NSOrderedDescending;
		}
		return [a.name localizedStandardCompare:b.name];
	}];
	return result;
}

- (UIImage *)iconForProxy:(id)proxy {
	// Best-effort: read AppIcon from bundle
	NSURL *bundleURL = nil;
	if ([proxy respondsToSelector:@selector(bundleURL)]) bundleURL = [proxy bundleURL];
	if (!bundleURL) return nil;
	NSString *bundlePath = bundleURL.path;
	NSArray *candidates = @[
		@"AppIcon60x60@2x.png", @"AppIcon60x60@3x.png",
		@"icon@2x.png", @"Icon@2x.png", @"Icon.png",
		@"AppIcon76x76@2x~ipad.png"
	];
	// Also parse Assets is hard; try Info.plist CFBundleIcons
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
	NSArray *iconFiles = info[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"];
	if (![iconFiles isKindOfClass:NSArray.class]) {
		iconFiles = info[@"CFBundleIconFiles"];
	}
	NSMutableArray *tryList = [NSMutableArray array];
	if ([iconFiles isKindOfClass:NSArray.class]) {
		for (NSString *base in iconFiles) {
			[tryList addObject:[base stringByAppendingString:@"@2x.png"]];
			[tryList addObject:[base stringByAppendingString:@"@3x.png"]];
			[tryList addObject:[base stringByAppendingString:@".png"]];
			[tryList addObject:base];
		}
	}
	[tryList addObjectsFromArray:candidates];

	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *name in tryList) {
		NSString *p = [bundlePath stringByAppendingPathComponent:name];
		if ([fm fileExistsAtPath:p]) {
			UIImage *img = [UIImage imageWithContentsOfFile:p];
			if (img) return img;
		}
	}
	// recursive shallow search for *60x60* or Icon*
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:bundlePath];
	NSInteger depthGuard = 0;
	for (NSString *rel in en) {
		if (++depthGuard > 400) break;
		NSString *low = rel.lowercaseString;
		if (![low hasSuffix:@".png"]) continue;
		if ([low containsString:@"appicon"] || [low containsString:@"icon"]) {
			UIImage *img = [UIImage imageWithContentsOfFile:[bundlePath stringByAppendingPathComponent:rel]];
			if (img && img.size.width >= 40) return img;
		}
	}
	return nil;
}

- (SBAppInfo *)appInfoForBundleID:(NSString *)bundleID {
	for (SBAppInfo *a in [self listUserApps]) {
		if ([a.bundleID isEqualToString:bundleID]) return a;
	}
	// fallback via proxy
	Class proxyClass = [self proxyClass];
	if (!proxyClass) return nil;
	id proxy = [proxyClass applicationProxyForIdentifier:bundleID];
	if (!proxy) return nil;
	SBAppInfo *info = [SBAppInfo new];
	info.bundleID = bundleID;
	info.name = [proxy respondsToSelector:@selector(localizedName)] ? [proxy localizedName] : bundleID;
	if ([proxy respondsToSelector:@selector(dataContainerURL)]) info.dataPath = [[proxy dataContainerURL] path];
	if ([proxy respondsToSelector:@selector(bundleURL)]) info.bundlePath = [[proxy bundleURL] path];
	[self fillExtraInfo:info fromProxy:proxy];
	return info;
}

#pragma mark - Profiles

- (NSArray<SBProfileInfo *> *)profilesForBundleID:(NSString *)bundleID {
	NSMutableArray *list = [NSMutableArray array];
	NSString *dir = [self profilesDir:bundleID];
	NSArray *ids = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
	NSDictionary *meta = [self loadMeta:bundleID];
	NSString *active = meta[@"activeProfileID"] ?: @"";
	NSDictionary *pmeta = meta[@"profiles"] ?: @{};

	for (NSString *pid in ids ?: @[]) {
		NSString *pdir = [dir stringByAppendingPathComponent:pid];
		BOOL isDir = NO;
		if (![[NSFileManager defaultManager] fileExistsAtPath:pdir isDirectory:&isDir] || !isDir) continue;
		SBProfileInfo *p = [SBProfileInfo new];
		p.profileID = pid;
		p.bundleID = bundleID;
		NSDictionary *pm = pmeta[pid];
		p.name = pm[@"name"] ?: pid;
		NSNumber *c = pm[@"createdAt"];
		p.createdAt = c ? [NSDate dateWithTimeIntervalSince1970:c.doubleValue] : [NSDate date];
		NSNumber *u = pm[@"updatedAt"];
		p.updatedAt = u ? [NSDate dateWithTimeIntervalSince1970:u.doubleValue] : nil;
		p.sizeBytes = [self directorySize:[pdir stringByAppendingPathComponent:@"Data"]];
		p.isActive = [pid isEqualToString:active];
		BOOL reset = [pm[@"resetDeviceIDs"] boolValue];
		NSDictionary *dev = [NSDictionary dictionaryWithContentsOfFile:[pdir stringByAppendingPathComponent:@"device.plist"]];
		if ([dev isKindOfClass:NSDictionary.class] && dev.count) {
			reset = YES;
			NSString *du = dev[@"deviceUUID"] ?: dev[@"vendorUUID"] ?: @"";
			if (du.length >= 8) p.deviceUUIDShort = [[du substringToIndex:8] uppercaseString];
		} else if ([pm[@"deviceUUID"] isKindOfClass:NSString.class]) {
			NSString *du = pm[@"deviceUUID"];
			if (du.length >= 8) p.deviceUUIDShort = [[du substringToIndex:8] uppercaseString];
		}
		p.resetDeviceIDs = reset;
		[list addObject:p];
	}
	[list sortUsingComparator:^NSComparisonResult(SBProfileInfo *a, SBProfileInfo *b) {
		return [b.createdAt compare:a.createdAt];
	}];
	return list;
}

- (NSString *)activeProfileIDForBundleID:(NSString *)bundleID {
	return [self loadMeta:bundleID][@"activeProfileID"];
}

#pragma mark - Extra app info

- (void)fillExtraInfo:(SBAppInfo *)info fromProxy:(id)proxy {
	if ([proxy respondsToSelector:@selector(teamID)]) {
		id t = [proxy teamID];
		if ([t isKindOfClass:NSString.class]) info.teamID = t;
	}
	NSMutableDictionary *groups = [NSMutableDictionary dictionary];
	if ([proxy respondsToSelector:@selector(groupContainerURLs)]) {
		NSDictionary *g = [proxy groupContainerURLs];
		if ([g isKindOfClass:NSDictionary.class]) {
			[g enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
				NSString *gid = [key isKindOfClass:NSString.class] ? key : [key description];
				NSString *path = nil;
				if ([obj isKindOfClass:NSURL.class]) path = [(NSURL *)obj path];
				else if ([obj isKindOfClass:NSString.class]) path = obj;
				if (gid.length && path.length) groups[gid] = path;
			}];
		}
	}
	// fallback scan shared app groups via metadata if empty
	if (!groups.count) {
		NSString *sharedRoot = @"/var/mobile/Containers/Shared/AppGroup";
		NSArray *uuids = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sharedRoot error:nil];
		for (NSString *uuid in uuids ?: @[]) {
			NSString *meta = [[sharedRoot stringByAppendingPathComponent:uuid] stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
			NSDictionary *md = [NSDictionary dictionaryWithContentsOfFile:meta];
			NSString *ident = md[@"MCMMetadataIdentifier"];
			// also try key
			if (!ident) ident = md[@"mcmMetadataIdentifier"];
			if (![ident isKindOfClass:NSString.class]) continue;
			// App groups don't always embed bundle id; keep all and filter by team later when saving if needed
			// Prefer groups that contain bundle id
			if ([ident containsString:info.bundleID] || (info.teamID.length && [ident containsString:info.teamID])) {
				groups[ident] = [sharedRoot stringByAppendingPathComponent:uuid];
			}
		}
	}
	info.groupPaths = groups.count ? groups : nil;
	if (!info.teamID.length && info.bundlePath.length) {
		// try embedded.mobileprovision / TeamIdentifier from code signature entitlements via Info no-op
		NSString *prov = [info.bundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"];
		NSData *data = [NSData dataWithContentsOfFile:prov];
		if (data) {
			NSString *raw = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
			if (!raw) raw = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
			NSRange r = [raw rangeOfString:@"<key>com.apple.developer.team-identifier</key>"];
			if (r.location != NSNotFound) {
				NSString *sub = [raw substringFromIndex:r.location];
				NSRange s = [sub rangeOfString:@"<string>"];
				NSRange e = [sub rangeOfString:@"</string>"];
				if (s.location != NSNotFound && e.location > s.location) {
					NSString *team = [sub substringWithRange:NSMakeRange(s.location + 8, e.location - (s.location + 8))];
					if (team.length == 10) info.teamID = team;
				}
			}
		}
	}
}

#pragma mark - Copy helpers

- (BOOL)shouldSkipRelativePath:(NSString *)rel {
	if (!rel.length) return NO;
	NSString *base = rel.lastPathComponent;
	if ([base isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"]) return YES;
	if ([rel containsString:@".com.apple.mobile_container_manager.metadata.plist"]) return YES;
	if ([rel hasPrefix:@"Library/SplashBoard/"] || [rel isEqualToString:@"Library/SplashBoard"]) return YES;
	// never skip preferences / cookies / webkit storage — critical for sessions
	if ([rel hasPrefix:@"Library/Preferences"] || [rel hasPrefix:@"Library/Cookies"] ||
		[rel hasPrefix:@"Library/WebKit"] || [rel hasPrefix:@"Library/HTTPStorages"] ||
		[rel hasPrefix:@"Library/Application Support"]) {
		return NO;
	}
	BOOL skipHeavy = YES;
	@try { skipHeavy = SBSettingsBool(SBSettingSkipCaches); } @catch (__unused NSException *e) {}
	if (skipHeavy) {
		if ([rel hasPrefix:@"tmp/"] || [rel isEqualToString:@"tmp"]) return YES;
		if ([rel hasPrefix:@"Library/Caches/"] || [rel isEqualToString:@"Library/Caches"]) return YES;
		if ([rel hasPrefix:@"Library/Logs/"] || [rel isEqualToString:@"Library/Logs"]) return YES;
	}
	return NO;
}

- (NSArray<NSString *> *)collectFilesUnder:(NSString *)root relativePrefix:(NSString *)prefix {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSMutableArray *files = [NSMutableArray array];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:root isDirectory:&isDir]) return files;
	if (!isDir) {
		if (prefix.length) [files addObject:prefix];
		return files;
	}
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
	for (NSString *rel in en) {
		NSString *fullRel = prefix.length ? [prefix stringByAppendingPathComponent:rel] : rel;
		if ([self shouldSkipRelativePath:fullRel]) {
			// if skipping a directory, skip descendants
			NSString *full = [root stringByAppendingPathComponent:rel];
			BOOL d = NO;
			if ([fm fileExistsAtPath:full isDirectory:&d] && d) [en skipDescendants];
			continue;
		}
		NSString *full = [root stringByAppendingPathComponent:rel];
		BOOL d = NO;
		[fm fileExistsAtPath:full isDirectory:&d];
		if (!d) [files addObject:fullRel];
	}
	return files;
}

- (BOOL)copyTreeFrom:(NSString *)srcRoot
				  to:(NSString *)dstRoot
			progress:(SBProgressBlock)progress
			   label:(NSString *)label
			   error:(NSError **)error {
	NSFileManager *fm = NSFileManager.defaultManager;
	[fm createDirectoryAtPath:dstRoot withIntermediateDirectories:YES attributes:nil error:nil];

	// collect top-level entries of container
	NSArray *top = [fm contentsOfDirectoryAtPath:srcRoot error:nil] ?: @[];
	NSMutableArray<NSString *> *files = [NSMutableArray array];
	for (NSString *name in top) {
		if ([name isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"]) continue;
		NSString *src = [srcRoot stringByAppendingPathComponent:name];
		BOOL isDir = NO;
		[fm fileExistsAtPath:src isDirectory:&isDir];
		if (!isDir) {
			if (![self shouldSkipRelativePath:name]) [files addObject:name];
			continue;
		}
		if ([self shouldSkipRelativePath:name]) continue;
		[files addObjectsFromArray:[self collectFilesUnder:src relativePrefix:name]];
	}

	NSUInteger total = MAX(files.count, (NSUInteger)1);
	NSUInteger i = 0;
	for (NSString *rel in files) {
		NSString *from = [srcRoot stringByAppendingPathComponent:rel];
		NSString *to = [dstRoot stringByAppendingPathComponent:rel];
		NSString *parent = [to stringByDeletingLastPathComponent];
		NSError *err = nil;
		if (![fm fileExistsAtPath:parent]) {
			[fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&err];
		}
		if ([fm fileExistsAtPath:to]) [fm removeItemAtPath:to error:nil];
		// hardlink when possible for speed? copy for safety across volumes
		if (![fm copyItemAtPath:from toPath:to error:&err]) {
			// continue on vanish
		}
		i++;
		if (progress && (i % 25 == 0 || i == total)) {
			NSString *msg = [NSString stringWithFormat:@"%@ %lu/%lu", label ?: @"复制", (unsigned long)i, (unsigned long)total];
			progress(msg, (double)i / (double)total);
		}
	}
	return YES;
}

- (BOOL)wipeTreeKeepingMetadata:(NSString *)dataPath progress:(SBProgressBlock)progress {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSArray *top = [fm contentsOfDirectoryAtPath:dataPath error:nil] ?: @[];
	for (NSString *name in top) {
		if ([name isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"]) continue;
		if (progress) progress([NSString stringWithFormat:@"清理 %@", name], -1);
		NSString *p = [dataPath stringByAppendingPathComponent:name];
		// If skip caches setting, still wipe caches on restore target so old session doesn't remain
		[fm removeItemAtPath:p error:nil];
	}
	return YES;
}

- (BOOL)replaceLiveContainer:(NSString *)dataPath
			  withProfileData:(NSString *)profileData
					 progress:(SBProgressBlock)progress
						error:(NSError **)error {
	[self wipeTreeKeepingMetadata:dataPath progress:progress];
	return [self copyTreeFrom:profileData to:dataPath progress:progress label:@"恢复容器" error:error];
}

#pragma mark - App Groups

- (BOOL)snapshotGroups:(NSDictionary<NSString *,NSString *> *)groupPaths
				   into:(NSString *)groupsDst
			   progress:(SBProgressBlock)progress
				  error:(NSError **)error {
	NSFileManager *fm = NSFileManager.defaultManager;
	[fm createDirectoryAtPath:groupsDst withIntermediateDirectories:YES attributes:nil error:nil];
	if (!groupPaths.count) return YES;
	__block NSUInteger idx = 0;
	NSUInteger total = groupPaths.count;
	for (NSString *gid in groupPaths) {
		idx++;
		NSString *src = groupPaths[gid];
		if (![fm fileExistsAtPath:src]) continue;
		NSString *safe = [[gid componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]] componentsJoinedByString:@"_"];
		NSString *dst = [groupsDst stringByAppendingPathComponent:safe];
		[fm removeItemAtPath:dst error:nil];
		if (progress) progress([NSString stringWithFormat:@"备份 Group %lu/%lu", (unsigned long)idx, (unsigned long)total], (double)idx/total);
		if (![self copyTreeFrom:src to:dst progress:nil label:@"group" error:error]) {
			// continue
		}
		// write mapping
	}
	// save map
	[groupPaths writeToFile:[groupsDst stringByAppendingPathComponent:@"_map.plist"] atomically:YES];
	return YES;
}

- (BOOL)restoreGroupsFrom:(NSString *)groupsDst
			 liveGroupPaths:(NSDictionary<NSString *,NSString *> *)groupPaths
				  progress:(SBProgressBlock)progress
					 error:(NSError **)error {
	NSFileManager *fm = NSFileManager.defaultManager;
	if (!groupPaths.count) return YES;
	NSDictionary *map = [NSDictionary dictionaryWithContentsOfFile:[groupsDst stringByAppendingPathComponent:@"_map.plist"]];
	// restore each live group path: match by gid
	__block NSUInteger idx = 0;
	NSUInteger total = groupPaths.count;
	for (NSString *gid in groupPaths) {
		idx++;
		NSString *live = groupPaths[gid];
		if (!live.length) continue;
		NSString *safe = [[gid componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]] componentsJoinedByString:@"_"];
		NSString *src = [groupsDst stringByAppendingPathComponent:safe];
		if (![fm fileExistsAtPath:src]) {
			// try map reverse
			continue;
		}
		if (progress) progress([NSString stringWithFormat:@"恢复 Group %lu/%lu", (unsigned long)idx, (unsigned long)total], (double)idx/total);
		// wipe live group content except metadata
		[self wipeTreeKeepingMetadata:live progress:nil];
		[self copyTreeFrom:src to:live progress:nil label:@"group" error:error];
	}
	(void)map;
	return YES;
}

#pragma mark - Keychain (best-effort)

- (NSArray *)exportKeychainItemsForApp:(SBAppInfo *)app {
	NSMutableArray *out = [NSMutableArray array];
	NSArray *classes = @[
		(__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecClassInternetPassword,
	];
	NSString *team = app.teamID ?: @"";
	NSString *bid = app.bundleID ?: @"";

	for (id cls in classes) {
		NSDictionary *query = @{
			(__bridge id)kSecClass: cls,
			(__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
			(__bridge id)kSecReturnAttributes: @YES,
			(__bridge id)kSecReturnData: @YES,
		};
		CFTypeRef result = NULL;
		OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
		if (st != errSecSuccess || !result) continue;
		NSArray *items = (__bridge_transfer NSArray *)result;
		if (![items isKindOfClass:NSArray.class]) continue;
		for (NSDictionary *item in items) {
			if (![item isKindOfClass:NSDictionary.class]) continue;
			NSString *agrp = item[(__bridge id)kSecAttrAccessGroup] ?: item[@"agrp"] ?: @"";
			NSString *svce = item[(__bridge id)kSecAttrService] ?: item[@"svce"] ?: @"";
			NSString *acct = item[(__bridge id)kSecAttrAccount] ?: item[@"acct"] ?: @"";
			NSString *label = item[(__bridge id)kSecAttrLabel] ?: item[@"labl"] ?: @"";
			BOOL match = NO;
			if (team.length && [agrp containsString:team]) match = YES;
			if (bid.length && ([agrp containsString:bid] || [svce containsString:bid] || [acct containsString:bid] || [label containsString:bid])) match = YES;
			// WeChat-ish / common patterns when team known
			if (!match && team.length) {
				// many items use TEAMID.* 
				if ([agrp hasPrefix:team]) match = YES;
			}
			if (!match) continue;

			NSMutableDictionary *clean = [NSMutableDictionary dictionary];
			// keep serializable fields
			void (^put)(id, id) = ^(id key, id val) {
				if (!key || !val) return;
				if ([val isKindOfClass:NSString.class] || [val isKindOfClass:NSNumber.class] || [val isKindOfClass:NSData.class] || [val isKindOfClass:NSDate.class]) {
					clean[key] = val;
				}
			};
			put(@"class", [cls isEqual:(__bridge id)kSecClassInternetPassword] ? @"inet" : @"genp");
			put(@"agrp", agrp);
			put(@"svce", svce);
			put(@"acct", acct);
			put(@"labl", label);
			put(@"data", item[(__bridge id)kSecValueData]);
			put(@"pdmn", item[(__bridge id)kSecAttrAccessible] ?: item[@"pdmn"]);
			put(@"path", item[(__bridge id)kSecAttrPath]);
			put(@"srvr", item[(__bridge id)kSecAttrServer]);
			put(@"ptcl", item[(__bridge id)kSecAttrProtocol]);
			put(@"atyp", item[(__bridge id)kSecAttrAuthenticationType]);
			put(@"port", item[(__bridge id)kSecAttrPort]);
			[out addObject:clean];
		}
	}
	return out;
}

- (void)deleteKeychainItemsMatchingApp:(SBAppInfo *)app {
	NSArray *items = [self exportKeychainItemsForApp:app]; // uses same match rules
	for (NSDictionary *item in items) {
		NSString *clsName = item[@"class"] ?: @"genp";
		id cls = [clsName isEqualToString:@"inet"] ? (__bridge id)kSecClassInternetPassword : (__bridge id)kSecClassGenericPassword;
		NSMutableDictionary *q = [@{ (__bridge id)kSecClass: cls } mutableCopy];
		if (item[@"agrp"]) q[(__bridge id)kSecAttrAccessGroup] = item[@"agrp"];
		if (item[@"svce"]) q[(__bridge id)kSecAttrService] = item[@"svce"];
		if (item[@"acct"]) q[(__bridge id)kSecAttrAccount] = item[@"acct"];
		if (item[@"srvr"]) q[(__bridge id)kSecAttrServer] = item[@"srvr"];
		SecItemDelete((__bridge CFDictionaryRef)q);
	}
}

- (NSUInteger)importKeychainItems:(NSArray *)items {
	if (![items isKindOfClass:NSArray.class]) return 0;
	NSUInteger ok = 0;
	for (NSDictionary *item in items) {
		if (![item isKindOfClass:NSDictionary.class]) continue;
		NSString *clsName = item[@"class"] ?: @"genp";
		id cls = [clsName isEqualToString:@"inet"] ? (__bridge id)kSecClassInternetPassword : (__bridge id)kSecClassGenericPassword;
		NSMutableDictionary *add = [@{ (__bridge id)kSecClass: cls } mutableCopy];
		if (item[@"agrp"]) add[(__bridge id)kSecAttrAccessGroup] = item[@"agrp"];
		if (item[@"svce"]) add[(__bridge id)kSecAttrService] = item[@"svce"];
		if (item[@"acct"]) add[(__bridge id)kSecAttrAccount] = item[@"acct"];
		if (item[@"labl"]) add[(__bridge id)kSecAttrLabel] = item[@"labl"];
		if (item[@"data"]) add[(__bridge id)kSecValueData] = item[@"data"];
		if (item[@"pdmn"]) add[(__bridge id)kSecAttrAccessible] = item[@"pdmn"];
		if (item[@"srvr"]) add[(__bridge id)kSecAttrServer] = item[@"srvr"];
		if (item[@"path"]) add[(__bridge id)kSecAttrPath] = item[@"path"];
		if (item[@"ptcl"]) add[(__bridge id)kSecAttrProtocol] = item[@"ptcl"];
		if (item[@"atyp"]) add[(__bridge id)kSecAttrAuthenticationType] = item[@"atyp"];
		if (item[@"port"]) add[(__bridge id)kSecAttrPort] = item[@"port"];
		// delete existing then add
		NSMutableDictionary *del = [@{ (__bridge id)kSecClass: cls } mutableCopy];
		if (item[@"agrp"]) del[(__bridge id)kSecAttrAccessGroup] = item[@"agrp"];
		if (item[@"svce"]) del[(__bridge id)kSecAttrService] = item[@"svce"];
		if (item[@"acct"]) del[(__bridge id)kSecAttrAccount] = item[@"acct"];
		if (item[@"srvr"]) del[(__bridge id)kSecAttrServer] = item[@"srvr"];
		SecItemDelete((__bridge CFDictionaryRef)del);
		OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
		if (st == errSecSuccess) ok++;
	}
	return ok;
}

#pragma mark - Snapshot high-level

- (BOOL)saveSnapshotForApp:(SBAppInfo *)app
			   profileDir:(NSString *)pdir
				 progress:(SBProgressBlock)progress
					error:(NSError **)error {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *dataDst = [pdir stringByAppendingPathComponent:@"Data"];
	NSString *groupsDst = [pdir stringByAppendingPathComponent:@"Groups"];
	NSString *kcPath = [pdir stringByAppendingPathComponent:@"keychain.plist"];

	[fm removeItemAtPath:dataDst error:nil];
	[fm createDirectoryAtPath:dataDst withIntermediateDirectories:YES attributes:nil error:nil];

	if (progress) progress(@"备份主容器…", 0);
	if (![self copyTreeFrom:app.dataPath to:dataDst progress:progress label:@"备份容器" error:error]) {
		return NO;
	}

	if (progress) progress(@"备份 App Group…", 0.7);
	[self snapshotGroups:app.groupPaths into:groupsDst progress:progress error:error];

	if (progress) progress(@"备份 Keychain…", 0.9);
	NSArray *kc = [self exportKeychainItemsForApp:app] ?: @[];
	// NSData may not write via writeToFile dictionary - use NSKeyedArchiver
	@try {
		NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:kc requiringSecureCoding:NO error:nil];
		[archived writeToFile:kcPath atomically:YES];
	} @catch (__unused NSException *ex) {
		// fallback empty
		[@[] writeToFile:kcPath atomically:YES];
	}

	// stats
	NSDictionary *stats = @{
		@"dataBytes": @([self directorySize:dataDst]),
		@"groupCount": @(app.groupPaths.count),
		@"keychainCount": @(kc.count),
		@"savedAt": @(NSDate.date.timeIntervalSince1970),
	};
	[stats writeToFile:[pdir stringByAppendingPathComponent:@"stats.plist"] atomically:YES];
	return YES;
}

- (BOOL)restoreSnapshotForApp:(SBAppInfo *)app
				  profileDir:(NSString *)pdir
					progress:(SBProgressBlock)progress
					   error:(NSError **)error {
	NSString *dataSrc = [pdir stringByAppendingPathComponent:@"Data"];
	NSString *groupsSrc = [pdir stringByAppendingPathComponent:@"Groups"];
	NSString *kcPath = [pdir stringByAppendingPathComponent:@"keychain.plist"];

	if (progress) progress(@"恢复主容器…", 0);
	if (![self replaceLiveContainer:app.dataPath withProfileData:dataSrc progress:progress error:error]) {
		return NO;
	}

	if (progress) progress(@"恢复 App Group…", 0.7);
	[self restoreGroupsFrom:groupsSrc liveGroupPaths:app.groupPaths progress:progress error:error];

	if (progress) progress(@"恢复 Keychain…", 0.9);
	NSArray *kc = nil;
	NSData *archived = [NSData dataWithContentsOfFile:kcPath];
	if (archived.length) {
		@try {
			kc = [NSKeyedUnarchiver unarchiveObjectWithData:archived];
		} @catch (__unused NSException *ex) {
			kc = [NSArray arrayWithContentsOfFile:kcPath];
		}
	}
	if ([kc isKindOfClass:NSArray.class] && kc.count) {
		// replace matching keychain with snapshot
		[self deleteKeychainItemsMatchingApp:app];
		[self importKeychainItems:kc];
	}
	return YES;
}

- (unsigned long long)directorySize:(NSString *)path {
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:path isDirectory:&isDir]) return 0;
	if (!isDir) {
		NSDictionary *a = [fm attributesOfItemAtPath:path error:nil];
		return a.fileSize;
	}
	unsigned long long total = 0;
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
	for (NSString *rel in en) {
		NSDictionary *a = [en fileAttributes];
		if ([a.fileType isEqualToString:NSFileTypeRegular]) {
			total += a.fileSize;
		}
	}
	return total;
}

- (NSString *)humanSize:(unsigned long long)bytes {
	double b = (double)bytes;
	if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
	if (b < 1024*1024) return [NSString stringWithFormat:@"%.1f KB", b/1024.0];
	if (b < 1024*1024*1024) return [NSString stringWithFormat:@"%.1f MB", b/(1024.0*1024.0)];
	return [NSString stringWithFormat:@"%.2f GB", b/(1024.0*1024.0*1024.0)];
}

#pragma mark - Device Identity

- (NSString *)randomSerial:(NSUInteger)len {
	static NSString *chars = @"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
	NSMutableString *s = [NSMutableString stringWithCapacity:len];
	for (NSUInteger i = 0; i < len; i++) {
		u_int32_t idx = arc4random_uniform((u_int32_t)chars.length);
		[s appendFormat:@"%C", [chars characterAtIndex:idx]];
	}
	return s;
}

- (NSDictionary *)generateDeviceIdentity {
	return @{
		@"vendorUUID": [[NSUUID UUID] UUIDString].uppercaseString,
		@"advertisingUUID": [[NSUUID UUID] UUIDString].uppercaseString,
		@"deviceUUID": [[NSUUID UUID] UUIDString].uppercaseString,
		@"installUUID": [[NSUUID UUID] UUIDString].uppercaseString,
		@"openUDID": [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""].lowercaseString,
		@"serial": [self randomSerial:12],
		@"createdAt": @(NSDate.date.timeIntervalSince1970),
		@"note": @"local seeds only; system IDFV/IDFA need injection to spoof",
	};
}

- (BOOL)isDeviceIdentityKey:(NSString *)key {
	if (!key.length) return NO;
	NSString *k = key.lowercaseString;
	static NSArray *needles;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		needles = @[
			@"idfa", @"idfv", @"advertising", @"vendorid", @"vendor_id",
			@"deviceid", @"device_id", @"deviceuuid", @"device_uuid",
			@"udid", @"uuid", @"openudid", @"open_udid",
			@"serial", @"imei", @"meid", @"android_id",
			@"installid", @"install_id", @"installationid", @"installation_id",
			@"appsflyer", @"adjust", @"firebase_installation", @"gidfa",
			@"uniqueid", @"unique_id", @"machineid", @"machine_id",
			@"fingerprint", @"device_token", @"devicetoken",
		];
	});
	for (NSString *n in needles) {
		if ([k containsString:n]) return YES;
	}
	return NO;
}

- (id)replaceIdentityValue:(id)value withIdentity:(NSDictionary *)identity keyHint:(NSString *)key {
	NSString *k = key.lowercaseString ?: @"";
	if ([k containsString:@"idfa"] || [k containsString:@"advertising"]) return identity[@"advertisingUUID"];
	if ([k containsString:@"idfv"] || [k containsString:@"vendor"]) return identity[@"vendorUUID"];
	if ([k containsString:@"openudid"] || [k containsString:@"open_udid"]) return identity[@"openUDID"];
	if ([k containsString:@"serial"]) return identity[@"serial"];
	if ([k containsString:@"install"]) return identity[@"installUUID"];
	if ([value isKindOfClass:NSString.class]) {
		NSString *s = (NSString *)value;
		// keep similar shape: UUID with dashes vs hex
		if (s.length == 36 && [s containsString:@"-"]) return identity[@"deviceUUID"];
		if (s.length >= 32) return identity[@"openUDID"];
		if (s.length >= 8 && s.length <= 16) return identity[@"serial"];
		return identity[@"deviceUUID"];
	}
	if ([value isKindOfClass:NSNumber.class]) {
		// don't invent numbers for numeric flags
		return value;
	}
	return identity[@"deviceUUID"];
}

- (id)scrubObject:(id)obj withIdentity:(NSDictionary *)identity {
	if ([obj isKindOfClass:NSDictionary.class]) {
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:((NSDictionary *)obj).count];
		[(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
			NSString *ks = [key isKindOfClass:NSString.class] ? key : [key description];
			if ([self isDeviceIdentityKey:ks]) {
				out[ks] = [self replaceIdentityValue:val withIdentity:identity keyHint:ks];
			} else {
				out[ks] = [self scrubObject:val withIdentity:identity];
			}
		}];
		return out;
	}
	if ([obj isKindOfClass:NSArray.class]) {
		NSMutableArray *arr = [NSMutableArray arrayWithCapacity:((NSArray *)obj).count];
		for (id item in (NSArray *)obj) {
			[arr addObject:[self scrubObject:item withIdentity:identity] ?: [NSNull null]];
		}
		return arr;
	}
	return obj;
}

- (void)ensureEmptyContainerSkeleton:(NSString *)dataPath {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSArray *dirs = @[
		@"Documents",
		@"Library",
		@"Library/Preferences",
		@"Library/Caches",
		@"tmp",
	];
	for (NSString *rel in dirs) {
		[fm createDirectoryAtPath:[dataPath stringByAppendingPathComponent:rel]
	  withIntermediateDirectories:YES attributes:nil error:nil];
	}
}

- (void)seedDeviceIdentity:(NSDictionary *)identity
		   intoContainerPath:(NSString *)dataPath
					bundleID:(NSString *)bundleID {
	if (!identity.count || !dataPath.length) return;
	NSFileManager *fm = NSFileManager.defaultManager;
	[self ensureEmptyContainerSkeleton:dataPath];
	NSString *prefs = [dataPath stringByAppendingPathComponent:@"Library/Preferences"];

	// dedicated identity file
	[identity writeToFile:[prefs stringByAppendingPathComponent:@"com.o2ol.switchbox.device.plist"] atomically:YES];

	// seed app defaults with common keys apps often read on first launch
	NSString *appPrefsPath = [prefs stringByAppendingPathComponent:[bundleID stringByAppendingString:@".plist"]];
	NSMutableDictionary *appPrefs = [[NSDictionary dictionaryWithContentsOfFile:appPrefsPath] mutableCopy] ?: [NSMutableDictionary dictionary];
	NSDictionary *seeds = @{
		@"IDFA": identity[@"advertisingUUID"],
		@"idfa": identity[@"advertisingUUID"],
		@"advertisingIdentifier": identity[@"advertisingUUID"],
		@"IDFV": identity[@"vendorUUID"],
		@"idfv": identity[@"vendorUUID"],
		@"identifierForVendor": identity[@"vendorUUID"],
		@"vendorIdentifier": identity[@"vendorUUID"],
		@"deviceId": identity[@"deviceUUID"],
		@"deviceID": identity[@"deviceUUID"],
		@"device_id": identity[@"deviceUUID"],
		@"deviceUUID": identity[@"deviceUUID"],
		@"UUID": identity[@"deviceUUID"],
		@"uuid": identity[@"deviceUUID"],
		@"UDID": identity[@"openUDID"],
		@"udid": identity[@"openUDID"],
		@"openudid": identity[@"openUDID"],
		@"OpenUDID": identity[@"openUDID"],
		@"installId": identity[@"installUUID"],
		@"installationId": identity[@"installUUID"],
		@"serialNumber": identity[@"serial"],
		@"serial": identity[@"serial"],
		@"SB_DeviceUUID": identity[@"deviceUUID"],
		@"SB_VendorUUID": identity[@"vendorUUID"],
		@"SB_AdvertisingUUID": identity[@"advertisingUUID"],
	};
	[appPrefs addEntriesFromDictionary:seeds];
	[appPrefs writeToFile:appPrefsPath atomically:YES];
}

- (void)scrubDeviceIdentifiersUnder:(NSString *)root withIdentity:(NSDictionary *)identity {
	if (!root.length || !identity.count) return;
	NSFileManager *fm = NSFileManager.defaultManager;
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
	NSInteger guard = 0;
	for (NSString *rel in en) {
		if (++guard > 8000) break;
		NSString *low = rel.lowercaseString;
		if (![low hasSuffix:@".plist"] && ![low hasSuffix:@".json"]) continue;
		// skip huge caches
		if ([low containsString:@"/caches/"] || [low containsString:@"/tmp/"]) continue;
		NSString *full = [root stringByAppendingPathComponent:rel];
		if ([low hasSuffix:@".plist"]) {
			NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:full];
			if (![d isKindOfClass:NSDictionary.class]) continue;
			NSDictionary *scrubbed = [self scrubObject:d withIdentity:identity];
			if (scrubbed) [scrubbed writeToFile:full atomically:YES];
		} else if ([low hasSuffix:@".json"]) {
			NSData *data = [NSData dataWithContentsOfFile:full];
			if (!data.length) continue;
			id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
			if (!json) continue;
			id scrubbed = [self scrubObject:json withIdentity:identity];
			NSData *out = [NSJSONSerialization dataWithJSONObject:scrubbed options:NSJSONWritingPrettyPrinted error:nil];
			if (out) [out writeToFile:full atomically:YES];
		}
	}
}

- (void)wipeSessionArtifactsInContainer:(NSString *)dataPath {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSArray *rels = @[
		@"Library/Cookies",
		@"Library/HTTPStorages",
		@"Library/WebKit",
		@"Library/Caches",
		@"Library/SplashBoard",
		@"tmp",
	];
	for (NSString *rel in rels) {
		NSString *p = [dataPath stringByAppendingPathComponent:rel];
		[fm removeItemAtPath:p error:nil];
		if ([rel isEqualToString:@"Library/Caches"] || [rel isEqualToString:@"tmp"]) {
			[fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
		}
	}
}

- (BOOL)buildEmptyGroupsForApp:(SBAppInfo *)app into:(NSString *)groupsDst error:(NSError **)error {
	NSFileManager *fm = NSFileManager.defaultManager;
	[fm removeItemAtPath:groupsDst error:nil];
	[fm createDirectoryAtPath:groupsDst withIntermediateDirectories:YES attributes:nil error:nil];
	if (!app.groupPaths.count) {
		[@{} writeToFile:[groupsDst stringByAppendingPathComponent:@"_map.plist"] atomically:YES];
		return YES;
	}
	NSMutableDictionary *map = [NSMutableDictionary dictionary];
	for (NSString *gid in app.groupPaths) {
		NSString *safe = [[gid componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]] componentsJoinedByString:@"_"];
		NSString *dst = [groupsDst stringByAppendingPathComponent:safe];
		[fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
		map[gid] = safe;
	}
	[map writeToFile:[groupsDst stringByAppendingPathComponent:@"_map.plist"] atomically:YES];
	return YES;
}

- (nullable NSDictionary *)deviceIdentityForProfile:(NSString *)profileID bundleID:(NSString *)bundleID {
	if (!profileID.length || !bundleID.length) return nil;
	NSString *p = [[self profileDir:bundleID profileID:profileID] stringByAppendingPathComponent:@"device.plist"];
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
	return [d isKindOfClass:NSDictionary.class] ? d : nil;
}

- (NSString *)normalizeUUIDString:(NSString *)raw {
	if (!raw.length) return @"";
	NSString *s = [[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
				   stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"{}"]];
	s = [s stringByReplacingOccurrencesOfString:@" " withString:@""];
	// accept 32 hex without dashes
	NSString *hex = [[s stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
	NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet];
	if (hex.length == 32 && [hex rangeOfCharacterFromSet:nonHex].location == NSNotFound) {
		return [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
				[hex substringWithRange:NSMakeRange(0, 8)],
				[hex substringWithRange:NSMakeRange(8, 4)],
				[hex substringWithRange:NSMakeRange(12, 4)],
				[hex substringWithRange:NSMakeRange(16, 4)],
				[hex substringWithRange:NSMakeRange(20, 12)]];
	}
	// keep as-is uppercase if already dashed-ish
	return s.uppercaseString;
}

- (NSString *)normalizeOpenUDID:(NSString *)raw {
	if (!raw.length) return @"";
	NSString *hex = [[[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
					  stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
	NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
	if ([hex rangeOfCharacterFromSet:nonHex].location != NSNotFound) {
		// allow mixed content, strip invalid
		NSMutableString *out = [NSMutableString string];
		for (NSUInteger i = 0; i < hex.length; i++) {
			unichar c = [hex characterAtIndex:i];
			if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) [out appendFormat:@"%C", c];
		}
		hex = out;
	}
	if (hex.length > 40) hex = [hex substringToIndex:40];
	if (hex.length < 16) {
		// pad with random to avoid empty
		while (hex.length < 32) {
			hex = [hex stringByAppendingString:[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""].lowercaseString];
		}
		hex = [hex substringToIndex:32];
	}
	return hex;
}

- (NSString *)normalizeSerial:(NSString *)raw {
	if (!raw.length) return [self randomSerial:12];
	NSString *s = [[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) [out appendFormat:@"%C", c];
	}
	if (out.length < 8) {
		[out appendString:[self randomSerial:12 - MIN(out.length, 12)]];
	}
	if (out.length > 20) return [out substringToIndex:20];
	return out;
}

- (NSDictionary *)normalizedDeviceIdentity:(NSDictionary *)identity {
	NSDictionary *base = identity.count ? identity : [self generateDeviceIdentity];
	NSMutableDictionary *out = [base mutableCopy] ?: [NSMutableDictionary dictionary];
	NSDictionary *gen = [self generateDeviceIdentity];
	NSString *device = [self normalizeUUIDString:out[@"deviceUUID"] ?: gen[@"deviceUUID"]];
	NSString *vendor = [self normalizeUUIDString:out[@"vendorUUID"] ?: gen[@"vendorUUID"]];
	NSString *ad = [self normalizeUUIDString:out[@"advertisingUUID"] ?: gen[@"advertisingUUID"]];
	NSString *install = [self normalizeUUIDString:out[@"installUUID"] ?: gen[@"installUUID"]];
	NSString *open = [self normalizeOpenUDID:out[@"openUDID"] ?: gen[@"openUDID"]];
	NSString *serial = [self normalizeSerial:out[@"serial"] ?: gen[@"serial"]];
	if (!device.length) device = gen[@"deviceUUID"];
	if (!vendor.length) vendor = gen[@"vendorUUID"];
	if (!ad.length) ad = gen[@"advertisingUUID"];
	if (!install.length) install = gen[@"installUUID"];
	out[@"deviceUUID"] = device;
	out[@"vendorUUID"] = vendor;
	out[@"advertisingUUID"] = ad;
	out[@"installUUID"] = install;
	out[@"openUDID"] = open;
	out[@"serial"] = serial;
	out[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
	if (!out[@"createdAt"]) out[@"createdAt"] = out[@"updatedAt"];
	out[@"note"] = @"local seeds only; system IDFV/IDFA need injection to spoof";
	out[@"editable"] = @YES;
	return out;
}

- (void)updateDeviceIdentity:(NSDictionary *)identity
				  forProfile:(NSString *)profileID
					bundleID:(NSString *)bundleID
				 applyToLive:(BOOL)applyToLive
				scrubExisting:(BOOL)scrubExisting
					progress:(SBProgressBlock)progress
				  completion:(SBDoneBlock)completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		if (!profileID.length || !bundleID.length) {
			dispatch_async(dispatch_get_main_queue(), ^{ completion([self err:@"参数无效"]); });
			return;
		}
		SBAppInfo *app = [self appInfoForBundleID:bundleID];
		if (!app) {
			dispatch_async(dispatch_get_main_queue(), ^{ completion([self err:@"找不到目标 App"]); });
			return;
		}
		NSString *pdir = [self profileDir:bundleID profileID:profileID];
		if (![[NSFileManager defaultManager] fileExistsAtPath:pdir]) {
			dispatch_async(dispatch_get_main_queue(), ^{ completion([self err:@"配置不存在"]); });
			return;
		}
		NSDictionary *norm = [self normalizedDeviceIdentity:identity];
		SBProgressBlock wrap = ^(NSString *msg, double p) {
			if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(msg, p); });
		};

		wrap(@"写入配置识别码…", 0.1);
		[norm writeToFile:[pdir stringByAppendingPathComponent:@"device.plist"] atomically:YES];

		NSString *dataPath = [pdir stringByAppendingPathComponent:@"Data"];
		[[NSFileManager defaultManager] createDirectoryAtPath:dataPath withIntermediateDirectories:YES attributes:nil error:nil];
		wrap(@"写入配置沙盒…", 0.35);
		[self seedDeviceIdentity:norm intoContainerPath:dataPath bundleID:bundleID];
		if (scrubExisting) {
			wrap(@"清洗配置内已有字段…", 0.5);
			[self scrubDeviceIdentifiersUnder:dataPath withIdentity:norm];
		}

		// meta
		NSMutableDictionary *meta = [self loadMeta:bundleID];
		NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
		NSMutableDictionary *pm = [profiles[profileID] mutableCopy] ?: [NSMutableDictionary dictionary];
		pm[@"resetDeviceIDs"] = @YES;
		pm[@"deviceUUID"] = norm[@"deviceUUID"] ?: @"";
		pm[@"vendorUUID"] = norm[@"vendorUUID"] ?: @"";
		pm[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
		profiles[profileID] = pm;
		meta[@"profiles"] = profiles;
		[self saveMeta:meta bundleID:bundleID];

		BOOL isActive = [meta[@"activeProfileID"] isEqualToString:profileID];
		BOOL doLive = applyToLive || isActive;
		if (doLive && app.dataPath.length) {
			wrap(@"关闭目标 App…", 0.6);
			[self ensureTerminated:bundleID];
			wrap(@"应用到当前容器…", 0.75);
			[self seedDeviceIdentity:norm intoContainerPath:app.dataPath bundleID:bundleID];
			if (scrubExisting) {
				[self scrubDeviceIdentifiersUnder:app.dataPath withIdentity:norm];
			}
			// if this profile is active, refresh snapshot so next switch is consistent
			if (isActive) {
				wrap(@"同步活动配置快照…", 0.9);
				NSError *err = nil;
				[self saveSnapshotForApp:app profileDir:pdir progress:wrap error:&err];
				// restore device.plist root after snapshot
				[norm writeToFile:[pdir stringByAppendingPathComponent:@"device.plist"] atomically:YES];
				[self seedDeviceIdentity:norm intoContainerPath:[pdir stringByAppendingPathComponent:@"Data"] bundleID:bundleID];
			}
		}

		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
	});
}

#pragma mark - Operations

- (void)ensureTerminated:(NSString *)bundleID {
	[self terminateApp:bundleID error:nil];
	[NSThread sleepForTimeInterval:0.5];
	[self terminateApp:bundleID error:nil];
	[NSThread sleepForTimeInterval:0.8];
}

- (void)createProfileFromCurrentForBundleID:(NSString *)bundleID
									   name:(NSString *)name
								  progress:(SBProgressBlock)progress
								completion:(SBDoneBlock)completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		SBAppInfo *app = [self appInfoForBundleID:bundleID];
		if (!app.dataPath.length || ![[NSFileManager defaultManager] fileExistsAtPath:app.dataPath]) {
			dispatch_async(dispatch_get_main_queue(), ^{ completion([self err:@"找不到 App 数据容器，请确认本 App 以 TrollStore 安装且有 no-sandbox 权限"]); });
			return;
		}

		if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(@"正在关闭 App…", -1); });
		[self ensureTerminated:bundleID];

		NSString *pid = [[NSUUID UUID] UUIDString];
		NSString *pdir = [self profileDir:bundleID profileID:pid];
		[[NSFileManager defaultManager] createDirectoryAtPath:pdir withIntermediateDirectories:YES attributes:nil error:nil];

		SBProgressBlock wrap = ^(NSString *msg, double p) {
			if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(msg, p); });
		};

		if (![self saveSnapshotForApp:app profileDir:pdir progress:wrap error:&err]) {
			[[NSFileManager defaultManager] removeItemAtPath:pdir error:nil];
			dispatch_async(dispatch_get_main_queue(), ^{ completion(err ?: [self err:@"备份失败"]); });
			return;
		}

		NSMutableDictionary *meta = [self loadMeta:bundleID];
		NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
		NSTimeInterval now = NSDate.date.timeIntervalSince1970;
		NSDictionary *stats = [NSDictionary dictionaryWithContentsOfFile:[pdir stringByAppendingPathComponent:@"stats.plist"]] ?: @{};
		profiles[pid] = @{
			@"name": name.length ? name : @"未命名",
			@"createdAt": @(now),
			@"updatedAt": @(now),
			@"keychainCount": stats[@"keychainCount"] ?: @0,
			@"groupCount": stats[@"groupCount"] ?: @0,
		};
		meta[@"profiles"] = profiles;
		// CRITICAL FIX: 当前现场就是这套配置，必须把 active 指到它。
		// 否则之后登录另一个号再切换时，会把新号写回旧配置，导致“怎么切都是同一个号”。
		meta[@"activeProfileID"] = pid;
		[self saveMeta:meta bundleID:bundleID];

		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
	});
}

- (void)createFreshProfileForBundleID:(NSString *)bundleID
								 name:(NSString *)name
					  resetDeviceIDs:(BOOL)resetDeviceIDs
							progress:(SBProgressBlock)progress
						  completion:(SBDoneBlock)completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		SBAppInfo *app = [self appInfoForBundleID:bundleID];
		if (!app.dataPath.length || ![[NSFileManager defaultManager] fileExistsAtPath:app.dataPath]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion([self err:@"找不到 App 数据容器，请确认本 App 以 TrollStore 安装且有 no-sandbox 权限"]);
			});
			return;
		}

		SBProgressBlock wrap = ^(NSString *msg, double p) {
			if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(msg, p); });
		};

		if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(@"正在关闭 App…", -1); });
		[self ensureTerminated:bundleID];

		// 先把当前现场写回已绑定配置，避免空配置覆盖导致丢号
		NSMutableDictionary *meta = [self loadMeta:bundleID];
		NSString *currentActive = meta[@"activeProfileID"] ?: @"";
		if (currentActive.length) {
			wrap(@"保存当前配置…", 0.05);
			NSString *curDir = [self profileDir:bundleID profileID:currentActive];
			if (![self saveSnapshotForApp:app profileDir:curDir progress:wrap error:&err]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					completion(err ?: [self err:@"保存当前配置失败，已中止新建空配置"]);
				});
				return;
			}
			NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
			NSMutableDictionary *pm = [profiles[currentActive] mutableCopy] ?: [NSMutableDictionary dictionary];
			pm[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
			profiles[currentActive] = pm;
			meta[@"profiles"] = profiles;
			[self saveMeta:meta bundleID:bundleID];
		}

		NSString *pid = [[NSUUID UUID] UUIDString];
		NSString *pdir = [self profileDir:bundleID profileID:pid];
		NSFileManager *fm = NSFileManager.defaultManager;
		[fm createDirectoryAtPath:pdir withIntermediateDirectories:YES attributes:nil error:nil];

		NSString *dataDst = [pdir stringByAppendingPathComponent:@"Data"];
		NSString *groupsDst = [pdir stringByAppendingPathComponent:@"Groups"];
		NSString *kcPath = [pdir stringByAppendingPathComponent:@"keychain.plist"];
		[fm removeItemAtPath:dataDst error:nil];
		[fm createDirectoryAtPath:dataDst withIntermediateDirectories:YES attributes:nil error:nil];
		[self ensureEmptyContainerSkeleton:dataDst];

		NSDictionary *identity = nil;
		if (resetDeviceIDs) {
			wrap(@"生成设备识别码…", 0.2);
			identity = [self generateDeviceIdentity];
			[identity writeToFile:[pdir stringByAppendingPathComponent:@"device.plist"] atomically:YES];
			[self seedDeviceIdentity:identity intoContainerPath:dataDst bundleID:bundleID];
		}

		wrap(@"准备 App Group…", 0.35);
		if (![self buildEmptyGroupsForApp:app into:groupsDst error:&err]) {
			[fm removeItemAtPath:pdir error:nil];
			dispatch_async(dispatch_get_main_queue(), ^{ completion(err ?: [self err:@"准备 App Group 失败"]); });
			return;
		}

		// 空 Keychain 快照
		@try {
			NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:@[] requiringSecureCoding:NO error:nil];
			[archived writeToFile:kcPath atomically:YES];
		} @catch (__unused NSException *ex) {
			[@[] writeToFile:kcPath atomically:YES];
		}

		// 清理现场会话残留 + 写入空配置
		wrap(@"清空目标容器…", 0.5);
		[self wipeTreeKeepingMetadata:app.dataPath progress:wrap];
		[self ensureEmptyContainerSkeleton:app.dataPath];
		if (resetDeviceIDs && identity) {
			[self seedDeviceIdentity:identity intoContainerPath:app.dataPath bundleID:bundleID];
			// wipe groups live content
			for (NSString *gid in app.groupPaths) {
				NSString *live = app.groupPaths[gid];
				if (live.length) [self wipeTreeKeepingMetadata:live progress:nil];
			}
			[self wipeSessionArtifactsInContainer:app.dataPath];
		} else {
			for (NSString *gid in app.groupPaths) {
				NSString *live = app.groupPaths[gid];
				if (live.length) [self wipeTreeKeepingMetadata:live progress:nil];
			}
			[self wipeSessionArtifactsInContainer:app.dataPath];
		}

		wrap(@"清理 Keychain…", 0.75);
		[self deleteKeychainItemsMatchingApp:app];

		// 从 live 再快照一次，保证 profile 与 live 一致
		wrap(@"写入配置快照…", 0.85);
		if (![self saveSnapshotForApp:app profileDir:pdir progress:wrap error:&err]) {
			// still keep partial profile? remove for safety
			[fm removeItemAtPath:pdir error:nil];
			dispatch_async(dispatch_get_main_queue(), ^{ completion(err ?: [self err:@"写入空配置失败"]); });
			return;
		}
		// re-write device.plist after snapshot (snapshot doesn't include it at pdir root)
		if (identity) {
			[identity writeToFile:[pdir stringByAppendingPathComponent:@"device.plist"] atomically:YES];
			// also re-seed into snapshot Data in case save overwrote
			[self seedDeviceIdentity:identity intoContainerPath:[pdir stringByAppendingPathComponent:@"Data"] bundleID:bundleID];
		}

		meta = [self loadMeta:bundleID];
		NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
		NSTimeInterval now = NSDate.date.timeIntervalSince1970;
		NSMutableDictionary *pm = [@{
			@"name": name.length ? name : @"未命名",
			@"createdAt": @(now),
			@"updatedAt": @(now),
			@"keychainCount": @0,
			@"groupCount": @(app.groupPaths.count),
			@"resetDeviceIDs": @(resetDeviceIDs),
			@"fresh": @YES,
		} mutableCopy];
		if (identity[@"deviceUUID"]) pm[@"deviceUUID"] = identity[@"deviceUUID"];
		if (identity[@"vendorUUID"]) pm[@"vendorUUID"] = identity[@"vendorUUID"];
		profiles[pid] = pm;
		meta[@"profiles"] = profiles;
		meta[@"activeProfileID"] = pid;
		[self saveMeta:meta bundleID:bundleID];

		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
	});
}

- (void)switchToProfile:(NSString *)profileID
			  bundleID:(NSString *)bundleID
	 saveCurrentAsName:(NSString *)autoSaveName
			  progress:(SBProgressBlock)progress
			completion:(SBDoneBlock)completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		SBAppInfo *app = [self appInfoForBundleID:bundleID];
		if (!app.dataPath.length) {
			dispatch_async(dispatch_get_main_queue(), ^{ completion([self err:@"找不到数据容器"]); });
			return;
		}
		NSString *pdir = [self profileDir:bundleID profileID:profileID];
		NSString *pdata = [pdir stringByAppendingPathComponent:@"Data"];
		if (![[NSFileManager defaultManager] fileExistsAtPath:pdata]) {
			dispatch_async(dispatch_get_main_queue(), ^{ completion([self err:@"配置数据不存在，请重新创建配置"]); });
			return;
		}

		NSMutableDictionary *meta = [self loadMeta:bundleID];
		NSString *currentActive = meta[@"activeProfileID"] ?: @"";
		if ([currentActive isEqualToString:profileID]) {
			// still allow force restore
		}

		if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(@"正在关闭 App…", -1); });
		[self ensureTerminated:bundleID];

		SBProgressBlock wrap = ^(NSString *msg, double p) {
			if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(msg, p); });
		};

		// Save current live -> active profile (or auto-create)
		if (currentActive.length && ![currentActive isEqualToString:profileID]) {
			NSString *curDir = [self profileDir:bundleID profileID:currentActive];
			if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(@"保存当前配置…", 0); });
			if (![self saveSnapshotForApp:app profileDir:curDir progress:wrap error:&err]) {
				dispatch_async(dispatch_get_main_queue(), ^{ completion(err ?: [self err:@"保存当前配置失败"]); });
				return;
			}
			NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
			NSMutableDictionary *pm = [profiles[currentActive] mutableCopy] ?: [NSMutableDictionary dictionary];
			pm[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
			profiles[currentActive] = pm;
			meta[@"profiles"] = profiles;
			[self saveMeta:meta bundleID:bundleID];
		} else if (!currentActive.length && autoSaveName.length) {
			dispatch_semaphore_t sem = dispatch_semaphore_create(0);
			__block NSError *cErr = nil;
			[self createProfileFromCurrentForBundleID:bundleID name:autoSaveName progress:progress completion:^(NSError *e) {
				cErr = e;
				dispatch_semaphore_signal(sem);
			}];
			dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
			if (cErr) {
				dispatch_async(dispatch_get_main_queue(), ^{ completion(cErr); });
				return;
			}
			[self ensureTerminated:bundleID];
			meta = [self loadMeta:bundleID];
		}

		if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(@"写入目标配置…", 0); });
		if (![self restoreSnapshotForApp:app profileDir:pdir progress:wrap error:&err]) {
			dispatch_async(dispatch_get_main_queue(), ^{ completion(err ?: [self err:@"切换失败"]); });
			return;
		}

		meta = [self loadMeta:bundleID];
		meta[@"activeProfileID"] = profileID;
		NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
		NSMutableDictionary *pm = [profiles[profileID] mutableCopy] ?: [NSMutableDictionary dictionary];
		pm[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
		profiles[profileID] = pm;
		meta[@"profiles"] = profiles;
		[self saveMeta:meta bundleID:bundleID];

		// brief settle
		[NSThread sleepForTimeInterval:0.3];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
	});
}

- (void)deleteProfile:(NSString *)profileID bundleID:(NSString *)bundleID error:(NSError **)error {
	NSString *pdir = [self profileDir:bundleID profileID:profileID];
	NSError *err = nil;
	if ([[NSFileManager defaultManager] fileExistsAtPath:pdir]) {
		if (![[NSFileManager defaultManager] removeItemAtPath:pdir error:&err]) {
			if (error) *error = err;
			return;
		}
	}
	NSMutableDictionary *meta = [self loadMeta:bundleID];
	NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
	[profiles removeObjectForKey:profileID];
	meta[@"profiles"] = profiles;
	if ([meta[@"activeProfileID"] isEqualToString:profileID]) {
		meta[@"activeProfileID"] = @"";
	}
	[self saveMeta:meta bundleID:bundleID];
}

- (void)renameProfile:(NSString *)profileID bundleID:(NSString *)bundleID toName:(NSString *)name error:(NSError **)error {
	if (!name.length) {
		if (error) *error = [self err:@"名称不能为空"];
		return;
	}
	NSMutableDictionary *meta = [self loadMeta:bundleID];
	NSMutableDictionary *profiles = [meta[@"profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
	NSMutableDictionary *pm = [profiles[profileID] mutableCopy];
	if (!pm) {
		if (error) *error = [self err:@"配置不存在"];
		return;
	}
	pm[@"name"] = name;
	profiles[profileID] = pm;
	meta[@"profiles"] = profiles;
	[self saveMeta:meta bundleID:bundleID];
}

#pragma mark - Process control

- (void)killProcessesMatchingExecutable:(NSString *)execName bundlePath:(NSString *)bundlePath {
	int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
	size_t size = 0;
	if (sysctl(mib, 3, NULL, &size, NULL, 0) < 0 || size == 0) return;
	struct kinfo_proc *procs = calloc(1, size);
	if (!procs) return;
	if (sysctl(mib, 3, procs, &size, NULL, 0) < 0) {
		free(procs);
		return;
	}
	int n = (int)(size / sizeof(struct kinfo_proc));
	for (int i = 0; i < n; i++) {
		pid_t pid = procs[i].kp_proc.p_pid;
		if (pid <= 1) continue;
		char pathbuf[MAXPATHLEN] = {0};
		int pmib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
		size_t psize = sizeof(pathbuf);
		// KERN_PROCARGS2 may fail; try proc_pidpath via dlsym
		typedef int (*proc_pidpath_t)(int, void *, uint32_t);
		static proc_pidpath_t proc_pidpath_fn = NULL;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			proc_pidpath_fn = (proc_pidpath_t)dlsym(RTLD_DEFAULT, "proc_pidpath");
		});
		BOOL match = NO;
		if (proc_pidpath_fn && proc_pidpath_fn(pid, pathbuf, sizeof(pathbuf)) > 0) {
			NSString *pp = [NSString stringWithUTF8String:pathbuf];
			if (bundlePath.length && [pp hasPrefix:bundlePath]) match = YES;
			if (!match && execName.length) {
				if ([pp.lastPathComponent isEqualToString:execName]) match = YES;
			}
		} else {
			// fallback: process name
			NSString *pname = [NSString stringWithCString:procs[i].kp_proc.p_comm encoding:NSUTF8StringEncoding];
			if (execName.length && [pname isEqualToString:execName]) match = YES;
		}
		if (match) {
			kill(pid, SIGKILL);
		}
	}
	free(procs);
}


- (BOOL)terminateApp:(NSString *)bundleID error:(NSError **)error {
	// 1) BackBoardServices private
	void *bks = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
	if (bks) {
		// void BKSTerminateApplicationForReasonAndReportWithDescription(NSString*, int, int, NSString*)
		void (*term)(CFStringRef, int, int, CFStringRef) = dlsym(bks, "BKSTerminateApplicationForReasonAndReportWithDescription");
		if (term) {
			term((__bridge CFStringRef)bundleID, 5, 0, (__bridge CFStringRef)@"SwitchBox");
		}
	}

	// 2) kill processes whose executable path contains the app bundle
	SBAppInfo *app = [self appInfoForBundleID:bundleID];
	NSString *exec = app.executableName;
	NSString *bundlePath = app.bundlePath;
	[self killProcessesMatchingExecutable:exec bundlePath:bundlePath];

	// 3) LSApplicationWorkspace private selector if any
	Class wsClass = [self workspaceClass];
	LSApplicationWorkspace *ws = [wsClass performSelector:@selector(defaultWorkspace)];
	// try -terminateApplication:withOptions: or similar via runtime
	NSArray *cands = @[
		@"terminateApplication:withOptions:",
		@"_terminateApplication:forReason:",
	];
	for (NSString *selName in cands) {
		SEL sel = NSSelectorFromString(selName);
		if ([ws respondsToSelector:sel]) {
			NSMethodSignature *sig = [ws methodSignatureForSelector:sel];
			if (sig.numberOfArguments >= 3) {
				NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
				inv.selector = sel;
				inv.target = ws;
				NSString *b = bundleID;
				[inv setArgument:&b atIndex:2];
				if (sig.numberOfArguments >= 4) {
					id arg3 = @{};
					[inv setArgument:&arg3 atIndex:3];
				}
				@try { [inv invoke]; } @catch (__unused NSException *ex) {}
			}
		}
	}
	return YES;
}

- (BOOL)openApp:(NSString *)bundleID error:(NSError **)error {
	Class wsClass = [self workspaceClass];
	if (!wsClass) {
		if (error) *error = [self err:@"LSApplicationWorkspace 不可用"];
		return NO;
	}
	LSApplicationWorkspace *ws = [wsClass performSelector:@selector(defaultWorkspace)];
	if ([ws respondsToSelector:@selector(openApplicationWithBundleID:)]) {
		BOOL ok = [ws openApplicationWithBundleID:bundleID];
		if (!ok && error) *error = [self err:@"打开失败"];
		return ok;
	}
	// URL scheme fallback
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleID]];
	if ([UIApplication.sharedApplication canOpenURL:url]) {
		[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
		return YES;
	}
	if (error) *error = [self err:@"无法打开该 App"];
	return NO;
}

- (NSError *)err:(NSString *)msg {
	return [NSError errorWithDomain:@"SwitchBox" code:1 userInfo:@{NSLocalizedDescriptionKey: msg}];
}

@end

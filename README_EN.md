# SwitchBox (切号箱)

[中文](./README.md) · [Releases](https://github.com/o2ol/switchbox/releases) · [MIT](./LICENSE)

TrollStore multi-profile account switcher: backup/restore app sandbox data, with optional device-ID seed reset on fresh profiles.

- **Author:** [o2ol](https://github.com/o2ol)
- **Version:** 1.2.0
- **Bundle:** `com.o2ol.switchbox`

## Support

| Item | Requirement |
|------|-------------|
| OS | iOS / iPadOS 15.0+ |
| Arch | arm64 |
| Devices | iPhone / iPad |
| Install | [TrollStore](https://github.com/opa334/TrollStore) |

## Features

- Multi-profile save/switch/rename/delete
- **Fresh profile with local device-ID seed reset**
- **Editable device-ID seeds** (manual edit / regenerate / apply live)
- Snapshot: data container + App Groups + Keychain
- Long-press quick switch, search
- Light/dark mode, URL schemes

## Recommended flow

1. Sign in as A → **Create from current** → name A  
2. **Create empty profile & reset IDs**  
3. Open app, sign in as B → **Create from current** → name B  
4. Switch between A / B later  

## Device-ID reset

On fresh profile creation:

1. Save the currently bound profile  
2. Wipe sandbox / App Groups / related Keychain items  
3. Generate local device / vendor / advertising UUID seeds  
4. Seed common preference keys; clear Cookies / WebKit session data  

> Without injection, **system IDFV/IDFA may stay the same**. Most useful for apps that store their own IDs. Not a true dual-instance like Crane.

## Install

1. Download `.tipa` / `.ipa` from [Releases](https://github.com/o2ol/switchbox/releases)  
2. Install with TrollStore  
3. Open → pick app → create / switch profiles  

## Build

```bash
export THEOS=/path/to/theos
./scripts/build_ipa.sh
```

## Scheme

```
switchbox://list
switchbox://manage?bundle=com.xxx.app
switchbox://switch?bundle=com.xxx.app&profile=Work
switchbox://open?bundle=com.xxx.app
```

## Backup path

On device: `/var/mobile/Library/SwitchBox/`

## Disclaimer

For personal maintenance on your own devices only. Use at your own risk. Compatibility and anti-fraud bypass are not guaranteed.

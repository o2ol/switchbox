# 切号箱 SwitchBox

[English](./README_EN.md) · [Releases](https://github.com/o2ol/switchbox/releases) · [MIT](./LICENSE)

TrollStore 多配置切号工具：备份/切换 App 沙盒数据，支持新建空配置并重置本地设备识别码。

- **作者：** [o2ol](https://github.com/o2ol)
- **版本：** 1.1.1
- **Bundle：** `com.o2ol.switchbox`

## 支持

| 项目 | 要求 |
|------|------|
| 系统 | iOS / iPadOS 15.0+ |
| 架构 | arm64 |
| 设备 | iPhone / iPad |
| 安装 | [TrollStore](https://github.com/opa334/TrollStore) |

## 功能

- 多配置存档：从当前新建 / 切换 / 重命名 / 删除
- **新建空配置并重置设备识别码**
- **编辑设备识别码**（手动改 / 重生成 / 应用到当前容器）
- 备份范围：数据容器 + App Group + Keychain
- 长按快速切号、搜索筛选
- 深浅色、URL Scheme

## 推荐流程

1. 登录账号 A → **从当前新建** → 命名 A  
2. **新建空配置并重置识别码**  
3. 打开 App 登录账号 B → **从当前新建** → 命名 B  
4. 之后在列表切换 A / B  

## 重置识别码

新建空配置时可选重置：

1. 保存当前已绑定配置  
2. 清空目标沙盒 / App Group / 相关 Keychain  
3. 生成本地 device / vendor / advertising 等 UUID 种子  
4. 写入 Preferences 常见字段，清理 Cookies / WebKit 等会话残留  

> 纯巨魔无法注入系统 API，**系统级 IDFV/IDFA 可能不变**。对读取自有存储识别码的 App 更有效。不是 Crane 式真正双开。

## 安装

1. 从 [Releases](https://github.com/o2ol/switchbox/releases) 下载 `.tipa` / `.ipa`  
2. 用 TrollStore 安装  
3. 打开 → 选择 App → 新建配置 / 切换  

## 构建

```bash
export THEOS=/path/to/theos
./scripts/build_ipa.sh
```

## Scheme

```
switchbox://list
switchbox://manage?bundle=com.xxx.app
switchbox://switch?bundle=com.xxx.app&profile=工作号
switchbox://open?bundle=com.xxx.app
```

## 备份位置

设备上：`/var/mobile/Library/SwitchBox/`

## 免责

仅供自有设备维护使用，风险自负。不保证兼容所有 App，不保证绕过任何风控。

# Bike 1.4.3 更新说明

发布日期：2026-09-10

## 修复

- 同步请求中断后再次同步，不再把尚未保存到本机的下载文档误判为本机删除。中途检查点只记录已经完成的远端上传、删除，下载基线在本地保存成功后才提交。
- Web/Electron、iOS 和 Android 保留同步期间的新编辑。遇到新编辑时暂缓应用下载结果；开启自动同步时安排再次同步。本地保存失败会报告错误，不会将下载标记为已经保存。
- 桌面同步保留移动端的快捷文档标记，以及文档、节点的未知扩展字段。
- iOS 和 Android 修改内容后清除过期 Markdown 缓存，避免桌面再次打开旧 Markdown；折叠、快捷标记和未改变内容的操作保留原文格式。
- 安装 Web 服务时保留已有 Sync 数据目录和数据库文件的归属。
- macOS Swift Native 同步和上传中断后保留已完成操作的检查点；拉取结果先保存到本机，再提交同步基线，保存失败时保留当前内存工作区。
- macOS Swift Native 延续同步期间的编辑保护，并增加返回结果前的工作区变化检查；快捷标记和扩展字段在 JSON 同步、Markdown 元数据保存与重新载入后继续保留。
- 修复 macOS Swift Native 复制 Markdown 文档后仍使用旧标题原文的问题。

## 部署改进

- 新增统一 Web/Sync Server 安装管理菜单，支持安装、更新、配置及服务管理。
- 缺少合适 Node.js 时，安装器可准备独立 Node.js 22 运行时。
- 修复同步数据库路径解析，并减少准备阶段不必要的服务用户创建。

## 发布产物

- `Bike-1.4.3-arm64.dmg`：Electron macOS Apple Silicon 客户端。
- `Bike-Native-1.4.3.dmg`：Swift Native macOS Apple Silicon 客户端，最低 macOS 15。
- `Bike-1.4.3-arm64.dmg.blockmap`、`latest-mac.yml`：Electron 更新元数据。
- `Bike-Web-1.4.3-sync-server.tar.gz`：Web/Sync Server 部署包。
- `SHA256SUMS-1.4.3.txt`：SHA-256 校验文件。

## 兼容性和升级说明

- 沿用 Workspace v1 与现有同步协议，无需迁移服务端数据库。升级前建议备份本机工作区及同步数据库。
- 同步仍按文档检测冲突，不会自动合并同一篇文档在不同设备上的并发修改。
- Sync Server 需要 Node.js 22.5.0 或更新版本，仍用于单用户个人同步。
- Electron 与 Swift Native macOS 包沿用本地 ad-hoc 签名，未进行 Apple 公证；首次打开可能需要在“系统设置 → 隐私与安全性”中允许运行。
- 本轮不发布新的 Android 或 iOS 安装包。移动端修复随源码提供，需要另行构建并安装后才会生效。
- 已经因旧版问题丢失的内容不会自动恢复，需要从已有备份找回。安装器修复保留现有权限，不会自动修复此前已经改错的服务器权限。

## 验证

- Node 回归测试：59/59 通过，覆盖同步故障恢复、同步期间编辑、本地保存失败、字段兼容、安装器权限及已有服务端和 MCP 功能。
- Android：52/52 单测通过，debug APK 构建通过；未执行设备 UI 测试，本轮不上传该测试 APK。
- iOS：SwiftPM 核心检查 23/23 通过，BikeiOSApp 的 SwiftPM 构建通过；iOS 模拟器完整构建因缺少 iOS 26.5 平台组件未完成。
- macOS Swift Native：新增 11 项同步/持久化回归测试及原有自检全部通过，测试工作区与同步配置使用隔离目录。
- macOS Swift Native 正式构建与 DMG 完整性、版本、深度签名检查通过；从挂载镜像启动后，在隔离目录中验证了标题编辑、Markdown 落盘及退出重启后的恢复。
- Web 生产构建通过；隔离浏览器中验证慢请求期间编辑可保存，后续同步可上传，控制台无错误。
- Electron DMG 完整性、挂载内容、版本和深度签名检查通过。直接运行挂载镜像中的应用，在隔离用户目录下完成编辑、保存和页面重新载入验证，未出现页面运行错误。
- 安装与服务脚本语法检查通过；安装权限检查使用模拟命令，未安装或重启实际系统服务。
- Web/Sync Server 部署包按文件清单打包，排除本机配置、数据库及调试产物；解压后验证 Web 登录、生产静态资源、同步鉴权和文档创建、读取、删除均通过。

主要验证命令：`npm test`、`npm run electron:dist:mac -- --publish never`、`swift run BikeCoreChecks`、`swift build --product BikeiOSApp`、`./gradlew testDebugUnitTest assembleDebug`、`hdiutil verify`、`codesign --verify --deep --strict`。

校验文件见本次 Release 的 [SHA256SUMS-1.4.3.txt](https://github.com/MoarLiu/Bike/releases/download/v1.4.3/SHA256SUMS-1.4.3.txt)。在所有发布资产下载到同一目录后运行 `shasum -a 256 -c SHA256SUMS-1.4.3.txt`。

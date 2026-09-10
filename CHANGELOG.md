# Changelog

## 1.4.3 — 2026-09-10

- 修复同步失败重试可能误删尚未保存到本机的远端文档。
- Web/Electron、iOS 和 Android 同步期间保留新编辑，下载结果落盘后再提交同步基线。
- 桌面端保留移动端快捷标记以及文档、节点的未知扩展字段。
- macOS Swift Native 补齐中断后的上传/删除检查点、先保存工作区再提交拉取基线，以及同步期间工作区变化的保护；字段可经 Markdown 元数据落盘后继续保留。
- 修复 macOS Swift Native 复制 Markdown 文档时仍使用旧标题缓存的问题。
- 移动端内容编辑使旧 Markdown 缓存失效，折叠、快捷标记和未改变内容的操作保留原文格式。
- 提供统一 Web/Sync Server 安装管理菜单、Node.js 自动准备及数据库路径修复；Web 安装不再接管已有 Sync 数据目录。
- 增加同步故障恢复、保存失败、编辑并发、字段兼容和安装权限的回归检查，并修复 Swift 检查入口的编译问题。

本次二进制资产为 Electron 与 Swift Native 的 macOS Apple Silicon DMG，以及 Web/Sync Server 部署包。移动端修复随源码提供，不包含新的 APK、IPA 或模拟器应用。

详见 [1.4.3 更新说明](docs/release-1.4.3.md)。更早版本记录见 [1.4.2](docs/release-1.4.2.md) 和 [1.4.1](docs/release-1.4.1.md)。

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

claude-lens 是 Claude Code 的轻量高性能 statusline 插件，用 Bash + jq 实现，替代基于 Node.js 的 claude-hud。

## 架构

热路径 (`claude-lens.sh`) 每 ~300ms 被 Claude Code 调用，需在 ~35ms 内完成：

- **stdin JSON** 直接提供 context、model、duration
- **Git 信息** 文件缓存于 `/tmp`，TTL 5s
- **Usage API** 文件缓存，TTL 300s + 异步后台刷新 (stale-while-revalidate)
- **工具/子代理/待办** 增量读取 transcript，通过字节偏移缓存 (TTL 2s)，仅用 `tail -c +<offset>` 读取新增字节

CLI 命令：
- `--install` - 将脚本注册为 Claude Code statusline（写入 settings.json）
- `--uninstall` - 移除 statusline 配置
- `--version` - 显示版本号
- `--benchmark N` - 运行 N 次性能基准测试

### 模块系统

每个 statusline 功能段是一个独立 bash 函数 (`module_<name>()`)，接收 jq 预解析的全局变量，输出 ANSI 着色文本。jq 只调用一次解析所有 stdin 字段。模块失败时输出缓存值或空字符串，绝不 exit 非零。

### 配置

- 位置优先级：`$CLAUDE_PLUGIN_DATA/config` > `~/.config/claude-lens/config`
- 格式：key=value，逐行读取 + 正则白名单验证（禁止 `source`，防止命令注入）
- 配置文件不存在时使用默认值（零配置承诺）

## 关键设计约束

- **热路径必须是纯 Bash + jq** - 禁用 Node.js、Python。300ms 轮询下每毫秒都重要。
- **文件缓存** 存于 `/tmp`，使用 `noclobber` 文件锁和原子写入。缓存必须跨进程重启存活。
- **O(1) transcript 解析** - 追踪字节偏移，禁止全量扫描。性能不能随会话时长退化。
- **优雅降级** - 任何数据源失败时，返回上次已知有效值。永远不能显示空白 statusline。
- **Stale-while-revalidate** - 永远不要让 statusline 阻塞在慢 API 调用上；先返回过期数据，后台刷新。

## 测试

- 单元/集成测试：bats-core
- 性能基准：hyperfine + 内置 `--benchmark`

## 状态

v0.2.1。962 行，70 个测试（61 unit + 9 integration）。与 claude-hud 功能基本对齐，有 7 项超越功能（趋势预测、成本追踪、pace tracking 等）。

# TODOS

## 推广 (2026-03-19)

**P1 - Reddit r/ClaudeAI 发帖**
标题: "I built a statusline that tells you if you're using Claude Code too fast or too slow"
正文讲故事（问题 → 方案 → 截图），附 GitHub 链接。
**Effort:** S | **Priority:** P1 | **When:** 周一至周三，北京时间晚 10 点（美东早 9 点）

**P2 - Hacker News Show HN**
标题: `Show HN: claude-lens – Bash statusline for Claude Code with pace tracking (~50ms)`
发帖后立刻自评论讲背景故事+技术亮点，前 2 小时在场回复所有评论。
**Effort:** S | **Priority:** P1 | **When:** 同上

**P3 - dev.to 技术文章**
角度: "如何用 Bash 在 300ms 轮询限制下实现 O(1) transcript 解析" 或 "从 Node.js 到纯 Bash 的性能优化"
**Effort:** M | **Priority:** P2 | **When:** 本周内

**P4 - 安装营销 skill**
从 coreyhaines31/marketingskills 取 launch-strategy 和 social-content skill，辅助后续推广。
**Effort:** S | **Priority:** P3

**P5 - awesome-claude-code 再试**
仓库当前限制了 issue 提交权限，关注是否开放或寻找维护者联系方式。
**Effort:** S | **Priority:** P2

---

## Crosscheck Fixes (2026-03-18)

**W2 - Config 白名单不够严格：** `load_config()` 接受任意 `[A-Z_]+` key，应限制为已知 key 列表（PRESET/SHOW_COST/SHOW_SPEED/SHOW_TREND/SHOW_USAGE）。
**Effort:** S | **Priority:** P2

**W3 - Transcript 解析脆弱：** 用 `grep -o` 抓 JSON 片段，遇到转义引号/复杂嵌套会误判。应改用 jq 解析增量 transcript 数据。
**Effort:** M | **Priority:** P2

**W4 - 热路径 fork 数优化：** ~~`$(run_module ...)` 每个模块一个 subshell，~~transcript 解析多次 grep/tail/wc 管道。考虑减少不必要的 fork。
v0.2.1 已完成：删除 run_module，替换 wc/tr/head/tail 为 bash 内置，缓存 `date +%s`。剩余：render() 中 10+ 个 `$(module_xxx)` subshell 仍在。
**Effort:** M | **Priority:** P2

## ~~README 清理~~ (已完成 - v0.2.0 README 重写)

## Feature Gaps (剩余)

**Provider/Plan 类型：** stdin JSON 无此字段，不可行。除非未来 CC 版本增加。
**Agents 运行时间：** 当前 transcript 无法可靠获取子代理启动时间戳。延后。
**Effort:** S | **Priority:** P3

## V2: Smart Information Density

**What:** 动态优先级显示 - 模块报告紧急级别，render 层按紧急程度分配空间。紧急状态（context >70%、rate limit 临近）获得更多视觉权重。

**Why:** V1 用静态颜色阈值（绿/黄/红），V2 迭代为智能仪表盘。

**Effort:** L (human) -> M (CC)
**Priority:** P2
**Depends on:** V1 模块架构稳定

## V2: Build-time Module Concatenation

**What:** 模块拆分为独立文件，Makefile 构建时拼接为单文件。

**Why:** V1 单文件 962 行，超过 500 行阈值。编辑体验开始下降。

**Effort:** S (human) -> S (CC)
**Priority:** P3
**Depends on:** V1 模块接口稳定

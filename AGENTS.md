# 项目概述

## Commercial authorization decision

Decision `2026-10-auth-1`: this remains a free content/community project. Do not add Permit commercial credentials, Commerce checkout, licensing accounts or a content paywall. Preserve source attribution, existing licenses and reader recovery/correction paths. Read the [portfolio authorization map](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/PORTFOLIO.md#authorization-integration-map) at each new slice and record the source/policy SHAs actually read; an updated file is not an acknowledgement by an already running agent.

## Required policy discovery at each slice

Before starting the next bounded slice, refresh remote state safely and re-read
this root AGENTS file, the repository's canonical implementation handoff, and
the current [family delivery standard](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/docs/PRODUCT-STANDARD.md),
[documentation language policy](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/docs/DOCUMENTATION-LANGUAGES.md)
and [portfolio decisions](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/PORTFOLIO.md).
Follow the corresponding Chinese links when preferred; both public user paths
must express the same promises. Product-specific plans and technical protocol
owners remain in their owning repositories.

Record the repository starting SHA and the central-policy commit/revision
actually read in the PR or handoff. A link's presence is not an acknowledgement
that an agent has read it. Existing conversations and stale checkouts do not
receive policy updates automatically: refresh these inputs at slice boundaries.
Preserve other agents' dirty worktrees; use an isolated checkout when needed,
without stashing, resetting or overwriting their work. Missing/offline policy
inputs must be reported as unverified, not silently claimed current.


王垠博客（yinwang.org）文章备份站，**Racket 全栈**：爬虫、校验、静态站生成同属一个 Racket 包，`raco yinwang-archive <命令>` 驱动。通过 API 爬取博文保存为 Markdown，生成静态站部署 GitHub Pages（GitHub Actions 每周一爬取）。posts 目录为**站点源文件**（不再考虑导回 Obsidian）。

## 命令（最重要）

```
raco yinwang-archive crawl [--force] [--root DIR]   # 爬取（增量；--force 全量）
raco yinwang-archive lint [--root DIR]              # 全量校验，CI 门禁，应恒 0 错误
raco yinwang-archive build [--out DIR] [--root DIR] # 生成静态站到 dist/
raco yinwang-archive fix-bold-spacing [--check|--dry-run]  # 修复坏强调
raco yinwang-archive normalize-code [--check]       # 顶层缩进代码转围栏
raco yinwang-archive notify [--root DIR]            # 新文章邮件（缺省 dry-run）
```

改完代码跑 `raco test -p yinwang-archive`（测试在 `yinwang-archive/tests/`）。

## 包结构（yinwang-archive/）

- `crawler.rkt`：主爬虫。增量逻辑 = source URL 去重 + `updated_at` 未变跳过；`format-content` 含自愈链（坏强调修复、顶层缩进代码转围栏、层级规范化、盘古空格），新爬内容自动规范化
- `format.rkt`：自愈链本体，`lint.rkt`/`fixers.rkt` 与其共享（lint 把 transform 输出与原文比较判损伤）
- `render.rkt`：Markdown → HTML。用 catalog 的 `markdown` 包解析 + 后处理对齐历史 markdown-it 行为：锚点 slugify（trim/lowercase/空白→`-`，重名加 `-1`）、figure div 还原为裸 img、`brush:` class 换 `language-x`、`**粗体**` 预转 `<strong>`（解析器对 CJK 相邻粗体有 bug）、smart typography 实体解回 ASCII
- `site.rkt`：全部页面模板（base/post/index/feed/search/sitemap/llms），浏览器端 JS（搜索/进度条/lightbox/TOC）原样保留——属合法薄壳层
- `build.rkt`：dist 写出。分页 50 篇/页，资产从 `src/site/` 与 `images/` 拷贝
- `notify.rkt`：git 未跟踪文件检测 + curl SMTP（Racket net/smtp 无 STARTTLS，smtp.qq.com 需要）
- `util.rkt`：含 **正则方言 shim**（`ws-chars`/`nl-char`/`tick-char` 等）与 python 兼容 JSON 序列化器

## 文件命名（最重要）

- **文件名 = frontmatter 的 `slug`**（如 `mites.md`），与站点 URL（`/posts/{slug}/`）、图片目录（`images/{slug}/`）三统一
- 中文标题只存在于 frontmatter 的 `title` 字段，不出现在文件名
- 少数文章源站 slug 本身是中文（如 `论研究.md`），保持原样——文件名即 slug，URL 不变

## frontmatter

```yaml
---
title: "我和螨虫的故事"
slug: mites
author: 王垠
created: 2026-07-15
updated: 2026-09-01
source: https://www.yinwang.org/posts/mites
---
```

- `title` 必填，双引号包裹（YAML 安全），值来自 API 返回的中文标题
- `slug` 必填（URL 最后一段）；`author`、`created`（API 的 publish_date）、`source` 必填
- `updated` 可选（API 的 updated_at，有则写入）
- 字段顺序固定：title → slug → author → created → updated → source

## 正文结构

- 正文以 `# {title}` 开始（每篇文件自包含）；渲染时剥掉首个 H1（页面头已有标题）
- 大节用 `##`，小节用 `###`
- 避免 `####` 及更深：爬虫会自动转为加粗段首词
- 若全文无 `##` 而有 `###`，爬虫自动把 `###` 升为 `##`（顶层小节统一 H2）
- 正文中的 `#` 如果不是标题而是代码（如 `#define`），必须用行内代码包裹

## 图片

- 图片存放在 `images/{slug}/` 目录
- 正文引用标准 Markdown 或 HTML：`![描述](/images/{slug}/文件名.png)`、`<img src="/images/{slug}/文件名.png" width="400">`

## 排版规范

- 段落之间空 1 行，段落内部无空行；列表项之间不加空行
- 代码块必须标注语言类型；**顶层缩进代码块会被渲染管线破坏，必须用围栏**（爬虫自动转换）
- CJK 与半角字符之间加空格（如 `使用 C++ 编程`），但 Markdown 标记（`*` `_` `~`）与内容之间**禁止**插空格，否则强调失效

## 去重与幂等

- 新增文章前，通过 frontmatter 的 `source` URL 检查是否已存在（`build_source_index()`）
- 爬虫默认增量：`updated_at` 未变的文章跳过，不会重写本地已修复的文件
- `index.json` 序列化与历史 Python `json.dump(indent=2)` **字节兼容**（`json-obj` 结构体保序 + 无尾换行），无变化爬取零 diff

## Racket 9.3 正则方言（大坑，必读）

本仓库跑在 Racket 9.3，其正则引擎**没有** `\d` `\s` `\w` 字母转义（写成字面字符）、`{n,m}` 量词、反向引用、POSIX 字符类；`(?m:)`/`(?s:)`/懒惰量词/环视可用；`regexp-match` 会裁掉尾部空组；`read-json` 产生**字符串键**（标准 Racket 是符号键）。所有模式一律用 `util.rkt` 的 shim（`ws-line-chars` 等）拼接，禁写 `\s`/`{3,}`/`\1`。

## 站点渲染对齐

- 样式表引用按**内容哈希**缓存指纹（`main.css?v=<sha1 前 10 位>`，`build.rkt` 算好经 `css-version` parameter 注入）——线上过 Cloudflare，改样式不改 URL 会拿到旧缓存（compact 头部对齐修复时踩过）

- 代码高亮：构建期只输出 `<pre><code class="language-x">`，高亮由 vendor 的 highlight.js 在浏览器端执行（`src/site/vendor/highlight.min.js`，common bundle）——浏览器驻留 UI 薄壳层
- 线上站（yinwang.jrtx.site）部署滞后于仓库时，正文对比会出现假差异；以 `posts/` 为准
- 喂给 feed 的 `<updated>` 用最新 `created`（历史 Eleventy 用文件时间戳，在 CI 上每次构建都变，改为确定性值）

## CI

- `ci.yml`：ubuntu + macos 双机跑 raco test / lint / build（push + PR）
- `crawl.yml`：每周一 UTC 03:00 爬取 + lint + notify + 自动 commit
- `deploy.yml`：push 到 main/master 构建 dist 部署 GH Pages
- 配方：`Bogdanp/setup-racket` → `raco pkg install --auto --no-docs markdown http-easy-lib` → `raco pkg install --auto --no-docs --link "$(pwd)"`

## 商业定调与界面取向

**阅读体验优先**。文章页：紧凑单行头部、768px 阅读列（~42 字/行）；**广告全线撤掉（不挂广告）**：AdSense 脚本与 meta、桌面双浮坑、移动单坑、ads.txt 已全部移除。**文章页内不放任何转化元素**（文尾公众号卡片曾试加，用户否决：突兀、图太小、生硬）。公众号转化只走两处：页脚一行链接 + `/wechat/` 专页（站长介绍 + 官方二维码 `wechat-qr.jpg` + 微信号，`build.rkt` 写出、sitemap 收录）。页脚两行极简：版权声明 + RSS/公众号链接（访问统计、站长主页、GitHub 链接、删除请求入口已裁撤——需要下架的版权方直接邮件联系站长）。阅读细节：方向键 ←/→ 切换上/下一篇（`site.rkt` 内联 JS）、`::selection`/focus-visible 主题色、引用块降噪（无底色填充）、行内代码不与链接抢色、vendor highlight.js 附带 lisp/scheme/haskell 语言包（common bundle 不含这三门，语料里有）。

## 产品交付与下一步（2026-10-23）

- 家族[交付标准](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/docs/PRODUCT-STANDARD.md)与[组合策略](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/PORTFOLIO.md)是共用政策；本仓具体行为以 `README.md` 为准，不复制五库依赖图。
- 当前执行入口：[产品审查 issue](https://github.com/turinglambdaai/yinwang-archive/issues/5)。保持免费内容维护：先验证来源/修订历史、链接/图片/代码渲染和失败抓取恢复。尊重既有阅读页与版权联系约定。
- 开工先检查干净工作树与远端，以 fast-forward-only 更新并记录 SHA；共享文件一次一个写入者，保留其他 checkout 的未提交工作。
- 每次只完成一个可验收切片，记录 owned files、依赖 pin、命令/平台/产物证据和回滚。已实现、已发布、实机验收分别陈述；不修改 requirements 或复用旧证据来制造通过。

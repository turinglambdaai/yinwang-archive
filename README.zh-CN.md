# Yinwang Blog Archive

王垠博客（[yinwang.org](https://www.yinwang.org)）文章自动备份。通过 GitHub Actions 每周自动爬取，将所有博文保存为 Markdown 文件并下载图片。已删除的文章通过 Git 历史保留。

![Racket](https://img.shields.io/badge/Racket-9E3E97?logo=racket&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[English](README.md) · **中文**

## 功能特性

- **Racket 全栈** — 爬虫、校验器、静态站生成器同属一个 Racket 包（`raco yinwang-archive …`）
- **每周自动爬取** — 通过 GitHub Actions 执行（每周一 UTC 03:00）
- **增量更新** — 仅下载新增或修改的文章
- **完整内容归档** — 文章保存为 Markdown，图片下载到本地
- **自包含 Markdown** — 文件名 = URL slug，中文标题存 frontmatter，正文以 H1 标题开始
- **自动去重** — 通过 source URL 跟踪，避免重复文件
- **静态站点生成** — 纯 Racket 构建（无 Node）的可搜索网站，部署到 GitHub Pages

## 项目结构

```
yinwang-archive/
├── posts/           # Markdown 文章（文件名 = slug）
├── images/          # 文章图片（按 URL slug 分目录）
├── yinwang-archive/       # Racket 包：爬虫、格式化、校验、建站
├── src/site/        # 静态资产（样式、favicon、自托管 highlight.js）
└── index.json       # 文章元数据索引
```

## 环境要求

- [Racket](https://racket-lang.org)（stable 版本即可）

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/turinglambdaai/yinwang-archive.git
cd yinwang-archive
```

### 2. 安装包

```bash
raco pkg install --auto --no-docs --link "$(pwd)"
```

### 3. 运行管线

```bash
# 增量爬取（仅新增/更新的文章）
raco yinwang-archive crawl

# 强制重新下载所有文章
raco yinwang-archive crawl --force

# 全量校验（CI 门禁）
raco yinwang-archive lint

# 构建静态站点（输出到 dist/）
raco yinwang-archive build
```

### 修复工具

```bash
raco yinwang-archive fix-bold-spacing [--check|--dry-run]  # 修复 `** 文字 **` 坏强调
raco yinwang-archive normalize-code [--check]              # 顶层缩进代码转围栏
raco yinwang-archive notify                                # 新文章邮件提醒（缺省 dry-run）
```

所有命令支持 `--root DIR`，可在任意目录对指定检出操作。

## 工作原理

1. **获取文章列表** — 爬虫调用 `https://www.yinwang.org/api/v1/posts` 接口，通过分页参数（`skip`/`limit`）获取所有文章 slug。
2. **去重检查** — 根据已有的 `source` URL 构建索引，避免生成重复文件。
3. **逐篇下载** — 对每个 slug，从 `https://www.yinwang.org/api/v1/posts/{slug}` 获取完整文章内容。
4. **下载图片** — 文章中引用的所有图片下载到 `images/{slug}/` 目录。
5. **格式化并保存** — 对内容进行排版处理（CJK 间距、标题层级规范化、代码块转围栏），生成带 YAML frontmatter 的 Markdown 文件。
6. **更新索引** — 将每篇已处理文章的元数据更新到 `index.json`（与历史 Python 序列化器字节兼容，无变化时不产生 diff）。
7. **建站** — 生成器将 Markdown 渲染为 HTML（标题锚点、围栏代码 + 客户端 highlight.js、Atom 订阅、搜索索引、sitemap、llms.txt）输出到 `dist/`。

### 文章格式

每个 Markdown 文件以 URL slug 命名，完全自包含：

```markdown
---
title: "我的博客文章"
slug: my-blog-post
author: 王垠
created: 2025-01-15
source: https://www.yinwang.org/posts/my-blog-post
---
# 我的博客文章

## 第一节

正文……
```

- 文件名 = `slug`（即 URL `/posts/{slug}/` 与图片目录 `images/{slug}/`，三者统一）
- 中文标题存于 frontmatter 的 `title` 字段；正文以 H1 标题开始
- 大节用 H2；爬虫会自动规范化标题层级与代码围栏

## 新文章提醒（可选）

每周爬取发现新文章时，工作流可给你发一封摘要邮件，方便你决定是否分享到公众号。通过仓库 Secrets 配置（Settings → Secrets and variables → Actions）：

| Secret      | 值                                          |
| ----------- | ------------------------------------------- |
| `SMTP_HOST` | 如 `smtp.qq.com`                            |
| `SMTP_USER` | 发件账号，如 `you@qq.com`                    |
| `SMTP_PASS` | SMTP 授权码（非登录密码）                    |
| `NOTIFY_TO` | 收件地址，通常与发件账号相同                  |

未配置时该步骤仅本地输出，无副作用。邮件经 `curl` 的 SMTP 客户端发送（STARTTLS），需 `PATH` 上有 `curl`。

## RSS

站点提供 Atom 订阅：`/feed.xml`（最新 20 篇，标题 + 链接 + 简短摘要）。有意不输出全文——内容归原作者所有。

## 许可证

仓库代码（Racket 包与工作流）基于 [MIT License](LICENSE) 开源；posts/ 下的博客内容版权归原作者所有，仅供个人存档阅读。

## 版权

本站为备份存档，仅供阅读便利，不销售任何文章内容，文章版权归原作者所有。

# Yinwang Blog Archive

Auto-crawled archive of [yinwang.org](https://www.yinwang.org) blog posts by Wang Yin. The crawler runs weekly via GitHub Actions, saving every post as Markdown with images. Deleted articles are preserved through Git history.

![Racket](https://img.shields.io/badge/Racket-9E3E97?logo=racket&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**English** · [中文](README.zh-CN.md)

## Features

- **Racket full-stack** — crawler, linter and static site generator are one Racket package (`raco yinwang-archive …`)
- **Automated weekly crawl** via GitHub Actions (every Monday at 03:00 UTC)
- **Incremental updates** — only downloads new or modified posts
- **Full content archival** — posts saved as Markdown, images downloaded locally
- **Self-contained Markdown** — file name = URL slug, Chinese title in frontmatter, body starts with an H1 heading
- **Deduplication** — prevents duplicate files by tracking source URLs
- **Static site generation** — builds a searchable website (Racket, no Node) and deploys to GitHub Pages

## Project Structure

```
yinwang-archive/
├── posts/           # Markdown articles (file name = URL slug)
├── images/          # Post images (organized by URL slug)
├── yinwang-archive/       # Racket package: crawler, formatter, linter, site builder
├── src/site/        # Static assets (styles, favicon, vendored highlight.js)
└── index.json       # Post metadata index
```

## Requirements

- [Racket](https://racket-lang.org) (stable; any 8.x+)

## Quick Start

### 1. Clone

```bash
git clone https://github.com/turinglambdaai/yinwang-archive.git
cd yinwang-archive
```

### 2. Install the package

```bash
raco pkg install --auto --no-docs --link "$(pwd)"
```

### 3. Run the pipeline

```bash
# Incremental crawl (only new/updated posts)
raco yinwang-archive crawl

# Force re-download all posts
raco yinwang-archive crawl --force

# Validate all posts (CI gate)
raco yinwang-archive lint

# Build the static site (output: dist/)
raco yinwang-archive build
```

### Repair tools

```bash
raco yinwang-archive fix-bold-spacing [--check|--dry-run]  # heal `** text **` emphasis
raco yinwang-archive normalize-code [--check]              # indented code -> fences
raco yinwang-archive notify                                # email new posts (dry-run default)
```

All commands accept `--root DIR` to operate on a checkout elsewhere than
the current directory.

## How It Works

1. **Fetch post list** — the crawler calls `https://www.yinwang.org/api/v1/posts` with pagination (`skip`/`limit`) to get all post slugs.
2. **Deduplicate** — it builds an index of existing posts by `source` URL to avoid duplicates.
3. **Download each post** — for each slug, it fetches the full post content from `https://www.yinwang.org/api/v1/posts/{slug}`.
4. **Download images** — all images referenced in the post are downloaded to `images/{slug}/`.
5. **Format and save** — the content is reformatted (CJK spacing, heading normalization, code fence conversion) and saved as a Markdown file with YAML frontmatter.
6. **Update index** — `index.json` is updated with metadata for each processed post (byte-compatible with the historical Python serializer, so no-op crawls stay diff-free).
7. **Build** — the site generator renders Markdown → HTML (heading anchors, fenced code with client-side highlight.js, Atom feed, search index, sitemap, llms.txt) into `dist/`.

### Post format

Each Markdown file is named after its URL slug and is fully self-contained:

```markdown
---
title: "My Blog Post"
slug: my-blog-post
author: 王垠
created: 2025-01-15
source: https://www.yinwang.org/posts/my-blog-post
---
# My Blog Post

## First Section

Body text...
```

- File name = `slug` (= URL `/posts/{slug}/` = image dir `images/{slug}/`).
- The Chinese title lives in frontmatter; the body starts with an H1 heading.
- Top-level sections use H2; the crawler normalizes heading depth and code fences automatically.

## Update Notifications (optional)

When the weekly crawl finds new posts, the workflow can email you a
summary so you can decide whether to share them. Configure via repo
secrets (Settings → Secrets and variables → Actions):

| Secret      | Value                                        |
| ----------- | -------------------------------------------- |
| `SMTP_HOST` | e.g. `smtp.qq.com`                           |
| `SMTP_USER` | the from-account, e.g. `you@qq.com`          |
| `SMTP_PASS` | SMTP authorization code (not login password) |
| `NOTIFY_TO` | recipient, usually the same address          |

Without the secrets the step is a harmless dry run. Delivery goes
through `curl`'s SMTP client (STARTTLS), which must be on `PATH`.

## RSS

The site publishes an Atom feed at `/feed.xml` (latest 20 posts, title +
link + short excerpt). Full text is intentionally not re-published —
the content belongs to its author.

## License

The code (Racket package & workflows) is licensed under the MIT License;
the archived posts remain copyrighted by their author — see [LICENSE](LICENSE).

## Copyright

All archived posts are copyrighted by their original author. This archive
is kept for reading convenience; no content is sold or relicensed.

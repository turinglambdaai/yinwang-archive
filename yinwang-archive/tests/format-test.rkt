#lang racket/base

;; Tests for the content formatting pipeline (Python crawler parity).

(require rackunit
         racket/string
         "../format.rkt"
         "../util.rkt")

;; ---- indented code -> fences ----

(test-case "indented code at top level becomes a fence"
  (check-equal?
   (indented-code-to-fences "para:\n\n    code line\n    more\n\nafter")
   "para:\n\n```text\ncode line\nmore\n```\n\nafter"))

(test-case "list-context indented block stays verbatim"
  (check-equal?
   (indented-code-to-fences "- item\n    continuation\n- next")
   "- item\n    continuation\n- next"))

(test-case "blank line inside block kept only when content follows"
  (check-equal?
   (indented-code-to-fences "    a\n\n    b\n\nplain")
   "```text\na\nb\n```\n\nplain"))

(test-case "fenced blocks are untouched"
  (check-equal?
   (indented-code-to-fences "```text\n    indented inside\n```\n")
   "```text\n    indented inside\n```\n"))

(test-case "already converted content is a fixed point"
  (define s "para\n\n```text\ncode\n```\n\ntail")
  (check-equal? (indented-code-to-fences s) s))

;; ---- emphasis healing ----

(test-case "broken bold is healed"
  (check-equal? (fix-emphasis-spacing "** bold text **") "**bold text**"))

(test-case "healed bold is a fixed point"
  (check-equal? (fix-emphasis-spacing "**bold**") "**bold**"))

(test-case "punctuation neighbours are healed"
  (check-equal? (fix-emphasis-spacing "**加粗 **。**后**") "**加粗**。**后**"))

(test-case "inline code is protected"
  (check-equal? (fix-emphasis-spacing "use `** not bold **` here")
                "use `** not bold **` here"))

(test-case "fenced blocks are protected"
  (check-equal? (fix-emphasis-spacing "```\n** x **\n```")
                "```\n** x **\n```"))

(test-case "whole-line italic lead-in is healed"
  (check-equal? (fix-emphasis-spacing "* an intro *") "*an intro*"))

;; ---- heading promotion ----

(test-case "h3 promoted to h2 when no h2 exists"
  (check-equal? (promote-h3-to-h2 "# T\n\n### A\n\ntext")
                "# T\n\n## A\n\ntext"))

(test-case "h3 kept when h2 exists"
  (check-equal? (promote-h3-to-h2 "# T\n\n## S\n\n### A")
                "# T\n\n## S\n\n### A"))

;; ---- the full chain ----

(test-case "format-content is idempotent on formatted input"
  (define s "# 标题\n\n## 节\n\n这是 CJK 与 English 混排的内容。\n\n```text\n代码 保持原样\n```\n")
  (check-equal? (format-content s) s))

(test-case "pangu spacing inserts CJK half-width gaps"
  (check-equal? (format-content "使用Racket编程写Python代码")
                "使用 Racket 编程写 Python 代码"))

(test-case "pangu leaves emphasis markers tight (the * class is excluded)"
  (check-equal? (format-content "**加粗内容**后续")
                "**加粗内容**后续"))

(test-case "bare fences get a text language"
  (check-equal? (format-content "```\ncode\n```")
                "```text\ncode\n```"))

(test-case "obsidian callouts are stripped"
  (check-equal? (format-content "> [!note] 注意事项")
                "> **注意事项**"))

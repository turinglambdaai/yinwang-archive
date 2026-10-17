#lang racket/base

;; Tests for the markdown rendering pipeline (markdown-it parity).

(require rackunit
         racket/string
         "../render.rkt"
         "../util.rkt")

;; ---- heading anchors ----

(test-case "h2/h3 get markdown-it-anchor style ids"
  (define html (render-document "## Section 平台\n\n### 深入 讨论"))
  (check-true (string-contains? html "<h2 id=\"section-平台\">"))
  (check-true (string-contains? html "<h3 id=\"深入-讨论\">")))

(test-case "duplicate headings get -1 suffixes"
  (define html (render-document "## 同名\n\n## 同名"))
  (check-true (string-contains? html "<h2 id=\"同名\">"))
  (check-true (string-contains? html "<h2 id=\"同名-1\">")))

(test-case "leading h1 is stripped from post bodies"
  (define html (render-body "# 标题\n\n正文"))
  (check-false (string-contains? html "<h1"))
  (check-true (string-contains? html "正文")))

;; ---- images ----

(test-case "markdown images render as bare img (not figure)"
  (define html (render-document "![](/images/a/1.png)"))
  (check-false (string-contains? html "figure"))
  (check-true (string-contains? html "<img src=\"/images/a/1.png\" alt=\"\">")))

(test-case "markdown images keep their alt text"
  (define html (render-document "![说明](/images/a/1.png)"))
  (check-true (string-contains? html "alt=\"说明\"")))

(test-case "raw img lines are not wrapped in paragraphs"
  (define html (render-document "\n<img src=\"/images/a/1.jpeg\" width=\"400\">\n"))
  (check-false (string-contains? html "<p><img"))
  (check-true (string-contains? html "<img src=\"/images/a/1.jpeg\" width=\"400\">")))

;; ---- code blocks ----

(test-case "fenced code gets a language- class for highlight.js"
  (define html (render-document "```java\nint x = 1;\n```"))
  (check-true (string-contains? html "<pre><code class=\"language-java\">"))
  (check-true (string-contains? html "int x = 1;")))

(test-case "code content is html-escaped"
  (define html (render-document "```text\na < b && c\n```"))
  (check-true (string-contains? html "a &lt; b &amp;&amp; c")))

;; ---- bold preprocessing (CJK adjacency) ----

(test-case "adjacent bold spans survive CJK punctuation"
  (define html (render-document "课程包括了**纯函数式编程**、**命令式编程**的核心内容"))
  (check-true (string-contains? html "<strong>纯函数式编程</strong>、<strong>命令式编程</strong>"))
  (check-false (string-contains? html "<em>、</em>")))

(test-case "broken italics render literal asterisks (markdown-it parity)"
  (define html (render-document "而远得很…… *Go 语言 * 关于 Go"))
  (check-true (string-contains? html "&ast;Go 语言 &ast;"))
  (check-false (string-contains? html "<em>Go 语言</em>")))

(test-case "tight italics still render as emphasis"
  (define html (render-document "*斜体*、**粗体**"))
  (check-true (string-contains? html "<em>斜体</em>"))
  (check-true (string-contains? html "<strong>粗体</strong>")))

;; ---- smart typography is undone ----

(test-case "smart dashes decode back to ascii (corpus uses single hyphens)"
  (define html (render-document "乙醇 72%-87% strong"))
  (check-true (string-contains? html "72%-87%")))

(test-case "smart apostrophes decode back to ascii"
  (define html (render-document "Murphy's Law"))
  (check-true (string-contains? html "Murphy's Law")))

;; ---- excerpt ----

(test-case "excerpt strips tags and truncates"
  (check-equal? (excerpt-of "<p>第一段</p><p>第二段</p>" 5) "第一段 第…")
  (check-equal? (excerpt-of "<p>短的</p>") "短的"))

#lang racket/base

;; Tests for frontmatter, filename sanitizing and the python-compatible
;; index.json serializer.

(require rackunit
         racket/dict
         racket/string
         "../frontmatter.rkt"
         "../util.rkt")

;; ---- frontmatter ----

(define mites-slug "mites")

(test-case "frontmatter round-trips"
  (define fm (generate-frontmatter "标\"题" mites-slug "王垠" "2026-07-15" #f "https://www.yinwang.org/posts/mites"))
  (check-equal? fm "---\ntitle: \"标\\\"题\"\nslug: mites\nauthor: 王垠\ncreated: 2026-07-15\nsource: https://www.yinwang.org/posts/mites\n---\n")
  (define parsed (parse-frontmatter (string-append fm "body")))
  (check-equal? (dict-ref parsed 'title) "标\"题")
  (check-equal? (dict-ref parsed 'slug) mites-slug))

(test-case "updated field only when present"
  (define fm (generate-frontmatter "t" "s" "王垠" "2026-01-01" "2026-02-02" "https://x"))
  (check-true (string-contains? fm "updated: 2026-02-02")))

(test-case "filename sanitize strips hostiles"
  (check-equal? (sanitize-filename "a/b:c*d?e\"f<g>h|i") "abcdefghi")
  (check-equal? (sanitize-filename "  ") "untitled")
  (check-equal? (sanitize-filename "论研究") "论研究"))

;; ---- python json parity ----

(test-case "serializer matches python json.dump(indent=2)"
  (define doc
    (json-obj
     (list (cons "posts"
                 (json-obj
                  (list (cons "mites"
                              (json-obj
                               (list (cons 'title "我和螨虫的故事")
                                     (cons 'slug "mites")
                                     (cons 'updated_at 'null)
                                     (cons 'tags (list "life"))
                                     (cons 'has_images #t))))))))))
  (check-equal?
   (jsexpr->python-json doc)
   (string-append
    "{\n"
    "  \"posts\": {\n"
    "    \"mites\": {\n"
    "      \"title\": \"我和螨虫的故事\",\n"
    "      \"slug\": \"mites\",\n"
    "      \"updated_at\": null,\n"
    "      \"tags\": [\n"
    "        \"life\"\n"
    "      ],\n"
    "      \"has_images\": true\n"
    "    }\n"
    "  }\n"
    "}")))

(test-case "json strings are escaped"
  (check-equal? (json-escape "a\"b\\c") "\"a\\\"b\\\\c\""))

;; ---- jref accepts both key dialects ----

(test-case "jref reads string-keyed and symbol-keyed hashes"
  (define hs (hash "title" "字符串键"))
  (define hy (hash 'title "符号键"))
  (check-equal? (jref hs 'title) "字符串键")
  (check-equal? (jref hy 'title) "符号键")
  (check-equal? (jref hs 'missing 'fallback) 'fallback))

;; ---- anchors ----

(test-case "anchor slug matches markdown-it-anchor slugify"
  (check-equal? (anchor-slug "  如何用 6 元钱解决螨虫问题 ") "如何用-6-元钱解决螨虫问题")
  (check-equal? (anchor-slug "德国 / 瑞士科技？") "德国-/-瑞士科技？"))


#lang racket/base

;; Post file format: YAML frontmatter (fixed field order) + body that
;; starts with the post's H1 title.

(require racket/string
         racket/match
         "util.rkt")

(provide (all-defined-out))

(define frontmatter-re (string-append "^---" nl-char "(?s:(.*?)" nl-char ")---" nl-char))

;; (hash/c string? string?) for the simple `key: value` frontmatter we
;; write; #f when the file has no frontmatter.
;; the crawler quotes string values (title) and escapes inner quotes
(define (unquote-value v)
  (define unquoted
    (if (and (>= (string-length v) 2)
             (string-prefix? v "\"")
             (string-suffix? v "\""))
        (substring v 1 (- (string-length v) 1))
        v))
  (string-replace unquoted "\\\"" "\""))

(define (parse-frontmatter text)
  (define m (regexp-match frontmatter-re text))
  (and m
       (for/hash ([line (in-list (string-split (cadr m) "\n"))]
                  #:when (non-empty-string? (string-trim line)))
         (match (regexp-match (string-append "^([A-Za-z_]+):[" ws-line-chars "]*(.*)$") line)
           [(list _ k v)
            (values (string->symbol k) (unquote-value (string-trim v)))]
           [#f (values (string->symbol (string-trim line)) "")]))))

(define (frontmatter-body text)
  (define m (regexp-match frontmatter-re text))
  (if m (substring text (string-length (car m))) text))

;; Serialize frontmatter in the fixed field order
;; title -> slug -> author -> created -> [updated] -> source.
(define (generate-frontmatter title slug author created updated source)
  (define lines
    (append
     (list (format "title: \"~a\"" (string-replace title "\"" "\\\""))
           (format "slug: ~a" slug)
           (format "author: ~a" author)
           (format "created: ~a" created))
     (if (and updated (non-empty-string? updated))
         (list (format "updated: ~a" updated))
         '())
     (list (format "source: ~a" source))))
  (string-append "---\n" (string-join lines "\n") "\n---\n"))

;; Filenames must survive three-way sync: strip filesystem-hostile
;; characters, matching the crawler's sanitize_filename.
(define (sanitize-filename name)
  (define cleaned
    (for/fold ([s name]) ([ch '(#\\ #\/ #\: #\* #\? #\" #\< #\> #\|)])
      (string-replace s (string ch) "")))
  (define trimmed (string-trim cleaned))
  (if (equal? trimmed "") "untitled" trimmed))

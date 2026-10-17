#lang racket/base

;; Post integrity linter — the same five checks as scripts/lint_posts.py:
;;   1. frontmatter has title/slug/author/created/source (updated optional)
;;   2. body starts with an H1 heading
;;   3. no broken emphasis (`** text **` etc.)
;;   4. no top-level indented code blocks (they break the build pipeline)
;;   5. code fences are balanced
;; Exit non-zero on the first class of damage found.

(require racket/path
         racket/string
         racket/list
         racket/file
         racket/format
         "util.rkt"
         "format.rkt"
         "frontmatter.rkt")

(provide lint-file
         lint-posts
         lint-command
         required-fields)

(define required-fields '("title" "slug" "author" "created" "source"))

(define (lint-file path)
  (define text (file->string path #:mode 'text))
  (define name (path->string (file-name-from-path path)))
  (define m (regexp-match frontmatter-re text))
  (cond
    [(not m) (list (format "~a: missing frontmatter" name))]
    [else
     (define fm (cadr m))
     (define body (substring text (string-length (car m))))
     (append
      (for/list ([field (in-list required-fields)]
                 #:unless (regexp-match? (string-append "(?m:^" field ":[" ws-line-chars "]*[^" ws-chars "])") fm))
        (format "~a: frontmatter missing '~a'" name field))
      (let ([first-line (for/first ([l (in-list (string-split body "\n" #:trim? #f))]
                                    #:when (non-empty-string? (string-trim l)))
                          l)])
        (if (and first-line (string-prefix? first-line "# "))
            '()
            (list (format "~a: body must start with an H1 heading" name))))
      (if (equal? (fix-emphasis-spacing text) text)
          '()
          (list (format "~a: broken emphasis (run raco yinwang-archive fix-bold-spacing)" name)))
      (if (equal? (indented-code-to-fences text) text)
          '()
          (list (format "~a: top-level indented code (run raco yinwang-archive normalize-code)" name)))
      (let ([fence-count
             (count fence-line? (string-split body "\n" #:trim? #f))])
        (if (even? fence-count)
            '()
            (list (format "~a: unbalanced code fences (~a)" name fence-count)))))]))

;; Lint every post under root/posts; returns (values errors file-count).
;; #f path lints all files.
(define (lint-posts [root (current-directory)] [single-file #f])
  (define files
    (if single-file
        (list single-file)
        (sort
         (filter (λ (p) (string-suffix? (path->string p) ".md"))
                 (directory-list (posts-dir root) #:build? #t))
         path<?)))
  (define errors
    (append-map lint-file files))
  (values errors (length files)))

;; CLI entry: prints and returns the process exit code.
(define (lint-command root)
  (define-values (errors n) (lint-posts root))
  (cond
    [(not (null? errors))
     (printf "\n~a files linted, ~a error(s):\n" n (length errors))
     (for ([e (in-list errors)]) (printf "  ~a\n" e))
     1]
    [else
     (printf "\n~a files linted, all clean\n" n)
     0]))

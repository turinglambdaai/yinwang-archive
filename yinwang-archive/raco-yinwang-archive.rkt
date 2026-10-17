#lang racket/base

;; raco yinwang-archive — command dispatch for the archive pipeline.
;;   crawl [--force] [--root DIR]          fetch new/updated posts
;;   lint [--root DIR]                     validate all posts (CI gate)
;;   fix-bold-spacing [--check|--dry-run]  heal `** text **` emphasis
;;   normalize-code [--check]              indented code -> fences
;;   dedent-tab FILE                       strip one leading tab per line
;;   build [--out DIR] [--root DIR]        generate the static site
;;   notify [--root DIR]                   email new posts (dry-run default)

(require racket/match
         racket/string
         "lint.rkt"
         "fixers.rkt"
         "crawler.rkt"
         "build.rkt"
         "notify.rkt")

(provide main)

;; pull "--flag VALUE" out of an arg list
(define (flag-value args name)
  (let loop ([xs args])
    (match xs
      ['() #f]
      [(cons a rest)
       (if (equal? a name)
           (and (pair? rest) (car rest))
           (loop rest))])))

(define (has-flag? args name)
  (and (member name args) #t))

(define (dispatch args)
  (define root
    (or (flag-value args "--root") "."))
  (define root-path (expand-user-path root))
  (match args
    [(list-rest "crawl" _)
     (crawl-command root-path (has-flag? args "--force"))]
    [(list-rest "lint" _)
     (lint-command root-path)]
    [(list-rest "fix-bold-spacing" _)
     (fix-bold-command root-path
                       #:check (has-flag? args "--check")
                       #:dry-run (has-flag? args "--dry-run"))]
    [(list-rest "normalize-code" _)
     (normalize-code-command root-path #:check (has-flag? args "--check"))]
    [(list-rest "dedent-tab" (cons file _))
     (dedent-tab-command (expand-user-path file))]
    [(list-rest "build" _)
     (define out (or (flag-value args "--out")
                     (path->string (build-path root-path "dist"))))
     (build-site #:root root-path #:out (expand-user-path out))]
    [(list-rest "notify" _)
     (notify-command root-path)]
    [_
     (displayln "usage: raco yinwang-archive <command> [flags]")
     (displayln "  crawl [--force] [--root DIR]        fetch new/updated posts from yinwang.org")
     (displayln "  lint [--root DIR]                   validate all posts")
     (displayln "  fix-bold-spacing [--check|--dry-run]  heal broken emphasis")
     (displayln "  normalize-code [--check]            indented code -> fences")
     (displayln "  dedent-tab FILE                     strip one leading tab per line")
     (displayln "  build [--out DIR] [--root DIR]      build the static site (default dist/)")
     (displayln "  notify [--root DIR]                 email new posts (dry-run default)")
     2]))

(define (main [args (vector->list (current-command-line-arguments))])
  (define code (dispatch args))
  (exit (if (number? code) code 0)))

;; raco runs this module directly
(main)

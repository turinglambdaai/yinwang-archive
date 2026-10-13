#lang racket/base

;; Repair tools — ports of scripts/fix_bold_spacing.py and
;; scripts/normalize_code_blocks.py, including their --check / --dry-run
;; modes.

(require racket/path
         racket/string
         racket/list
         racket/file
         racket/format
         "util.rkt"
         "format.rkt")

(provide fix-bold-command
         normalize-code-command
         dedent-tab-command)

(define (post-files root)
  (sort
   (filter (λ (p) (string-suffix? (path->string p) ".md"))
           (directory-list (posts-dir root) #:build? #t))
   path<?))

(define (fix-bold-command [root (current-directory)]
                          #:check [check? #f]
                          #:dry-run [dry-run? #f])
  (define changed 0)
  (for ([f (in-list (post-files root))])
    (define original (file->string f #:mode 'text))
    (define fixed (fix-emphasis-spacing original))
    (unless (equal? fixed original)
      (set! changed (+ changed 1))
      (cond
        [check? (printf "NEEDS FIX: ~a\n" (path->string (file-name-from-path f)))]
        [dry-run?
         (printf "would fix: ~a\n" (path->string (file-name-from-path f)))
         (for ([a (in-list (string-split original "\n" #:trim? #f))]
               [b (in-list (string-split fixed "\n" #:trim? #f))])
           (unless (equal? a b)
             (printf "  - ~a\n  + ~a\n" a b)))]
        [else
         (write-utf8! f fixed)
         (printf "fixed: ~a\n" (path->string (file-name-from-path f)))])))
  (printf "\n~a file(s) ~a\n"
          changed
          (cond [check? "damaged"] [dry-run? "would fix"] [else "fixed"]))
  (if (and check? (> changed 0)) 1 0))

(define (normalize-code-command [root (current-directory)] #:check [check? #f])
  (define changed 0)
  (for ([f (in-list (post-files root))])
    (define original (file->string f #:mode 'text))
    (define fixed (indented-code-to-fences original))
    (unless (equal? fixed original)
      (set! changed (+ changed 1))
      (cond
        [check? (printf "NEEDS FIX: ~a\n" (path->string (file-name-from-path f)))]
        [else
         (write-utf8! f fixed)
         (printf "normalized: ~a\n" (path->string (file-name-from-path f)))])))
  (printf "\n~a file(s) ~a\n" changed (if check? "damaged" "normalized"))
  (if (and check? (> changed 0)) 1 0))

(define (dedent-tab-command file)
  (write-utf8! file (dedent-tab (file->string file #:mode 'text)))
  (printf "dedented: ~a\n" (path->string (file-name-from-path file)))
  0)

#lang racket/base

;; Content formatting pipeline: a faithful port of the Python
;; crawler/format chain (crawler.py + fix_bold_spacing.py +
;; normalize_code_blocks.py). Byte-stable on already-formatted posts so
;; weekly crawls and lint --check stay diff-free.
;;
;; All regexps are built from the util.rkt dialect shims: the 9.3 engine
;; has no letter escapes, {n,m} quantifiers or backreferences.

(require racket/string
         racket/list
         racket/vector
         racket/match
         "util.rkt")

(provide stash-marker
         promote-h3-to-h2
         indented-code-to-fences
         dedent-tab
         fix-emphasis-spacing
         format-content
         fence-line?                ; ^\s*```...$  (lint / fixers)
         fence-open-re              ; ^(\s{0,3})(`{3,})([^`]*)$
         find-inline-code-spans)

;; ---- shared fence detection ----

;; Whole-line fences only; a lone ```code``` run (info string containing
;; a backtick) is inline text, not a fence. (`{3,} becomes ``` plus a
;; zero-or-more run of the same character.)
(define fence-line-re
  (regexp (string-append "^[" ws-line-chars "]*```" tick-char "*"
                         "[^" tick-char "]*$")))

(define (fence-line? line)
  (regexp-match? fence-line-re line))

;; ^(\s{0,3})(`{3,})([^`]*)$  — the {0,3} expanded by hand
(define fence-open-re
  (regexp (string-append "^([" ws-line-chars "]?[" ws-line-chars "]?[" ws-line-chars "]?)"
                         "(```" tick-char "*)"
                         "([^" tick-char "]*)$")))

;; ---- indented code -> fences (normalize_code_blocks.py) ----

(define indent-re
  (regexp (string-append "^(?:[" (string #\tab) "]|    )([^" ws-chars "].*)$")))
(define list-item-re
  (regexp (string-append "^[" ws-line-chars "]*(?:[0-9]+[.]|[-*+])[" ws-line-chars "]")))

(define (strip-one-indent line)
  (cond
    [(string-prefix? line "\t") (substring line 1)]
    [(string-prefix? line "    ") (substring line 4)]
    [else line]))

(define (dedent-tab content)
  (string-join
   (for/list ([line (in-list (string-split content "\n" #:trim? #f))])
     (if (string-prefix? line "\t") (substring line 1) line))
   "\n"))

(define (append-rev items out-rev)
  (foldl cons out-rev items))

(define (indented-code-to-fences content)
  (define lines (list->vector (string-split content "\n" #:trim? #f)))
  (define n (vector-length lines))
  (define (indented? k)
    (regexp-match? indent-re (vector-ref lines k)))
  (let walk ([i 0] [in-fence? #f] [out-rev '()])
    (cond
      [(>= i n) (string-join (reverse out-rev) "\n")]
      [(fence-line? (vector-ref lines i))
       (walk (+ i 1) (not in-fence?) (cons (vector-ref lines i) out-rev))]
      [(and (not in-fence?) (indented? i))
       ;; collect the full indented run (a blank line belongs to the
       ;; block only when indented content follows it)
       (define-values (j block-rev)
         (let collect ([k i] [acc '()])
           (cond
             [(>= k n) (values k acc)]
             [(and (non-empty-string? (string-trim (vector-ref lines k)))
                   (not (indented? k)))
              (values k acc)]
             [(and (not (non-empty-string? (string-trim (vector-ref lines k))))
                   (< (+ k 1) n)
                   (not (indented? (+ k 1))))
              (values k acc)]
             [else (collect (+ k 1) (cons (vector-ref lines k) acc))])))
       (define block (reverse block-rev))
       ;; list context? the last non-blank line before the block decides
       (define prev
         (for/first ([l (in-list out-rev)]
                     #:when (non-empty-string? (string-trim l)))
           l))
       (if (and prev (regexp-match? list-item-re prev))
           (walk j in-fence? (append-rev block out-rev))
           (walk j in-fence?
                 (append-rev
                  (append '("```text")
                          (for/list ([l (in-list block)]
                                     #:when (non-empty-string? (string-trim l)))
                            (strip-one-indent l))
                          '("```"))
                  out-rev)))]
      [else
       (walk (+ i 1) in-fence? (cons (vector-ref lines i) out-rev))])))

;; ---- emphasis healing (fix_bold_spacing.py) ----

(define bold-re
  (regexp (string-append "\\*\\*[" ws-line-chars "]*"
                         "([^*" nl-char "]+?)"
                         "[" ws-line-chars "]*\\*\\*")))
(define bold-close-punct-re (regexp "\\*\\* +([，。！？；：）】」])"))
(define bold-open-punct-re (regexp "([，。！？；：（【「]) +\\*\\*"))
(define italic-line-re
  (regexp (string-append "^\\*[" ws-line-chars "]+(.+?)[" ws-line-chars "]+\\*$")))

;; python INLINE_CODE_RE: (`+)([^`]|[^`][\s\S]*?[^`])\1(?!`) — a run of
;; k ticks closed by a run of exactly k ticks. The engine has no
;; backreferences, so the spans are found with a scanner.
(define (find-inline-code-spans content)
  (define n (string-length content))
  (define (tick-run-at i)
    (let loop ([j i])
      (if (and (< j n) (char=? (string-ref content j) #\`))
          (loop (+ j 1))
          j)))
  ;; end index of a run of exactly k ticks starting at or after `from`
  (define (find-close from k)
    (define run (make-string k #\`))
    (let scan ([i from])
      (cond
        [(> (+ i k) n) #f]
        [(and (or (zero? i) (not (char=? (string-ref content (- i 1)) #\`)))
              (equal? (substring content i (+ i k)) run)
              (or (= (+ i k) n)
                  (not (char=? (string-ref content (+ i k)) #\`))))
         (+ i k)]
        [else (scan (+ i 1))])))
  (let loop ([i 0] [spans '()])
    (cond
      [(>= i n) (reverse spans)]
      [(char=? (string-ref content i) #\`)
       (define j (tick-run-at i))
       (define k (- j i))
       (define close (find-close j k))
       (cond
         [close (loop close (cons (cons i close) spans))]
         [else (loop j spans)])]
      [else (loop (+ i 1) spans)])))

(define stash-marker "\uE000")

(define (fix-text-outside-code content)
  (define spans (find-inline-code-spans content))
  ;; stash inline code spans so their asterisks are never touched
  (define protected
    (let build ([i 0] [rest spans] [n-stashed 0] [acc '()])
      (match rest
        ['() (string-append* (reverse (cons (substring content i) acc)))]
        [(cons (cons s e) more)
         (build e more (+ n-stashed 1)
                (cons (string-append stash-marker
                                     (number->string n-stashed)
                                     stash-marker)
                      (cons (substring content i s) acc)))])))
  (define fixed
    (regexp-replace* bold-open-punct-re
                     (regexp-replace* bold-close-punct-re
                                      (regexp-replace* bold-re protected "**\\1**")
                                      "**\\1")
                     "\\1**"))
  ;; per-line rewrite for the italic lead-ins
  (define fixed2
    (string-join
     (for/list ([line (in-list (string-split fixed "\n" #:trim? #f))])
       (regexp-replace* italic-line-re line "*\\1*"))
     "\n"))
  ;; unstash the inline code spans
  (define stash-texts
    (for/list ([sp (in-list spans)]) (substring content (car sp) (cdr sp))))
  (regexp-replace* (regexp (string-append stash-marker "([0-9]+)" stash-marker))
                   fixed2
                   (λ (_m num) (list-ref stash-texts (string->number num)))))

(define (fix-emphasis-spacing content)
  (string-join
   (let loop ([lines (string-split content "\n" #:trim? #f)] [in-code? #f])
     (cond
       [(null? lines) '()]
       [(fence-line? (car lines))
        (cons (car lines) (loop (cdr lines) (not in-code?)))]
       [else
        (cons (if in-code? (car lines) (fix-text-outside-code (car lines)))
              (loop (cdr lines) in-code?))]))
   "\n"))

;; ---- heading normalization (crawler.py) ----

;; If the body has no H2 but has H3s, promote H3 -> H2 so the top
;; section level is consistently H2 under the post's H1 title.
(define (promote-h3-to-h2 content)
  (define fence-re
    (regexp (string-append "^[" ws-line-chars "]*```" tick-char "*")))
  (define (scan-lines content)
    (string-split content "\n" #:trim? #f))
  (define-values (has-h2? has-h3?)
    (for/fold ([h2? #f] [h3? #f])
              ([line (in-list (scan-lines content))])
      (cond
        [(regexp-match? fence-re line) (values h2? h3?)]
        [(regexp-match? (regexp "^## ") line) (values #t h3?)]
        [(regexp-match? (regexp "^### ") line) (values h2? #t)]
        [else (values h2? h3?)])))
  (if (or has-h2? (not has-h3?))
      content
      (let loop ([lines (scan-lines content)] [in-fence? #f] [acc '()])
        (cond
          [(null? lines) (string-join (reverse acc) "\n")]
          [(regexp-match? fence-re (car lines))
           (loop (cdr lines) (not in-fence?) (cons (car lines) acc))]
          [in-fence?
           (loop (cdr lines) in-fence? (cons (car lines) acc))]
          [else
           (loop (cdr lines) in-fence?
                 (cons (regexp-replace (regexp "^### ") (car lines) "## ") acc))]))))

;; ---- the full chain (crawler.py format_content) ----

;; ^#{4,}\s+(.+)$  — four hashes then a zero-or-more hash run
(define heading-depth-re
  (regexp (string-append "(?m:^####" "#" "*[" ws-line-chars "]+(.+)$)")))

(define (format-content content)
  ;; heading-level: top section level is H2 (post title is the H1)
  (define c0 (promote-h3-to-h2 content))

  ;; heading-depth: #### or deeper -> bold paragraph start
  (define c1 (regexp-replace* heading-depth-re c0 "**\\1**"))

  ;; indented-code: top-level indented code blocks break the site build,
  ;; convert them to fenced blocks first
  (define c2 (indented-code-to-fences c1))

  ;; callout: strip Obsidian callout syntax
  (define callout-bold-re
    (regexp (string-append
             "(?m:^>[" ws-line-chars "]*\\[![a-zA-Z0-9_]+\\]"
             "[" ws-line-chars "]*(\\*\\*.+\\*\\*)[" ws-line-chars "]*$)")))
  (define callout-re
    (regexp (string-append
             "(?m:^>[" ws-line-chars "]*\\[![a-zA-Z0-9_]+\\]"
             "[" ws-line-chars "]*(.+)$)")))
  (define c3a (regexp-replace* callout-bold-re c2 "> \\1"))
  (define c3 (regexp-replace* callout-re c3a "> **\\1**"))

  ;; code-lang: add `text` to bare opening code fences
  (define c4
    (let* ([lines (list->vector (string-split c3 "\n" #:trim? #f))]
           [n (vector-length lines)])
      (let loop ([i 0] [in-code? #f])
        (cond
          [(>= i n) (string-join (vector->list lines) "\n")]
          [else
           (define m (regexp-match fence-open-re (vector-ref lines i)))
           (cond
             [(not m) (loop (+ i 1) in-code?)]
             [(not in-code?)
              (define fence (list-ref m 2)) ; group 2 is the tick run
              ;; the engine omits trailing empty groups; guard the index
              (define info (string-trim (if (>= (length m) 4) (or (list-ref m 3) "") "")))
              (when (equal? info "")
                (vector-set! lines i (string-append fence "text")))
              (loop (+ i 1) #t)]
             [else (loop (+ i 1) #f)])]))))

  ;; cjk-spacing: Pangu spacing (CJK <-> half-width). The half-width class
  ;; deliberately EXCLUDES markdown emphasis markers (* _ ~): inserting a
  ;; space there breaks `**bold**` into literal asterisks.
  (define p0 c4)
  ;; step 1: remove existing incorrect spaces
  (define p1 (regexp-replace* (regexp "([一-鿿，。！？；：]) ([a-zA-Z0-9%])") p0 "\\1\\2"))
  (define p2 (regexp-replace* (regexp "([a-zA-Z0-9%]) ([一-鿿，。！？；：])") p1 "\\1\\2"))
  ;; step 2: insert spaces between CJK and half-width characters
  (define p3 (regexp-replace* (regexp "([一-鿿，。！？；：])([a-zA-Z0-9@#$%&+={}<>/\\\\|^])") p2 "\\1 \\2"))
  (define p4 (regexp-replace* (regexp "([a-zA-Z0-9@#$%&+={}<>/\\\\|^])([一-鿿，。！？；：])") p3 "\\1 \\2"))
  ;; step 3a: collapse spaces inside markdown links
  (define p5 (regexp-replace* (regexp "([一-鿿]) \\]") p4 "\\1]"))
  (define p6 (regexp-replace* (regexp "\\] \\(") p5 "]("))
  (define p7 (regexp-replace* (regexp "\\] ([一-鿿]) \\(") p6 "]\\1("))
  ;; step 3b: no space after full-width punctuation before CJK
  (define p8 (regexp-replace* (regexp "([，。！？；：]) ([一-鿿])") p7 "\\1\\2"))
  ;; step 3c: no space between digit and percent sign
  (define p9 (regexp-replace* (regexp "([0-9]) %") p8 "\\1%"))

  ;; list-spacing: remove blank lines between consecutive list items
  (define list-item-line-re
    (regexp (string-append "^[" ws-line-chars "]*[-*+][" ws-line-chars "]")))
  (define c5
    (let loop ([lines (string-split p9 "\n" #:trim? #f)] [acc '()])
      (match lines
        ['() (string-join (reverse acc) "\n")]
        [(cons a rest)
         (match rest
           [(cons blank (cons b _))
            #:when (and (regexp-match? list-item-line-re a)
                        (equal? (string-trim blank) "")
                        (regexp-match? list-item-line-re b))
            (loop (cons blank rest) (cons a acc))]
           [_ (loop rest (cons a acc))])])))

  ;; multi-blank: max 1 blank line between paragraphs
  (define c6 (regexp-replace* (regexp (string-append nl-char nl-char nl-char "+")) c5 "\n\n"))
  (define c7 (regexp-replace* (regexp "\n\n\n") c6 "\n\n"))

  ;; strip trailing whitespace
  (define c8 (regexp-replace* (regexp (string-append " +" nl-char)) c7 "\n"))

  ;; emphasis-spacing: heal `** bold **` back to `**bold**`
  (fix-emphasis-spacing c8))

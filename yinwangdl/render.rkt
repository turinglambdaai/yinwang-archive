#lang racket/base

;; Markdown -> HTML rendering, aligned with the historical Eleventy
;; pipeline (markdown-it + markdown-it-anchor + highlight.js):
;;   - raw HTML passes through (bare <img> lines are emitted verbatim,
;;     not wrapped in a paragraph)
;;   - h2/h3 get anchor ids via markdown-it-anchor's slugify
;;   - the leading H1 (post title) is stripped — the page header renders it
;;   - code fences render as <pre><code class="language-x"> and are
;;     highlighted client-side by the vendored highlight.js
;; The `markdown` package (greghendershott) does the parsing; these
;; post-passes normalize its output (figure divs, brush: classes) to the
;; shapes markdown-it produced.

(require markdown
         racket/string
         racket/list
         racket/match
         racket/format
         "util.rkt"
         "format.rkt")

(provide render-body
         render-document
         excerpt-of
         preprocess-tables
         add-heading-ids
         unwrap-figures
         unwrap-paragraph-images
         normalize-code-pre
         element-attrs
         element-body
         element?
         xexpr-text
         table->html)

;; ---- pipe-table fallback (the parser has no table support) ----
;; A fenced run of `| a | b |` lines whose second line is a separator is
;; converted to raw HTML before parsing. The corpus currently contains
;; none; this keeps future crawls from silently degrading.

(define (table-line? l)
  (and (string-prefix? (string-trim l) "|")
       (string-suffix? (string-trim l) "|")))

(define (separator-line? l)
  (define t (string-trim l))
  (and (table-line? t)
       (regexp-match? (string-append "^\\|( :?--+:? ?\\|)+$") t)))

(define (split-row l)
  (define t (string-trim l))
  (define inner (substring t 1 (- (string-length t) 1)))
  (map string-trim (string-split inner "|")))

(define (table->html lines)
  (define rows (map split-row lines))
  (define header (car rows))
  (define body-rows (cddr rows))
  (string-append
   "<table>\n<thead>\n<tr>"
   (string-append* (for/list ([h (in-list header)])
                     (format "<th>~a</th>" (html-escape h))))
   "</tr>\n</thead>\n<tbody>\n"
   (string-append*
    (for/list ([r (in-list body-rows)])
      (string-append
       "<tr>"
       (string-append* (for/list ([c (in-list r)])
                         (format "<td>~a</td>" (html-escape c))))
       "</tr>\n"))
    )
   "</tbody>\n</table>"))

(define (preprocess-tables content)
  (define lines (string-split content "\n" #:trim? #f))
  (string-join
   (let loop ([ls lines] [acc '()])
     (match ls
       ['() (reverse acc)]
       [(cons a (cons b rest))
        #:when (and (table-line? a) (separator-line? b))
        (define table-lines
          (take-while ls (λ (l) (table-line? l))))
        (loop (drop ls (length table-lines))
              (cons (table->html table-lines) acc))]
       [(cons a rest)
        (loop rest (cons a acc))]))
   "\n"))

(define (take-while ls pred?)
  (cond
    [(null? ls) '()]
    [(pred? (car ls)) (cons (car ls) (take-while (cdr ls) pred?))]
    [else '()]))

;; The parser here splits `**a**、**b**` into single-asterisk emphasis
;; pairs around CJK punctuation (markdown-it handled this correctly).
;; Convert double-asterisk bold spans to raw <strong> HTML before
;; parsing; fenced blocks and inline code spans are left untouched.
(define bold-raw-re (regexp "\\*\\*([^*\n]+?)\\*\\*"))

;; markdown-it renders a `*...*` pair as literal asterisks when either
;; side of the pair touches whitespace (CommonMark flanking rules); the
;; parser here makes it emphasis anyway. Escape such broken pairs to
;; &ast; so both engines agree. Tight pairs are left for the parser.
(define (escape-broken-italics line)
  (define n (string-length line))
  (define (ws? i)
    (and (<= 0 i (- n 1)) (char-whitespace? (string-ref line i))))
  (let loop ([i 0] [acc '()])
    (cond
      [(>= i n) (string-append* (reverse acc))]
      [(and (char=? (string-ref line i) #\*)
            (< (+ i 1) n)
            (char=? (string-ref line (+ i 1)) #\*))
       ;; a leftover ** run: emit verbatim
       (loop (+ i 2) (cons "**" acc))]
      [(char=? (string-ref line i) #\*)
       (define j
         (for/first ([k (in-range (+ i 1) n)]
                     #:when (char=? (string-ref line k) #\*))
           k))
       (cond
         [(not j) (loop (+ i 1) (cons "*" acc))]
         [else
          (define content (substring line (+ i 1) j))
          (if (or (ws? (+ i 1)) (and (> (string-length content) 0)
                                     (char-whitespace? (string-ref content (- (string-length content) 1)))))
              (loop (+ j 1)
                    (cons "&ast;" (cons content (cons "&ast;" acc))))
              (loop (+ j 1) (cons (substring line i (+ j 1)) acc)))])]
      [else
       (loop (+ i 1) (cons (substring line i (+ i 1)) acc))])))

(define (preprocess-bold content)
  (define (convert-line line)
    (define spans (find-inline-code-spans line))
    (define stash-texts
      (for/list ([sp (in-list spans)]) (substring line (car sp) (cdr sp))))
    (define protected
      (let build ([i 0] [rest spans] [n 0] [acc '()])
        (match rest
          ['() (string-append* (reverse (cons (substring line i) acc)))]
          [(cons (cons s e) more)
           (build e more (+ n 1)
                  (cons (string-append stash-marker (number->string n) stash-marker)
                        (cons (substring line i s) acc)))])))
    (define converted
      (escape-broken-italics
       (regexp-replace* bold-raw-re protected "<strong>\\1</strong>")))
    (regexp-replace* (regexp (string-append stash-marker "([0-9]+)" stash-marker))
                     converted
                     (λ (_m num) (list-ref stash-texts (string->number num)))))
  (string-join
   (let loop ([lines (string-split content "\n" #:trim? #f)] [in-fence? #f])
     (cond
       [(null? lines) '()]
       [(fence-line? (car lines))
        (cons (car lines) (loop (cdr lines) (not in-fence?)))]
       [else
        (cons (if in-fence? (car lines) (convert-line (car lines)))
              (loop (cdr lines) in-fence?))]))
   "\n"))

;; ---- xexpr helpers ----

(define (element? x tag)
  (and (list? x) (pair? x) (eq? (car x) tag)))

(define (element-attrs x)
  (if (and (>= (length x) 2) (list? (cadr x)) (andmap pair? (cadr x)))
      (cadr x)
      '()))

(define (element-body x)
  (if (and (>= (length x) 2) (list? (cadr x)) (andmap pair? (cadr x)))
      (cddr x)
      (cdr x)))

(define (replace-attr attrs k v)
  (append
   (filter (λ (kv) (not (eq? (car kv) k))) attrs)
   (list (list k v))))

(define (attr-value attrs k)
  (for/first ([kv (in-list attrs)] #:when (eq? (car kv) k))
    (cadr kv)))

;; concatenated plain text of inline content
(define (xexpr-text x)
  (cond
    [(string? x) x]
    [(raw? x) (raw-text x)]
    [(list? x) (string-append* (map xexpr-text (element-body x)))]
    [else ""]))

;; ---- post-processing passes ----

;; markdown-it-anchor parity: ids on h2/h3, document order, dedup with -1
(define (add-heading-ids elements)
  (define headings
    (filter (λ (x) (or (element? x 'h2) (element? x 'h3))) elements))
  (define ids
    (assign-anchor-ids (map anchor-slug (map xexpr-text headings))))
  (for/list ([x (in-list elements)])
    (if (or (element? x 'h2) (element? x 'h3))
        (let* ([attrs (element-attrs x)]
               [id (car ids)]
               [_ (set! ids (cdr ids))])
          (cons (car x) (cons (replace-attr attrs 'id id) (element-body x))))
        x)))

;; (div ((class "figure")) (img ...) (p ((class "caption")) ...)) -> (img ...)
;; with the caption restored as the alt text (markdown-it inline image).
(define (unwrap-figures x)
  (cond
    [(not (list? x)) x]
    [(and (element? x 'div)
          (equal? (attr-value (element-attrs x) 'class) "figure"))
     (define body (element-body x))
     (define img (findf (λ (b) (element? b 'img)) body))
     (define caption
       (for/first ([b (in-list body)]
                   #:when (and (element? b 'p)
                               (equal? (attr-value (element-attrs b) 'class) "caption")))
         (string-trim (xexpr-text b))))
     (cond
       [img
        (define attrs (element-attrs img))
        (define alt (attr-value attrs 'alt))
        (define final-attrs
          (cond
            [(and caption (non-empty-string? caption))
             (replace-attr attrs 'alt caption)]
            [(eq? alt #f) (cons (list 'alt "") attrs)]
            [else attrs]))
        (list 'img final-attrs)]
       [else (map unwrap-figures x)])]
    [else (map unwrap-figures x)]))

;; (p (img ...)) -> (img ...): markdown-it emits a bare <img> line as a
;; raw HTML block, not wrapped in a paragraph.
(define (unwrap-paragraph-images x)
  (cond
    [(not (list? x)) x]
    [(and (element? x 'p)
          (= (length (element-body x)) 1)
          (element? (car (element-body x)) 'img))
     (car (element-body x))]
    [else (map unwrap-paragraph-images x)]))

;; (pre ((class "brush: lang")) (code text)) ->
;; (pre () (code ((class "language-lang")) text)) for highlight.js
(define (normalize-code-pre x)
  (cond
    [(not (list? x)) x]
    [(and (element? x 'pre)
          (let ([cls (attr-value (element-attrs x) 'class)])
            (and (string? cls) (string-prefix? cls "brush:"))))
     (define lang
       (let* ([cls (attr-value (element-attrs x) 'class)]
              [rest (string-trim (substring cls (string-length "brush:")))])
         (string-trim (car (string-split rest ";" #:trim? #f)))))
     (define code-el (findf (λ (b) (element? b 'code)) (element-body x)))
     (if code-el
         (list 'pre '()
               (list* 'code (list (list 'class (format "language-~a" lang)))
                          (element-body code-el)))
         x)]
    [else (map normalize-code-pre x)]))

;; ---- public API ----

;; Full post body -> HTML. The body's leading H1 title is dropped.
(define (render-body body)
  (define elements (parse-markdown (preprocess-bold (preprocess-tables body))))
  (define without-h1
    (if (and (pair? elements) (element? (car elements) 'h1))
        (cdr elements)
        elements))
  (string-append*
   (for/list ([x (in-list
                  (normalize-code-pre
                   (unwrap-paragraph-images
                    (unwrap-figures
                     (add-heading-ids without-h1)))))])
     (xexpr->html x))))

;; Render a markdown document as-is (no H1 stripping) — used for tests.
(define (render-document md)
  (string-append*
   (for/list ([x (in-list
                  (normalize-code-pre
                   (unwrap-paragraph-images
                    (unwrap-figures
                     (add-heading-ids (parse-markdown (preprocess-bold md)))))))])
     (xexpr->html x))))

;; Plain-text excerpt of rendered HTML for the Atom feed: strip tags,
;; collapse whitespace, cut at n chars with an ellipsis.
(define (excerpt-of html [n 140])
  (define text
    (string-trim
     (regexp-replace* (regexp (string-append "[" ws-chars "]+"))
                      (regexp-replace* (regexp "<[^>]+>") html " ")
                      " ")))
  (if (> (string-length text) n)
      (string-append (substring text 0 n) "…")
      text))

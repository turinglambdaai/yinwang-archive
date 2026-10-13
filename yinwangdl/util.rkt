#lang racket/base

;; Shared helpers: repo layout, HTML escaping, xexpr writing, date/slug
;; helpers and a Python-json-compatible serializer for index.json.

(require racket/file
         racket/path
         racket/string
         racket/date
         racket/format
         racket/list
         racket/match)

(provide (all-defined-out))

;; ---- regexp dialect shims ----
;; Racket 9.3's regexp engine has no \d/\s/\w letter escapes (a letter
;; escape matches the literal letter), no {n,m} quantifiers, no
;; backreferences and no POSIX classes. Build those pieces from real
;; characters instead.
(define ws-chars (string #\space #\tab #\newline #\return #\u00A0 #\u3000))
(define ws-line-chars (string #\space #\tab))
(define ws-class (string-append "[" ws-chars "]"))
(define not-ws-class (string-append "[^" ws-chars "]"))
(define nl-char (string #\newline))
(define tick-char (string #\`))

;; ---- repo layout (commands run with the repo root as working dir) ----

(define (posts-dir [root (current-directory)])
  (build-path root "posts"))
(define (images-dir [root (current-directory)])
  (build-path root "images"))
(define (index-file [root (current-directory)])
  (build-path root "index.json"))
(define (site-src-dir [root (current-directory)])
  (build-path root "src" "site"))

(define base-url "https://www.yinwang.org")
(define site-name "王垠博客备份")
(define site-base-url (or (getenv "SITE_BASE_URL") "https://yinwang.jrtx.site"))
(define site-language (or (getenv "SITE_MAIN_LANGUAGE") "zh"))

;; ---- utf-8 file io ----

(define (read-post-file path)
  (with-input-from-file path
    (λ () (read-string (file-size path)))
    #:mode 'text))

(define (write-utf8! path content)
  (make-directory* (path-only path))
  (with-output-to-file path
    (λ () (display content))
    #:mode 'text
    #:exists 'replace))

;; ---- html escaping ----

(define (html-escape s)
  (string-append*
   (for/list ([c (in-string s)])
     (case c
       [(#\&) "&amp;"]
       [(#\<) "&lt;"]
       [(#\>) "&gt;"]
       [else (string c)]))))

(define (html-escape-attr s)
  (string-append*
   (for/list ([c (in-string s)])
     (case c
       [(#\&) "&amp;"]
       [(#\<) "&lt;"]
       [(#\>) "&gt;"]
       [(#\") "&quot;"]
       [(#\') "&#39;"]
       [else (string c)]))))

;; ---- xexpr writing ----
;; Renders an xexpr tree as HTML. Attribute values are always quoted and
;; escaped; text content escapes &, <, >. Raw strings can be injected with
;; (raw "...") nodes for pre-rendered fragments.

(struct raw (text) #:transparent)

;; HTML void elements: written without a closing tag
(define void-elements '(img br hr input meta link source wbr col embed track area base param))

(define (write-xexpr x [out (current-output-port)])
  (cond
    [(raw? x) (display (raw-text x) out)]
    [(string? x) (display (html-escape x) out)]
    ;; entity: the markdown package represents &ndash; as the symbol ndash
    ;; and rewrites dashes/quotes through "smart" typography; the source
    ;; posts use ASCII punctuation (markdown-it kept it literal), so the
    ;; smart entities are decoded back. The corpus has single hyphens in
    ;; prose (ranges like 72%-87%), so both dash entities decode to "-".
    ;; Literal CJK quote characters are strings and pass through.
    [(symbol? x)
     (display
      (case x
        [(mdash ndash) "-"]
        [(hellip) "..."]
        [(rsquo lsquo) "'"]
        [(rdquo ldquo) "\""]
        [else (string-append "&" (symbol->string x) ";")])
      out)]
    ;; a bare number is a character code (parser artifact, e.g. 124 = |)
    [(number? x) (display (string (integer->char x)) out)]
    [(list? x)
     (match x
       [(list tag attributes body ...)
        #:when (and (symbol? tag) (list? attributes))
        (fprintf out "<~a" tag)
        (for ([kv (in-list attributes)])
          (match kv
            [(list k v)
             (fprintf out " ~a=\"~a\"" k (html-escape-attr (if (string? v) v (format "~a" v))))]))
        (cond
          [(memq tag void-elements) (display ">" out)]
          [(null? body)
           (fprintf out "></~a>" tag)]
          [else
           (display ">" out)
           (for ([b (in-list body)]) (write-xexpr b out))
           (fprintf out "</~a>" tag)])]
       [(list tag body ...)
        #:when (symbol? tag)
        (write-xexpr (list* tag '() body) out)]
       [_ (error 'write-xexpr "bad xexpr: ~a" x)])]
    [else (error 'write-xexpr "bad xexpr: ~a" x)]))

(define (xexpr->html x)
  (let ([out (open-output-string)])
    (write-xexpr x out)
    (get-output-string out)))

;; ---- dates ----

;; "2026-07-15" or "2026-07-15T..." -> "2026-07-15"
(define (isodate d)
  (and d (string? d) (>= (string-length d) 10) (substring d 0 10)))

(define (year-of d)
  (cond
    [(not d) "Unknown"]
    [(string? d) (substring d 0 (min 4 (string-length d)))]
    [else "Unknown"]))

;; Current UTC time as an RFC 3339 / ISO 8601 timestamp (feed <updated>).
(define (now-iso-utc)
  (define now (current-seconds))
  (define d (seconds->date now #f))
  (format "~a-~a-~aT~a:~a:~a.000Z"
          (~r (date-year d) #:min-width 4 #:pad-string "0")
          (~r (date-month d) #:min-width 2 #:pad-string "0")
          (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0")
          (~r (date-minute d) #:min-width 2 #:pad-string "0")
          (~r (date-second d) #:min-width 2 #:pad-string "0")))

;; ---- jsexpr lookup ----
;; read-json on this build yields string keys (standard Racket yields
;; symbols); accept both so the crawler survives either dialect.
(define (jref h key [default #f])
  (cond
    [(not (hash? h)) default]
    [(hash-has-key? h key) (hash-ref h key)]
    [(hash-has-key? h (if (symbol? key) (symbol->string key) (string->symbol key)))
     (hash-ref h (if (symbol? key) (symbol->string key) (string->symbol key)))]
    [else default]))

;; ---- anchor slugs (markdown-it-anchor parity) ----
;; slugify: s.trim().toLowerCase().replace(/\s+/g, "-"), then first
;; duplicate gets "-1", second "-2", ... (uniqueSlugStartIndex = 1).

(define (anchor-slug text)
  (regexp-replace* (regexp (string-append "[" ws-chars "]+"))
                   (string-trim (string-downcase text))
                   "-"))

;; markdown-it-anchor parity: first duplicate of a slug gets "-1", the
;; second "-2", etc. Takes heading texts in document order, returns ids.
(define (assign-anchor-ids texts)
  (define seen (make-hash))
  (for/list ([base (in-list texts)])
    (let loop ([n 0])
      (define candidate (if (zero? n) base (format "~a-~a" base n)))
      (if (hash-has-key? seen candidate)
          (loop (+ n 1))
          (begin (hash-set! seen candidate #t) candidate)))))

;; ---- python json.dump(indent=2, ensure_ascii=False) compatible ----
;; index.json is read and rewritten by the crawler; byte-stable output
;; keeps weekly no-op crawls diff-free. JSON objects are a (json-obj
;; ((key . value) ...)) struct so insertion order survives the round
;; trip (python dicts are ordered, hashes are not); arrays are lists;
;; JSON null is the symbol 'null.

(struct json-obj (fields) #:transparent)

(define (jsexpr->python-json v [indent 0])
  (define pad (make-string indent #\space))
  (define pad2 (make-string (+ indent 2) #\space))
  (cond
    [(json-obj? v)
     (define fields (json-obj-fields v))
     (if (null? fields)
         "{}"
         (string-append "{\n"
                        (string-join
                         (for/list ([kv (in-list fields)])
                           (format "~a~a: ~a"
                                   pad2
                                   (json-escape (if (string? (car kv)) (car kv) (~a (car kv))))
                                   (jsexpr->python-json (cdr kv) (+ indent 2))))
                         ",\n")
                        "\n"
                        pad
                        "}"))]
    [(list? v)
     (if (null? v)
         "[]"
         (string-append "[\n"
                        (string-join
                         (for/list ([item (in-list v)])
                           (string-append pad2 (jsexpr->python-json item (+ indent 2))))
                         ",\n")
                        "\n"
                        pad
                        "]"))]
    [(string? v) (json-escape v)]
    [(eq? v 'null) "null"]
    [(boolean? v) (if v "true" "false")]
    [(real? v) (~a v)]
    [else (error 'jsexpr->python-json "unsupported value: ~a" v)]))


(define (json-escape s)
  (string-append "\""
                 (string-append*
                  (for/list ([c (in-string s)])
                    (cond
                      [(eqv? c #\") "\\\""]
                      [(eqv? c #\\) "\\\\"]
                      [(eqv? c #\newline) "\\n"]
                      [(eqv? c #\return) "\\r"]
                      [(eqv? c #\tab) "\\t"]
                      [(< (char->integer c) 32) (format "\\u~a" (~r (char->integer c) #:min-width 4 #:pad-string "0" #:base 16))]
                      [else (string c)])))
                 "\""))

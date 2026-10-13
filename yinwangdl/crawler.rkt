#lang racket/base

;; Yin Wang blog crawler — port of scripts/crawler.py. Fetches the post
;; list from yinwang.org with pagination, downloads new/updated posts as
;; formatted Markdown plus their images, and maintains index.json
;; byte-compatibly with the historical Python serializer (2-space indent,
;; insertion order, no trailing newline) so no-op crawls stay diff-free.

(require racket/path
         net/http-easy
         net/uri-codec
         json
         racket/string
         racket/list
         racket/file
         racket/format
         racket/match
         "util.rkt"
         "format.rkt"
         "frontmatter.rkt")

(provide crawl crawl-command)

(define user-agent "Mozilla/5.0 (compatible; yinwangdl-crawler/2.0)")
(define crawl-delay 1.0)             ; seconds between requests
(define image-delay 0.5)

(define timeouts (make-timeout-config #:lease 5 #:connect 30 #:request 120))

;; JSON null -> 'null; missing keys keep their default.
(define (jval v [default 'null])
  (if (eq? v 'null) default v))

;; string-typed json value (null/missing -> default)
(define (jstr v [default ""])
  (cond [(eq? v 'null) default]
        [(not v) default]
        [(string? v) v]
        [default]))

;; ---- API ----

(define (api-get url)
  (get url
       #:headers (hasheq 'User-Agent user-agent)
       #:timeouts timeouts))

(define (fetch-all-slugs)
  (let loop ([skip 0] [acc '()])
    (define resp (api-get (format "~a/api/v1/posts?skip=~a&limit=20" base-url skip)))
    (unless (= (response-status-code resp) 200)
      (error 'fetch-all-slugs "API returned ~a" (response-status-code resp)))
    (define data (string->jsexpr (bytes->string/utf-8 (response-body resp))))
    (define posts (jref data 'posts))
    (define total (jref data 'total 0))
    (printf "  Fetched ~a posts (skip=~a, total=~a)\n" (length posts) skip total)
    (define acc2 (append acc posts))
    (cond
      [(or (>= (+ skip 20) total) (null? posts))
       ;; deduplicate by slug, keeping first occurrence
       (define seen (make-hash))
       (define unique
         (for/list ([p (in-list acc2)]
                    #:unless (hash-has-key? seen (jref p 'slug)))
           (hash-set! seen (jref p 'slug) #t)
           p))
       (printf "  Total unique posts: ~a\n" (length unique))
       unique]
      [else
       (sleep crawl-delay)
       (loop (+ skip 20) acc2)])))

(define (fetch-post slug)
  (with-handlers ([exn:fail?
                   (λ (e)
                     (printf "  ERROR fetching post '~a': ~a\n" slug (exn-message e))
                     #f)])
    (define resp
      (api-get (string-append base-url "/api/v1/posts/" (uri-encode slug))))
    (if (not (= (response-status-code resp) 200))
        (begin
          (printf "  ERROR fetching post '~a': HTTP ~a\n"
                  slug (response-status-code resp))
          #f)
        (string->jsexpr (bytes->string/utf-8 (response-body resp))))))

;; ---- images ----

(define (url-basename url)
  ;; basename of the URL path (query/fragment stripped)
  (define path
    (let* ([s (car (string-split url "?" #:trim? #f))]
           [s (car (string-split s "#" #:trim? #f))])
      s))
  (define parts (string-split path "/" #:trim? #f))
  (if (null? parts) "" (last parts)))

(define (download-image url dest-dir)
  (cond
    [(equal? url "") #f]
    [else
     (define full (if (string-prefix? url "/") (string-append base-url url) url))
     (define filename (url-basename full))
     (cond
       [(equal? filename "") #f]
       [else
        (define dest-path (build-path dest-dir filename))
        (cond
          [(file-exists? dest-path) filename]
          [else
           (with-handlers ([exn:fail?
                            (λ (e)
                              (printf "    WARNING: Failed to download image ~a: ~a\n"
                                      full (exn-message e))
                              #f)])
             (define resp (get full #:headers (hasheq 'User-Agent user-agent)
                               #:timeouts timeouts))
             (if (not (= (response-status-code resp) 200))
                 (begin
                   (printf "    WARNING: Failed to download image ~a: HTTP ~a\n"
                           full (response-status-code resp))
                   #f)
                 (begin
                   (make-directory* dest-dir)
                   (with-output-to-file dest-path
                     (λ () (write-bytes (response-body resp)))
                     #:exists 'replace)
                   (printf "    Downloaded image: ~a\n" filename)
                   filename)))])])]))

(define (extract-images content)
  (define urls
    (append
     (for/list ([m (in-list (regexp-match* (regexp "!\\[[^\\]]*\\]\\(([^)]+)\\)") content
                                           #:match-select values))])
       (cadr m))
     (for/list ([m (in-list (regexp-match* (regexp "<img[^>]*src=[\"']([^\"']+)[\"']") content
                                           #:match-select values))])
       (cadr m))))
  (filter (λ (u) (not (string-prefix? u "data:"))) urls))

(define (replace-image-paths content slug)
  (define c1
    (regexp-replace* (regexp "!\\[([^\\]]*)\\]\\(([^)]+)\\)") content
                     (λ (whole alt url)
                       (if (string-prefix? url "/")
                           (format "![~a](/images/~a/~a)" alt slug (url-basename url))
                           whole))))
  (regexp-replace* (regexp "(<img[^>]*)(src=[\"'])([^\"']+)([\"'][^>]*>)") c1
                   (λ (whole prefix srcattr url suffix)
                     (if (string-prefix? url "/")
                         (string-append prefix srcattr
                                        "/images/" slug "/" (url-basename url)
                                        suffix)
                         whole))))

(define (download-post-images slug content root)
  (define failures '())
  (for ([url (in-list (extract-images content))])
    (define full-url
      (cond [(string-prefix? url "/") (string-append base-url url)]
            [(string-prefix? url "http") url]
            [else #f]))
    (when full-url
      (define result (download-image full-url (build-path (images-dir root) slug)))
      (when (and (not result) (not (string-prefix? url "/images/")))
        (set! failures (cons url failures)))
      (sleep image-delay)))
  (reverse failures))

;; ---- post files ----

(define (save-post post content root)
  (define slug (hash-ref post 'slug))
  (define title
    (let ([t (jstr (jref post 'title 'null))])
      (if (equal? t "") slug t)))
  (define frontmatter
    (generate-frontmatter title slug "王垠"
                          (jstr (jref post 'publish_date 'null))
                          (jstr (hash-ref post 'updated_at 'null))
                          (format "~a/posts/~a" base-url slug)))
  (define formatted (format-content content))
  (define body (string-append "# " title "\n\n" (replace-image-paths formatted slug)))
  (define filepath (build-path (posts-dir root) (string-append (sanitize-filename slug) ".md")))
  (write-utf8! filepath (string-append frontmatter body))
  (printf "  Saved: ~a\n" (path->string (file-name-from-path filepath))))

;; ---- dedup + index ----

;; source URL -> file path, from the existing posts directory
(define (build-source-index root)
  (define idx (make-hash))
  (define dir (posts-dir root))
  (when (directory-exists? dir)
    (for ([f (in-list (directory-list dir #:build? #t))]
          #:when (string-suffix? (path->string f) ".md"))
      (define m (regexp-match (string-append "(?m:^source:[" ws-line-chars "]*(.+)$)") (file->string f #:mode 'text)))
      (when m
        (hash-set! idx (string-trim (cadr m)) f))))
  idx)

;; Read index.json as an ordered assoc list ((slug . entry-fields) ...)
;; where entry-fields is an assoc list in the canonical key order
;; title/slug/publish_date/updated_at/tags/has_images.
(define index-entry-keys '(title slug publish_date updated_at tags has_images))

(define (load-index root)
  (define f (index-file root))
  (cond
    [(not (file-exists? f)) '()]
    [else
     (define text (file->string f #:mode 'text))
     (define data (string->jsexpr text))
     (define posts (jref data 'posts (hasheq)))
     (define order
       (regexp-match* (regexp "(?m:^    \"([^\"]+)\": \\{)") text
                      #:match-select cadr))
     (for/list ([slug (in-list order)])
       (cons slug (entry->assoc (jref posts slug (hasheq)))))]))

(define (entry->assoc entry)
  (for/list ([k (in-list index-entry-keys)])
    (cons k (hash-ref entry k 'null))))

(define (assoc-set assoc key value)
  (define found? #f)
  (define updated
    (for/list ([kv (in-list assoc)])
      (if (equal? (car kv) key)
          (begin (set! found? #t) (cons key value))
          kv)))
  (if found? updated (append assoc (list (cons key value)))))

(define (save-index! entries root)
  (define doc
    (json-obj (list (cons "posts"
                          (json-obj
                           (for/list ([kv (in-list entries)])
                             (cons (car kv) (json-obj (cdr kv)))))))))
  (write-utf8! (index-file root) (jsexpr->python-json doc)))

;; ---- crawl ----

(struct crawl-state (entries new-count updated-count skip-count failures))

(define (crawl #:force [force? #f] #:root [root (current-directory)])
  (printf "Fetching post list from API...\n")
  (define all-posts (fetch-all-slugs))
  (define source-index (build-source-index root))
  (define total (length all-posts))

  (define final-state
    (for/fold ([st (crawl-state (load-index root) 0 0 0 '())])
              ([post-meta (in-list all-posts)] [i (in-naturals)])
      (define slug (jref post-meta 'slug))
      (define source-url (format "~a/posts/~a" base-url slug))
      (define updated-at (jval (jref post-meta 'updated_at 'null)))
      (define existing
        (for/first ([kv (in-list (crawl-state-entries st))]
                    #:when (equal? (car kv) slug))
          (cdr kv)))

      (cond
        ;; incremental skip: file exists and updated_at unchanged
        [(and (not force?)
              (hash-has-key? source-index source-url)
              existing
              (equal? (cdr (assq 'updated_at existing)) updated-at))
         (crawl-state (crawl-state-entries st)
                      (crawl-state-new-count st)
                      (crawl-state-updated-count st)
                      (+ (crawl-state-skip-count st) 1)
                      (crawl-state-failures st))]

        [else
         (printf "[~a/~a] Processing: ~a\n" (+ i 1) total slug)
         (define post (fetch-post slug))
         (cond
           [(or (not post)
                (equal? (jstr (jref post 'content 'null)) ""))
            (printf "  Skipping (no content)\n")
            st]
           [else
            (define content (jref post 'content))
            (define failures (download-post-images slug content root))
            (save-post post content root)
            (define entry
              (list (cons 'title (jstr (jref post 'title 'null)))
                    (cons 'slug slug)
                    (cons 'publish_date (jstr (jref post 'publish_date 'null)))
                    (cons 'updated_at updated-at)
                    (cons 'tags (jval (jref post 'tags 'null) '()))
                    (cons 'has_images (not (null? (extract-images content))))))
            (sleep crawl-delay)
            (crawl-state (assoc-set (crawl-state-entries st) slug entry)
                         (if existing
                             (crawl-state-new-count st)
                             (+ (crawl-state-new-count st) 1))
                         (if existing
                             (+ (crawl-state-updated-count st) 1)
                             (crawl-state-updated-count st))
                         (crawl-state-skip-count st)
                         (append (crawl-state-failures st) failures))])])))

  (save-index! (crawl-state-entries final-state) root)
  (printf "\nDone! New: ~a, Updated: ~a, Skipped: ~a\n"
          (crawl-state-new-count final-state)
          (crawl-state-updated-count final-state)
          (crawl-state-skip-count final-state))
  (define failures (crawl-state-failures final-state))
  (unless (null? failures)
    (printf "Image download failures: ~a\n" (length failures))
    (for ([f (in-list failures)]) (printf "  - ~a\n" f)))
  0)

;; ---- CLI ----

(define (crawl-command [root (current-directory)] [force? #f])
  (crawl #:force force? #:root root))

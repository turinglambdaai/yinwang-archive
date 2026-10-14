#lang racket/base

;; Static site builder — replaces the Eleventy build (npm run build).
;; Output layout matches the historical dist/: /posts/{slug}/ pages,
;; paginated home (50/page), feed.xml, search.json, sitemap.xml,
;; llms.txt, plus copied assets from src/site and images/.

(require racket/path
         racket/string
         racket/list
         racket/file
         racket/format
         racket/match
         racket/dict
         file/sha1
         "util.rkt"
         "frontmatter.rkt"
         "render.rkt"
         "site.rkt")

(provide build-site
         load-posts
         page-size)

(define page-size 50)

;; Load and render every post; returns assoc lists sorted by created
;; date descending (ties keep path order). Keys:
;; title slug author created updated source html url
(define (load-posts root)
  (define dir (posts-dir root))
  (define files
    (sort
     (filter (λ (p) (string-suffix? (path->string p) ".md"))
             (directory-list dir #:build? #t))
     path<?))
  (define posts
    (for/list ([f (in-list files)])
      (define text (file->string f #:mode 'text))
      (define fm (parse-frontmatter text))
      (define body (frontmatter-body text))
      (define stem
        (path->string (path-replace-extension (file-name-from-path f) #"")))
      (and fm
           (list (cons 'title (dict-ref fm 'title ""))
                 (cons 'slug (dict-ref fm 'slug stem))
                 (cons 'author (dict-ref fm 'author ""))
                 (cons 'created (dict-ref fm 'created #f))
                 (cons 'updated (dict-ref fm 'updated #f))
                 (cons 'source (dict-ref fm 'source #f))
                 (cons 'html (render-body body))
                 (cons 'url (string-append "/posts/" stem "/"))))))
  (define clean (filter values posts))
  ;; stable: sort by path already applied; now created desc
  (sort clean
        (λ (a b)
          (compare-created (dict-ref a 'created #f) (dict-ref b 'created #f)))))

;; newest first; missing dates sink to the bottom deterministically
(define (compare-created a b)
  (cond
    [(equal? a b) #f]
    [(not a) #f]
    [(not b) #t]
    [else (string>? a b)]))

(define (write-page! out url-rel html)
  ;; "/posts/x/" -> out/posts/x/index.html; "/" -> out/index.html
  (define dir-rel
    (let ([s (substring url-rel 1)])
      (if (string-suffix? s "/") (substring s 0 (- (string-length s) 1)) s)))
  (define path
    (if (equal? dir-rel "")
        (build-path out "index.html")
        (build-path out (string->path dir-rel) "index.html")))
  (make-directory* (path-only path))
  (write-utf8! path html))

(define (build-site #:root [root (current-directory)]
                    #:out [out (build-path root "dist")])
  (when (directory-exists? out)
    (delete-directory/files out))
  (make-directory* out)
  (define posts (load-posts root))

  ;; cache-bust the stylesheet URL by its content hash
  (define css-file (build-path (site-src-dir root) "styles" "main.css"))
  (define css-hash
    (substring (sha1 (open-input-bytes (file->bytes css-file))) 0 10))

  (parameterize ([css-version css-hash])
    ;; paginated home
    (define total-pages (max 1 (ceiling (/ (length posts) page-size))))
    (for ([page (in-range total-pages)])
      (define slice
        (list-tail posts
                   (min (* page page-size) (length posts))))
      (define slice-50 (take slice (min page-size (length slice))))
      (write-page! out (page-url page)
                   (index-page slice-50 page total-pages)))

    ;; post pages with older/newer neighbours
    (for ([i (in-naturals)] [p (in-list posts)])
      (define older (if (< (+ i 1) (length posts)) (list-ref posts (+ i 1)) #f))
      (define newer (if (> i 0) (list-ref posts (- i 1)) #f))
      (write-page! out (dict-ref p 'url) (post-page p older newer)))

    ;; wechat page (公众号专页)
    (write-page! out "/wechat/" (wechat-page))

    ;; metadata outputs
    (write-utf8! (build-path out "feed.xml") (feed-xml posts))
    (write-utf8! (build-path out "search.json") (search-json posts))
    (write-utf8! (build-path out "sitemap.xml") (sitemap-xml posts total-pages))
    (write-utf8! (build-path out "llms.txt") (llms-txt posts))

    (printf "Wrote ~a posts (~a pages) to ~a\n"
            (length posts) total-pages out))

  ;; assets
  (define src (site-src-dir root))
  (for ([item (in-list '("favicon.svg" "robots.txt" "CNAME" "wechat-qr.jpg"))])
    (define f (build-path src item))
    (when (file-exists? f)
      (copy-file f (build-path out item) #t)))
  (for ([dir (in-list '("styles" "vendor"))])
    (define d (build-path src dir))
    (when (directory-exists? d)
      (copy-directory/files d (build-path out dir))))
  (define images (images-dir root))
  (when (directory-exists? images)
    (copy-directory/files images (build-path out "images")))
  0)

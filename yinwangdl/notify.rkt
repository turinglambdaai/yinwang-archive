#lang racket/base

;; Notify the site owner by email about newly crawled posts — port of
;; scripts/notify_new_posts.py. New = untracked in git (just crawled,
;; not yet committed). Delivery goes through curl's SMTP client because
;; Racket's net/smtp lacks STARTTLS (required by smtp.qq.com et al).
;; Configure via SMTP_HOST / SMTP_USER / SMTP_PASS / NOTIFY_TO; any
;; missing variable means a dry run.

(require racket/path
         racket/dict
         racket/system
         racket/string
         racket/list
         racket/file
         racket/port
         racket/match
         net/base64
         "util.rkt"
         "frontmatter.rkt")

(provide notify-command
         new-post-files)

(define site-base "https://yinwang.jrtx.site")

(define (git-path)
  (or (find-executable-path "git")
      (error 'notify "git not found")))

;; posts/*.md files that are untracked in the repo, sorted by path
(define (new-post-files root)
  (define-values (sp stdout stdin stderr)
    (subprocess #f #f #f (git-path) "-C" (path->string root)
                "ls-files" "--others" "--exclude-standard" "posts"))
  (define out (port->string stdout))
  (subprocess-wait sp)
  (close-input-port stdout)
  (close-input-port stderr)
  (sort
   (for/list ([rel (in-list (string-split out "\n" #:trim? #f))]
              #:when (string-suffix? rel ".md"))
     (build-path root (string->path rel)))
   path<?))

(define (post-info path)
  (define fm (parse-frontmatter (file->string path #:mode 'text)))
  (define title (if fm (dict-ref fm 'title #f) #f))
  (define slug (if fm (dict-ref fm 'slug #f) #f))
  (values (or title (path->string (file-name-from-path path)))
          (or slug (path->string (file-name-from-path path)))))

;; RFC 2047 encoded-word for the subject (python Header(..., "utf-8"))
(define (rfc2047-subject s)
  (format "=?utf-8?B?~a?="
          (bytes->string/latin-1
           (base64-encode (string->bytes/utf-8 s) ""))))

(define (build-message subject from to body)
  ;; MIMEText(body, "plain", "utf-8") parity: base64-encoded body,
  ;; wrapped at 76 columns (base64-encode does this)
  (string-append
   "From: yinwangdl <" from ">\r\n"
   "To: " to "\r\n"
   "Subject: " (rfc2047-subject subject) "\r\n"
   "MIME-Version: 1.0\r\n"
   "Content-Type: text/plain; charset=utf-8\r\n"
   "Content-Transfer-Encoding: base64\r\n"
   "\r\n"
   (bytes->string/latin-1 (base64-encode (string->bytes/utf-8 body) "\r\n"))))

(define (send-via-curl host user password to message)
  (define tmp (make-temporary-file "yinwangdl-notify~a"))
  (write-utf8! tmp message)
  (dynamic-wind
    (λ () (void))
    (λ ()
      (system*/exit-code
       (or (find-executable-path "curl") (error 'notify "curl not found"))
       "-sS" "--max-time" "30"
       "--url" (format "smtp://~a:587" host)
       "--ssl-reqd"
       "--mail-from" user
       "--mail-rcpt" to
       "--user" (string-append user ":" password)
       "--upload-file" (path->string tmp)))
    (λ () (when (file-exists? tmp) (delete-file tmp)))))

(define (notify-command [root (current-directory)])
  (define files (new-post-files root))
  (cond
    [(null? files)
     (printf "no new posts\n")
     0]
    [else
     (define infos
       (for/list ([f (in-list files)] [i (in-naturals)])
         (define-values (title slug) (post-info f))
         (cons i (cons title slug))))
     (define body
       (string-append
        (format "本周爬取新增 ~a 篇文章：\n\n" (length files))
        (string-append*
         (for/list ([info (in-list infos)])
           (format "~a. ~a\n   ~a/posts/~a/\n"
                   (+ (car info) 1)
                   (cadr info)
                   site-base
                   (cddr info))))))
     (display body)
     (define host (string-trim (or (getenv "SMTP_HOST") "")))
     (define user (string-trim (or (getenv "SMTP_USER") "")))
     (define password (string-trim (or (getenv "SMTP_PASS") "")))
     (define to (string-trim (or (getenv "NOTIFY_TO") "")))
     (cond
       [(or (equal? host "") (equal? user "") (equal? password "") (equal? to ""))
        (printf "(dry-run: set SMTP_HOST/SMTP_USER/SMTP_PASS/NOTIFY_TO to deliver)\n")
        0]
       [else
        (define message
          (build-message (format "王垠博客归档站：新增 ~a 篇文章" (length files))
                         user to body))
        (send-via-curl host user password to message)
        (printf "\nmail sent to ~a\n" to)
        0])]))

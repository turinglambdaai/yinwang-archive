#lang racket/base

;; Tests for page templates: footer links, the wechat page, sitemap.

(require rackunit
         racket/string
         "../site.rkt"
         "../util.rkt")

(define post
  (list (cons 'title "测试文章")
        (cons 'slug "test")
        (cons 'author "王垠")
        (cons 'created "2026-01-01")
        (cons 'updated #f)
        (cons 'source "https://www.yinwang.org/posts/test")
        (cons 'html "<p>正文</p>")
        (cons 'url "/posts/test/")))

(test-case "footer links to the wechat page, no takedown channel"
  (define html (post-page post #f #f))
  (check-true (string-contains? html "<a href=\"/wechat/\">"))
  (check-true (string-contains? html "公众号 TuringLambdaAI</a>"))
  (check-false (string-contains? html "删除请求"))
  (check-false (string-contains? html "yinwangdl/issues")))

(test-case "posts stay clean: no funnel elements inside the article"
  (define html (post-page post #f #f))
  (check-false (string-contains? html "follow-card"))
  (check-false (string-contains? html "wechat-qr.jpg")))

(test-case "ads are fully removed from every page"
  (for ([html (in-list (list (post-page post #f #f) (wechat-page)))])
    (check-false (string-contains? html "adsbygoogle"))
    (check-false (string-contains? html "google-adsense-account"))
    (check-false (string-contains? html "ad-sidebar"))
    (check-false (string-contains? html "ad-mobile"))))

(test-case "wechat page shows qr and account name"
  (define html (wechat-page))
  (check-true (string-contains? html "TuringLambdaAI"))
  (check-true (string-contains? html "src=\"/wechat-qr.jpg\""))
  (check-true
   (string-contains? html
                     (format "canonical\" href=\"~a/wechat/\"" site-base-url))))

(test-case "sitemap includes the wechat page"
  (check-true
   (string-contains? (sitemap-xml (list post) 1)
                     (format "<loc>~a/wechat/</loc>" site-base-url))))

#lang info

(define collection "yinwang-archive")
(define version "1.0.0")
(define deps '("base" "markdown" "http-easy"))
(define build-deps '("base" "rackunit-lib"))
(define pkg-desc "Wang Yin blog archive: crawl, lint, build the static site")
(define pkg-authors '(turinglambdaai))
(define raco-commands
  '(("yinwang-archive" yinwang-archive/raco-yinwang-archive
     "blog archive pipeline: crawl / lint / fix-bold / normalize-code / build / notify" #f)))
(define test-omit-paths '("raco-yinwang-archive.rkt"))

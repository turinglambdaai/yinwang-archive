#lang info

(define collection "yinwangdl")
(define version "1.0.0")
(define deps '("base" "markdown" "http-easy"))
(define build-deps '("base" "rackunit-lib"))
(define pkg-desc "Wang Yin blog archive: crawl, lint, build the static site")
(define pkg-authors '(turinglambdaai))
(define raco-commands
  '(("yinwangdl" yinwangdl/raco-yinwangdl
     "blog archive pipeline: crawl / lint / fix-bold / normalize-code / build / notify" #f)))
(define test-omit-paths '("raco-yinwangdl.rkt"))

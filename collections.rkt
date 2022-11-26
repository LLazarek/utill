#lang racket/base

(provide require->file-path)

(define (require->file-path quoted-require-path)
  ((current-module-name-resolver)
   quoted-require-path
   #f
   #f
   #f))

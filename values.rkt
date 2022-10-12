#lang racket

(provide pick-values)

(require syntax/parse/define)

(define-simple-macro (pick-values e picker)
  (call-with-values (thunk e)
                    (compose1 picker list)))

#lang racket/base

(require scribble/reader
         readline/readline
         syntax/parse/define)

(provide (rename-out [use-at-readtable enable-at-exp!])
         make-repl)

(define-simple-macro (make-repl
                      prompt
                      #:input input-name
                      #:loop
                      ([loop-pat loop-body ...] ...)
                      #:exit
                      ([exit-pat exit-body ...] ...))
  (let loop ()
    (display prompt)
    (flush-output)
    (define input-name (readline prompt))
    (when (and (string? input-name)
               (not (string-prefix? input-name " ")))
      (add-history input-name))
    (match (string-trim input-name #:right? #f)
      [(regexp "^h(elp)?")
       (displayln "Available commands:")
       (displayln (list loop-pat ... exit-pat ...))
       (loop)]
      [loop-pat
       loop-body ...
       (loop)]
      ...
      [exit-pat
       exit-body ...]
      ...
      [(? eof-object?) (void)]
      [else
       (printf "Unknown command: ~a\n" input-name)
       (loop)])))

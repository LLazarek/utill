#lang at-exp racket

(provide clone-repo!
         add!
         checkout-last-commit-before
         commit!
         push!
         commit-and-push!
         get-head-commit-sha
         get-status
         get-current-branch
         sha?
         checkout!)

(require "files.rkt")

(define-logger git)

(define (sha? str)
  (and (string? str)
       (= (string-length str) 40)
       (regexp-match? #rx"^[a-z0-9]+$" str)))

;; Returns either zero, one, or two values, depending on #:status? and #:output?:
;; if both are true, returns both the exit status and output in that order
;; if either is true and the other is false, returns just the one that's true
;; if neither are true, returns void
(define (git cmd
             #:in [repo-dir (current-directory)]
             #:output? [output? #t]
             #:status? [status? #f])
  (define outstr (open-output-string))
  (parameterize ([current-directory   repo-dir]
                 [current-output-port outstr]
                 [current-error-port  outstr])
    (define status (system (~a "git " cmd)))
    (cond [(and status? output?)
           (values status (get-output-string outstr))]
          [status? status]
          [output? (get-output-string outstr)]
          [else (void)])))

(define/contract (clone-repo! repo-url destination-dir)
  (string? string? . -> . (or/c path-to-existant-directory? #f))

  (define-values {success? output}
    (git @~a{clone "@repo-url" "@destination-dir"}
              #:output? #t
              #:status? #t))
  (match success?
    [#t
     destination-dir]
    [#f
     (log-git-error @~a{
                    Failed to clone repo at @repo-url
                    Git output:
                    ----------
                    @output
                    ----------
                    })
     #f]))

(define/contract (add! repo-path paths)
  (path-to-existant-directory?
   (or/c (or/c path-to-existant-file? path-to-existant-directory?)
         (listof (or/c path-to-existant-file? path-to-existant-directory?)))
   . -> .
   any)

  (define path-strs (if (list? paths)
                        (string-join (map ~a paths))
                        paths))
  (define output (git @~a{add @path-strs}
                      #:in repo-path))
  (log-git-debug @~a{
                    git-add output:
                    -----
                    @output
                    -----
                    }))

(define/contract (get-current-branch repo-dir)
  (path-to-existant-directory? . -> . string?)
  (match (git "branch" #:in repo-dir)
    [(and (regexp #rx"(?m:^\\* .*HEAD detached.*$)") branch-output)
     (raise-user-error 'get-current-branch
                       @~a{
                           Couldn't get current branch of @repo-dir @;
                           because HEAD is detached.
                           Git says: @branch-output
                           })]
    [(regexp #rx"(?m:^\\* (.+?)$)" (list _ branch)) branch]
    [other (raise-user-error 'get-current-branch
                             @~a{
                                 Couldn't get current branch of @repo-dir
                                 Git says: @other
                                 })]))

(define/contract ((checkout-last-commit-before iso-date-deadline
                                               ; #f means default/current branch
                                               [branch #f])
                  repo-dir)
  ({string?}
   {(or/c #f string?)}
   . ->* .
   (path-to-existant-directory? . -> . any))

  (define branch-to-checkout (or branch
                                 (get-current-branch repo-dir)))
  (define pre-deadline-commit
    (string-trim
     (git @~a{rev-list --date=iso --reverse -n 1 --before='@iso-date-deadline' @branch-to-checkout}
          #:in repo-dir)))
  (log-git-info @~a{Checking out commit @pre-deadline-commit})
  (checkout! repo-dir pre-deadline-commit))

(define/contract (get-status repo-dir)
  (path-to-existant-directory? . -> . (or/c 'clean string?))
  (define status (git "status" #:in repo-dir))
  (if (regexp-match? #rx"nothing to commit, working tree clean" status)
      'clean
      status))

(define/contract (commit! repo-dir msg
                          #:add [paths-to-add empty])
  ({path-to-existant-directory? string?}
   {#:add (listof path-string?)}
   . ->* .
   any)

  (log-git-debug @~a{git-adding @paths-to-add})
  (add! repo-dir paths-to-add)
  (log-git-debug @~a{Committing ...})
  (define-values {success? commit-output}
    (git @~a{commit -m "@msg"}
         #:in repo-dir
         #:status? #t
         #:output? #t))
  (if (or success?
          ;; git gives non-0 exit code in this case, but don't consider it a failure
          (regexp-match? #px"^On branch.*?\nnothing to commit, working tree clean\\s*$"
                         commit-output))
      (log-git-debug @~a{
                        git commit output
                        -----
                        @commit-output
                        -----
                        })
      (raise-user-error
       'git:commit!
       @~a{
           git commit in repo @repo-dir failed with output
           -----
           @commit-output
           -----
           })))

(define/contract (push! repo-dir
                        #:remote [remote "origin"]
                        #:branch [branch "master"])
  ({path-to-existant-directory?}
   {#:remote string?
    #:branch string?}
   . ->* .
   any)

  (define-values {success? push-output}
    (git @~a{push @remote @branch}
         #:in repo-dir
         #:status? #t
         #:output? #t))
  (if success?
      (log-git-debug @~a{
                        git push @remote @branch output
                        -----
                        @push-output
                        -----
                        })
      (raise-user-error
       'git:push!
       @~a{
           git push @remote @branch in @repo-dir failed with output
           -----
           @push-output
           -----
           })))

(define/contract (commit-and-push! repo-dir msg
                                   #:remote [remote "origin"]
                                   #:branch [branch "master"]
                                   #:add [paths-to-add empty])
  ({path-to-existant-directory? string?}
   {#:remote string?
    #:branch string?
    #:add (listof path-string?)}
   . ->* .
   any)

  (commit! repo-dir
           msg
           #:add paths-to-add)
  (push! repo-dir
         #:remote remote
         #:branch branch))

(define (get-head-commit-sha [repo-dir (current-directory)]
                             #:short? [short? #f])
  (string-trim (git @~a{rev-parse @(if short? "--short" "") HEAD}
                    #:in repo-dir)))

(define (checkout! repo-dir ref)
  (log-git-debug @~a{git: checking out @ref})
  (git @~a{checkout @ref > /dev/null 2>&1}
       #:in repo-dir))
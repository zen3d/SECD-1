(define (cdddr lst) (cdr (cddr lst)))

(define (self-print-env env)
  (letrec ((print-frame
    (lambda (syms vals)
      (if (null? syms)
        (if (null? vals) '()
          (begin (display "\n;; Error: trailing vals\n") (display vals) (newline)))
        (if (null? vals)
          (begin
            (display "\n;; Error: no vals\n") (display syms) '())
          (begin
            (display "\n;;  ") (display (car syms)) (display "  -> ") (display (car vals))
            (print-frame (cdr syms) (cdr vals))))))))
    (if (null? env) '()
      (let ((frame (car env)))
        (if (null? frame)
          (begin
            (display "\n;; Error: null frame\n") '())
          (begin
            (display "\n;; Frame\n")
            (if (vector? frame)
                (begin
                  (display "\n;;   ###")
                  (let ((f (vector-ref frame 0)))
                    (print-frame (car f) (cdr f))))
                (print-frame (car frame) (cdr frame)))
            (self-print-env (cdr env))))))))

(define (self-lookup-env env sym)
  (if (null? env)
    ;; access to the Scheme env:
    (if (defined? sym) (eval sym (interaction-environment)) '())
    (let ((frame (let ((f (car env)))
                   (if (vector? f)  (vector-ref f 0) f)))
          (envrest (cdr env)))
      (if (pair? frame)
        (letrec ((lookup-frame
            (lambda (syms vals)
              (if (null? syms) '()
                (if (eq? (car syms) sym)
                    (list (car vals))
                    (lookup-frame (cdr syms) (cdr vals)))))))
          (if (eq? (length (car frame)) (length (cdr frame)))
            (let ((res (lookup-frame (car frame) (cdr frame))))
              (if (null? res)
                  (self-lookup-env envrest sym)
                  res))
            (begin
                (display "\nError:_args") (newline)
                (self-print-env env)
                '())))
        ;; it's an omega-frame, skipping:
        (self-lookup-env envrest sym)))))

(define (self-eval-step s e c d)
  (let ((cmd (car c)) (c1 (cdr c)))
    (begin
      ;(display "\n\n  s = ") (display s)
      ;(display "\n  e = ") (display e)
      ;(display "\n  c = ") (display c)
      ;(display "\n  d = ") (display d)
      (cond
        ((eq? cmd 'LDC)
          (let ((cn (car c1)) (c2 (cdr c1)))
            (self-eval-step (cons cn s) e c2 d)))
        ((eq? cmd 'ADD)
          (let ((v1 (car s)) (v2 (cadr s)) (s2 (cddr s)))
            (self-eval-step (cons (+ v1 v2) s2) e c1 d)))
        ((eq? cmd 'SUB)
          (let ((v1 (car s)) (v2 (cadr s)) (s2 (cddr s)))
            (self-eval-step (cons (- v1 v2) s2) e c1 d)))
        ((eq? cmd 'MUL)
          (let ((v1 (car s)) (v2 (cadr s)) (s2 (cddr s)))
            (self-eval-step (cons (* v1 v2) s2) e c1 d)))

        ((eq? cmd 'CONS)
          (let ((v1 (car s)) (v2 (cadr s)) (s2 (cddr s)))
            (self-eval-step (cons (cons v1 v2) s2) e c1 d)))
        ((eq? cmd 'CAR)
          (let ((v (car s)) (s1 (cdr s)))
            (self-eval-step (cons (car v) s1) e c1 d)))
        ((eq? cmd 'CDR)
          (let ((v (car s)) (s1 (cdr s)))
            (if (null? v)
              'Error:_cdr_nil
              (self-eval-step (cons (cdr v) s1) e c1 d))))

        ((eq? cmd 'LEQ)
          (let ((v1 (car s)) (v2 (cadr s)) (s2 (cddr s)))
            (self-eval-step (cons (<= v1 v2) s2) e c1 d)))
        ((eq? cmd 'TYPE)
          (let ((v (car s)) (s1 (cdr s)))
            (self-eval-step (cons (secd-type v) s1) e c1 d)))
        ((eq? cmd 'EQ)
          (let ((v1 (car s)) (v2 (cadr s)) (s2 (cddr s)))
            (self-eval-step (cons (eq? v1 v2) s2) e c1 d)))

        ((eq? cmd 'SEL)
          (let ((v (car s)) (s1 (cdr s))
                (thenb (car c1)) (elseb (cadr c1)) (c2 (cddr c1)))
            (self-eval-step s1 e (if v thenb elseb) (cons c2 d))))
        ((eq? cmd 'JOIN)
          (let ((c1 (car d)) (d1 (cdr d)))
            (self-eval-step s e c1 d1)))

        ((eq? cmd 'LD)
          (let ((cn (car c1)) (c2 (cdr c1)))
            (let ((v (self-lookup-env e cn)))
              (if (null? v)
                (list 'Error:_lookup_failed_for cn)
                (self-eval-step (cons (car v) s) e c2 d)))))
        ((eq? cmd 'LDF)
          (let ((func (car c1)) (c2 (cdr c1)))
            (let ((clos (cons func e)))
              (self-eval-step (cons clos s) e c2 d))))
        ((eq? cmd 'AP)
          (let ((clos (car s)) (argvals (cadr s)) (s2 (cddr s)))
            (let ((func (car clos)) (e1 (cdr clos)))
              (let ((args (car func)) (body (cadr func)))
                (let ((d1 (append (list s2 e c1) d)))
                  (begin
                    ;(display "\n; argnames: ") (display args)
                    ;(display "\n; argvals : ") (display argvals) (newline)
                    ;(self-print-env e1)
                    (self-eval-step '() (cons (cons args argvals) e1) body d1)))))))
        ((eq? cmd 'RTN)
          (let ((v (car s))
                (s1 (car d)) (e1 (cadr d)) (c1 (caddr d)) (d1 (cdddr d)))
            (self-eval-step (cons v s1) e1 c1 d1)))

        ((eq? cmd 'READ)
          (let ((inp (read)))
            (self-eval-step (cons inp s) e c1 d)))
        ((eq? cmd 'PRINT)
          (begin
            (display (car s))
            (self-eval-step s e c d)))

        ((eq? cmd 'DUM)
            (self-eval-step s (cons (make-vector 1 0) e) c1 d))
        ((eq? cmd 'RAP)
          (let ((clos (car s)) (argvals (cadr s)) (s2 (cddr s)))
            (let ((func (car clos)) (e1 (cdr clos)))
              (let ((args (car func)) (body (cadr func)))
                (let ((frame (cons args argvals))
                      (d1 (append (list s2 (cdr e1) c1) d)))
                  (begin
                    ;(display "\n; RAP argnames: ") (display args)
                    ;(display "\n; RAP  argvals: ") (display argvals)
                    (vector-set! (car e1) 0 frame)
                    (self-eval-step '() e1 body d1)))))))

        ((eq? cmd 'STOP)
          (car s))
        (else
          (list 'Error:_unknown_command cmd))
      ))))

(define (self-eval-secd ctrl)
  (self-eval-step '() '() ctrl '()))

(define (self-eval expr)
  (self-eval-secd (append (secd-compile expr) '(STOP))))

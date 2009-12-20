;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: C -*-
;;;;
;;;;  Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
;;;;  Copyright (c) 1990, Giuseppe Attardi.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.

;;;; CMPTYPE  Type information.

(in-package "COMPILER")

;;; CL-TYPE is any valid type specification of Common Lisp.
;;;
;;; TYPE is a representation type used by ECL.  TYPE is one of:
;;;
;;;				T(BOOLEAN)
;;;
;;;	FIXNUM  CHARACTER  SINGLE-FLOAT  DOUBLE-FLOAT
;;;	(VECTOR T)  STRING  BIT-VECTOR  (VECTOR FIXNUM)
;;;	(VECTOR SINGLE-FLOAT)  (VECTOR DOUBLE-FLOAT)
;;;	(ARRAY T)  (ARRAY BASE-CHAR)  (ARRAY BIT)
;;;	(ARRAY FIXNUM)
;;;	(ARRAY SINGLE-FLOAT)  (ARRAY DOUBLE-FLOAT)
;;;	STANDARD-OBJECT STRUCTURE-OBJECT
;;;	SYMBOL
;;;	UNKNOWN
;;;
;;;				NIL
;;;
;;;
;;; immediate-type:
;;;	FIXNUM		int
;;;	CHARACTER	char
;;;	SINGLE-FLOAT	float
;;;	DOUBLE-FLOAT	double

(deftype any () 't)

(defun member-type (type disjoint-supertypes)
  (member type disjoint-supertypes :test #'subtypep))

(defun object-type (thing)
  (type-of thing))

(defun type-filter (type &optional values-allowed)
  (multiple-value-bind (type-name type-args) (sys::normalize-type type)
    (case type-name
        ((FIXNUM CHARACTER SINGLE-FLOAT DOUBLE-FLOAT SYMBOL) type-name)
        (SHORT-FLOAT #-short-float 'SINGLE-FLOAT #+short-float 'SHORT-FLOAT)
        (LONG-FLOAT #-long-float 'DOUBLE-FLOAT #+long-float 'LONG-FLOAT)
        ((SIMPLE-STRING STRING) 'STRING)
        ((SIMPLE-BIT-VECTOR BIT-VECTOR) 'BIT-VECTOR)
	((NIL T) t)
	((SIMPLE-ARRAY ARRAY)
	 (cond ((endp type-args) '(ARRAY *))		; Beppe
	       ((eq '* (car type-args)) t)
	       (t (let ((element-type (upgraded-array-element-type (car type-args)))
			(dimensions (if (cdr type-args) (second type-args) '*)))
		    (if (and (not (eq dimensions '*))
			     (or (numberp dimensions)
				 (= (length dimensions) 1)))
		      (case element-type
			(BASE-CHAR 'STRING)
			(BIT 'BIT-VECTOR)
			(t (list 'VECTOR element-type)))
		      (list 'ARRAY element-type))))))
	(INTEGER (if (subtypep type 'FIXNUM) 'FIXNUM t))
	((STREAM CONS) type-name) ; Juanjo
        (FUNCTION type-name)
	(t (cond ((eq type-name 'VALUES)
		  (unless values-allowed
		    (error "VALUES type found in a place where it is not allowed."))
		  `(VALUES ,@(mapcar #'(lambda (x)
					(if (or (eq x '&optional)
						(eq x '&rest))
					    x
					    (type-filter x)))
				    type-args)))
		 #+clos
		 ((subtypep type 'STANDARD-OBJECT) type)
		 #+clos
		 ((subtypep type 'STRUCTURE-OBJECT) type)
		 ((dolist (v '(FIXNUM CHARACTER SINGLE-FLOAT DOUBLE-FLOAT
                               #+short-float SHORT-FLOAT #+long-float LONG-FLOAT
			       (VECTOR T) STRING BIT-VECTOR
			       (VECTOR FIXNUM) (VECTOR SINGLE-FLOAT)
			       (VECTOR DOUBLE-FLOAT) (ARRAY BASE-CHAR)
			       (ARRAY BIT) (ARRAY FIXNUM)
			       (ARRAY SINGLE-FLOAT) (ARRAY DOUBLE-FLOAT)
			       (ARRAY T))) ; Beppe
		    (when (subtypep type v) (return v))))
		 ((and (eq type-name 'SATISFIES) ; Beppe
		       (symbolp (car type-args))
		       (get-sysprop (car type-args) 'TYPE-FILTER)))
		 (t t))))))

(defun valid-type-specifier (type)
  (handler-case
     (if (subtypep type 'T)
	 (values t (type-filter type))
         (values nil nil))
    (error (c) (values nil nil))))

(defun known-type-p (type)
  (subtypep type 'T))

(defun-equal-cached type-and (t1 t2)
  ;; FIXME! Should we allow "*" as type name???
  (when (or (eq t1 t2) (eq t2 '*))
    (return-from type-and t1))
  (when (eq t1 '*)
    (return-from type-and t2))
  (let* ((si::*highest-type-tag* si::*highest-type-tag*)
	 (si::*save-types-database* t)
	 (si::*member-types* si::*member-types*)
	 (si::*elementary-types* si::*elementary-types*)
	 (tag1 (si::safe-canonical-type t1))
	 (tag2 (si::safe-canonical-type t2)))
    (cond ((and (numberp tag1) (numberp tag2))
	   (setf tag1 (si::safe-canonical-type t1)
		 tag2 (si::safe-canonical-type t2))
	   (cond ((zerop (logand tag1 tag2)) ; '(AND t1 t2) = NIL
		  NIL)
		 ((zerop (logandc2 tag1 tag2)) ; t1 <= t2
		  t1)
		 ((zerop (logandc2 tag2 tag1)) ; t2 <= t1
		  t2)
		 (t
		  `(AND ,t1 ,t2))))
	  ((eq tag1 'CONS)
	   (cmpwarn "Unsupported CONS type ~S. Replacing it with T." t1)
	   t2)
	  ((eq tag2 'CONS)
	   (cmpwarn "Unsupported CONS type ~S. Replacing it with T." t2)
	   t1)
	  ((null tag1)
           (setf c::*compiler-break-enable* t)
           ;(error "foo")
	   (cmpwarn "Unknown type ~S. Assuming it is T." t1)
	   t2)
	  (t
           (setf c::*compiler-break-enable* t)
           ;(error "foo")
	   (cmpwarn "Unknown type ~S. Assuming it is T." t2)
	   t1))))

(defun-equal-cached values-type-primary-type (type)
  (when (and (consp type) (eq (first type) 'VALUES))
    (let ((subtype (second type)))
      (when (or (eq subtype '&optional) (eq subtype '&rest))
        (setf type (cddr type))
        (when (or (null type)
                  (eq (setf subtype (first type)) '&optional)
                  (eq subtype '&rest))
          (cmperr "Syntax error in type expression ~S" type))
        ;; An &optional or &rest output value might be missing
        ;; If this is the case, the the value will be NIL.
        (setf subtype (type-or 'null subtype)))
      (setf type subtype)))
  type)

(defun-equal-cached values-type-to-n-types (type length)
  (if (or (atom type) (not (eql (first type) 'values)))
      (list* type (make-list (1- length) :initial-element 'NULL))
      (do* ((l (rest type))
            (output '())
            (n length (1- n)))
           ((or (null l) (zerop n)) (nreverse output))
        (let ((type (pop l)))
          (case type
            (&optional
             (when (null l)
               (cmperr "Syntax error in type expression ~S" type))
             (setf type (pop l)))
            (&rest
             (when (null l)
               (cmperr "Syntax error in type expression ~S" type))
             (return-from values-type-to-n-types
               (nreconc output (make-list n :initial-element (first l))))))
          (push type output)))))

(defun split-values-type (type)
  (if (or (atom type) (not (eq (first type) 'VALUES)))
      (values (list type) nil nil)
      (let ((rest (member '&rest type))
            (opt (member '&optional type)))
        (values (ldiff (rest type) (or rest opt))
                (ldiff (rest (member '&optional type)) rest)
                (rest (member '&rest type))))))

(defun-equal-cached values-type-or (t1 t2)
  (when (or (eq t2 'T) (equalp t2 '(VALUES &REST T)))
    (return-from values-type-or t2))
  (when (or (eq t1 'T) (equalp t1 '(VALUES &REST T)))
    (return-from values-type-or t1))
  (unless t1
    (return-from values-type-or t2))
  (unless t2
    (return-from values-type-or t1))
  (multiple-value-bind (req1 opt1 rest1)
      (split-values-type t1)
    (multiple-value-bind (req2 opt2 rest2)
        (split-values-type t2)
      (let ((req '())
            (opt '())
            (rest '()))
        (loop for t1 in req1
           do (cond (req2
                     (push (type-or t1 (pop req2)) req))
                    (opt2
                     (push (type-or t1 (pop opt2)) opt))
                    (rest2
                     (push (type-or t1 (first rest2)) opt))
                    (t
                     (push t1 opt))))
        (loop for t1 in opt1
           do (cond (req2
                     (push (type-or t1 (pop req2)) opt))
                    (opt2
                     (push (type-or t1 (pop opt2)) opt))
                    (rest2
                     (push (type-or t1 (first rest2)) opt))
                    (t
                     (push t1 opt))))
        (let ((t1 (if rest1 (first rest1) t)))
          (loop for t2 in req2
             do (push (type-or t1 t2) opt))
          (loop for t2 in opt2
             do (push (type-or t1 t2) opt))
          (if rest2
              (setf rest (list (type-or t1 (first rest2))))
              (setf rest rest1)))
        `(VALUES ,@(nreverse req)
                 ,@(and opt (cons '&optional (nreverse opt)))
                 ,@(and rest (cons '&optional rest)))))))

(defun-equal-cached values-type-and (t1 t2)
  (when (or (eq t2 'T) (equalp t2 '(VALUES &REST T)))
    (return-from values-type-and t1))
  (when (or (eq t1 'T) (equalp t1 '(VALUES &REST T)))
    (return-from values-type-and t2))
  (when (or (null t1) (null t2))
    (return-from values-type-and nil))
  (multiple-value-bind (req1 opt1 rest1)
      (split-values-type t1)
    (multiple-value-bind (req2 opt2 rest2)
        (split-values-type t2)
      (let ((req '())
            (opt '())
            (rest '()))
        (loop for t1 in req1
           do (cond (req2 (push (type-and t1 (pop req2)) req))
                    (opt2 (push (type-and t1 (pop opt2)) req))
                    (rest2 (push (type-and t1 (first rest2)) req))
                    (t (setf opt1 nil rest1 nil) (return))))
        (loop for t1 in opt1
           do (cond (req2 (push (type-and t1 (pop req2)) req))
                    (opt2 (push (type-and t1 (pop opt2)) opt))
                    (rest2 (push (type-and t1 (first rest2)) opt))
                    (t (setf opt1 nil rest1 nil) (return))))
        (when rest
          (let ((t1 (first rest)))
            (loop for t2 in req2
               do (push (type-and t1 t2) req))
            (loop for t2 in opt2
               do (push (type-and t1 t2) opt))
            (when rest2
              (setf rest (list (type-and t1 (first rest2)))))))
        `(VALUES ,@(nreverse req)
                 ,@(and opt (cons '&optional (nreverse opt)))
                 ,@(and rest (cons '&optional rest)))))))

(defun-equal-cached type-or (t1 t2)
  ;; FIXME! Should we allow "*" as type name???
  (when (or (eq t1 t2) (eq t2 '*))
    (return-from type-or t1))
  (when (eq t1 '*)
    (return-from type-or t2))
  (let* ((si::*highest-type-tag* si::*highest-type-tag*)
	 (si::*save-types-database* t)
	 (si::*member-types* si::*member-types*)
	 (si::*elementary-types* si::*elementary-types*)
	 (tag1 (si::safe-canonical-type t1))
	 (tag2 (si::safe-canonical-type t2)))
    (cond ((and (numberp tag1) (numberp tag2))
	   (setf tag1 (si::safe-canonical-type t1)
		 tag2 (si::safe-canonical-type t2))
	   (cond ((zerop (logandc2 tag1 tag2)) ; t1 <= t2
		  t2)
		 ((zerop (logandc2 tag2 tag1)) ; t2 <= t1
		  t1)
		 (t
		  `(OR ,t1 ,t2))))
	  ((eq tag1 'CONS)
	   (cmpwarn "Unsupported CONS type ~S. Replacing it with T." t1)
	   T)
	  ((eq tag2 'CONS)
	   (cmpwarn "Unsupported CONS type ~S. Replacing it with T." t2)
	   T)
	  ((null tag1)
	   (cmpwarn "Unknown type ~S" t1)
	   T)
	  (t
	   (cmpwarn "Unknown type ~S" t2)
	   T))))

(defun type>= (type1 type2)
  (subtypep type2 type1))

;;;
;;; and-form-type
;;;   returns a copy of form whose type is the type-and of type and the form's
;;;   type
;;;
(defun and-form-type (type form original-form &optional (mode :safe)
		      (format-string "") &rest format-args)
  (let* ((type2 (c1form-or-loc-primary-type form))
	 (type1 (type-and type type2)))
    ;; We only change the type if it is not NIL. Is this wise?
    (if type1
	(setf (c1form-or-loc-values-type form) type1)
	(funcall (if (eq mode :safe) #'cmperr #'cmpwarn)
		 "~?, the type of the form ~s is ~s, not ~s." format-string
		 format-args original-form type2 type))
    form))

(defun default-init (var)
  (let ((new-value (cdr (assoc (var-type var)
			       '((fixnum . 0) (character . #\space)
                                 #+long-float (long-float 0.0L1)
				 (double-float . 0.0D1) (single-float . 0.0F1))
			       :test #'subtypep))))
    new-value))

(defun default-init-loc (var)
  (c1form-arg 0 (c1expr (default-init var))))

;;----------------------------------------------------------------------
;; (FUNCTION ...) types. This code is a continuation of predlib.lsp.
;; It implements function types and a SUBTYPEP relationship between them.
;;

(in-package "SI")

(defstruct function-type
  required
  optional
  rest
  key-p
  keywords
  keyword-types
  allow-other-keys-p
  output)

(defun canonical-function-type (ftype)
  (when (function-type-p ftype)
    (return-from canonical-function-type ftype))
  (flet ((ftype-error ()
	   (error "Syntax error in FUNCTION type definition ~S" ftype)))
    (let (o k k-t values)
      (unless (and (= (length ftype) 3) (eql (first ftype) 'FUNCTION))
	(ftype-error))
      (multiple-value-bind (requireds optionals rest key-flag keywords
				      allow-other-keys-p auxs)
	  (si::process-lambda-list (second ftype) 'FTYPE)
	(dotimes (i (pop optionals))
	  (let ((type (first optionals))
		(init (second optionals))
		(flag (third optionals)))
	    (setq optionals (cdddr optionals))
	    (when (or init flag) (ftype-error))
	    (push type o)))
	(dotimes (i (pop keywords))
	  (let ((keyword (first keywords))
		(var (second keywords))
		(type (third keywords))
		(flag (fourth keywords)))
	    (setq keywords (cddddr keywords))
	    (when (or var flag) (ftype-error))
	    (push keyword k)
	    (push type k-t)))
	(setf values (third ftype))
	(cond ((atom values) (setf values (list 'VALUES values)))
	      ((and (listp values) (eql (first values) 'VALUES)))
	      (t (ftype-error)))
	(when (and rest key-flag
		   (not (subtypep 'keyword rest)))
	  (ftype-error))
	(make-function-type :required (rest requireds)
			    :optional o
			    :rest rest
			    :key-p key-flag
			    :keywords k
			    :keyword-types k-t
			    :allow-other-keys-p allow-other-keys-p
			    :output (canonical-values-type values))))))

(defconstant +function-type-tag+ (cdr (assoc 'FUNCTION *elementary-types*)))

(defun register-function-type (type)
  (or (find-registered-tag type)
      (find-registered-tag (setq ftype (canonical-function-type type)))
      (let ((tag (register-type ftype #'function-type-p #'function-type-<=)))
	(update-types +function-type-tag+ tag)
	tag)))

(defun function-type-<= (f1 f2)
  (unless (and (every* #'subtypep
		       (function-type-required f2)
		       (function-type-required f1))
	       (do* ((o1 (function-type-optional f1) (cdr o1))
		     (o2 (function-type-optional f2) (cdr o2))
		     (r1 (function-type-rest f1))
		     (r2 (function-type-rest f2))
		     t1 t2)
		    ((and (endp o1) (endp o2)) t)
		 (setf t1 (cond ((consp o1) (first o1))
				(r1 r1)
				(t (return nil)))
		       t2 (cond ((consp o2) (first o2))
				(r2 r2)
				(t (return nil))))
		 (unless (subtypep t1 t2)
		   (return nil)))
	       (subtypep (function-type-output f1)
			 (function-type-output f2))
	       (eql (function-type-key-p f1) (function-type-key-p f2))
	       (or (function-type-allow-other-keys-p f2)
		   (not (function-type-allow-other-keys-p f1))))
    (return-from function-type-<= nil))
  (do* ((k2 (function-type-keywords f2))
	(k-t2 (function-type-keyword-types f2))
	(k1 (function-type-keywords f1) (cdr k1))
	(k-t1 (function-type-keyword-types f1) (cdr k1)))
       ((endp k1)
	t)
    (unless
	(let* ((n (position (first k1) k2)))
	  (when n
	    (let ((t2 (nth n k-t2)))
	      (subtypep (first k-t1) t2))))
      (return-from function-type-<= nil))))

;;----------------------------------------------------------------------
;; (VALUES ...) type

(defstruct values-type
  min-values
  max-values
  required
  optional
  rest)

(defun register-values-type (vtype)
  (or (find-registered-tag vtype)
      (find-registered-tag (setf vtype (canonical-values-type vtype)))
      (register-type vtype #'values-type-p #'values-type-<=)))

(defun canonical-values-type (vtype)
  (when (values-type-p vtype)
    (return-from canonical-values-type vtype))
  (flet ((vtype-error ()
	   (error "Syntax error in VALUES type definition ~S" vtype)))
    (unless (and (listp vtype) (eql (pop vtype) 'VALUES))
      (vtype-error))
    (let ((required '())
	  (optional '())
	  (rest nil))
      (do ()
	  ((endp vtype)
	   (make-values-type :min-values (length required)
			     :max-values (if rest multiple-values-limit
					     (+ (length required)
						(length optional)))
			     :required (nreverse required)
			     :optional (nreverse optional)
			     :rest rest))

	(let ((type (pop vtype)))
	  (if (eql type '&optional)
	      (do ()
		  ((endp vtype))
		(let ((type (pop vtype)))
		  (if (eql type '&rest)
		      (if (endp vtype)
			  (ftype-error)
			  (setf rest (first vtype)))
		      (push type optional))))
	      (push type required)))))))

(defun values-type-<= (v1 v2)
  (and (= (values-type-min-values v1) (values-type-min-values v2))
       (= (values-type-max-values v1) (values-type-max-values v2))
       (every* #'subtypep (values-type-required v1) (values-type-required v2))
       (every* #'subtypep (values-type-optional v1) (values-type-optional v2))
       (subtypep (values-type-rest v1) (values-type-rest v2))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; TYPE PROPAGATORS
;;;

(in-package "COMPILER")

(defun c1form-or-loc-primary-type (x)
  (cond ((c1form-p x)
	 (c1form-primary-type x))
	((var-p x)
	 (var-type x))
	(t
	 (loc-type x))))

(defun c1form-or-loc-values-type (x)
  (cond ((c1form-p x)
	 (c1form-values-type x))
	((var-p x)
	 (var-type x))
	(t
	 (loc-type x))))

(defun (setf c1form-or-loc-values-type) (v x)
  (cond ((c1form-p x)
	 (setf (c1form-values-type x) v))
	((var-p x)
	 (setf (var-type x) v))
	(t
         (error)
         (cmpnote "Cannot change type of location ~A" x))))

(defun enforce-types (fname arg-types forms &optional lisp-forms)
  (do* ((types arg-types (rest types))
        (fl forms (rest fl))
        (al lisp-forms (rest al))
        (i 1 (1+ i))
        (in-optionals nil))
       ((endp types)
        (when types
          (cmpwarn "Too many arguments passed to ~A" fname)))
    (let ((expected-type (first types)))
      (when (member expected-type '(* &rest &key &allow-other-keys) :test #'eq)
        (return))
      (when (eq expected-type '&optional)
        (when (or in-optionals (null (rest types)))
          (cmpwarn "Syntax error in type proclamation for function ~A.~&~A"
                   fname arg-types))
        (setf in-optionals t
              types (rest types)
              expected-type (first types)))
      (when (endp fl)
        (unless in-optionals
          (cmpwarn "Too few arguments for proclaimed function ~A" fname))
        (return))
      (when lisp-forms
        (let* ((form (first fl))
               (lisp-form (first al))
               (old-type (c1form-or-loc-values-type form)))
          (and-form-type expected-type form lisp-form
                         :safe "In the argument ~d of a call to ~a" i fname)
          ;; In safe mode, we cannot assume that the type of the
          ;; argument is going to be the right one.
          (unless (zerop (cmp-env-optimization 'safety))
            (setf (c1form-or-loc-values-type form) old-type)))))))

(defun infer-arg-and-return-types (fname forms &optional (env *cmp-env*))
  (let ((found (get-sysprop fname 'C1TYPE-PROPAGATOR))
        arg-types
        (return-type '(VALUES &REST T)))
    (cond (found
           (multiple-value-setq (arg-types return-type)
             (apply found fname (mapcar #'c1form-or-loc-primary-type forms))))
          ((multiple-value-setq (arg-types found)
             (get-arg-types fname env))
           (setf return-type (or (get-return-type fname) return-type))))
    (values arg-types return-type found)))

(defun propagate-types (fname forms lisp-forms)
  (multiple-value-bind (arg-types return-type found)
      (infer-arg-and-return-types fname forms)
    (when found
      (enforce-types fname arg-types forms lisp-forms))
    return-type))

(defmacro def-type-propagator (fname lambda-list &body body)
  (unless (member '&rest lambda-list)
    (let ((var (gensym)))
      (setf lambda-list (append lambda-list (list '&rest var))
            body (list* `(declare (ignorable ,var)) body)))
    `(put-sysprop ',fname 'C1TYPE-PROPAGATOR
                  #'(ext:lambda-block ,fname ,lambda-list ,@body))))

(defun copy-type-propagator (orig dest-list)
  (loop with function = (get-sysprop orig 'C1TYPE-PROPAGATOR)
     for name in dest-list
     do (put-sysprop name 'C1TYPE-PROPAGATOR function)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; TYPE CHECKING
;;

(defun remove-function-types (type)
  ;; We replace this type by an approximate one that contains no function
  ;; types. This function may not produce the best approximation. Hence,
  ;; it is only used for optional type checks where we do not want to pass
  ;; TYPEP a complex type.
  (flet ((simplify-type (type)
           (cond ((subtypep type '(NOT FUNCTION))
                  type)
                 ((subtypep type 'FUNCTION)
                  'FUNCTION)
                 (t
                  T))))
    (if (atom type)
        (simplify-type type)
        (case (first type)
          ((OR AND NOT)
           (cons (first type)
                 (loop for i in (rest type) collect (remove-function-types i))))
          (FUNCTION 'FUNCTION)
          (otherwise (simplify-type type))))))

(defmacro optional-check-type (&whole whole var-name type &environment env)
  "Generates a type check that is only activated for the appropriate
safety settings and when the type is not trivial."
  (unless (policy-automatic-check-type-p env)
    (cmpnote "Unable to emit check for variable ~A" whole))
  (when (policy-automatic-check-type-p env)
    (setf type (remove-function-types type))
    (multiple-value-bind (ok valid)
	(subtypep 't type)
      (unless (or ok (not valid))
	`(check-type ,var-name ,type)))))

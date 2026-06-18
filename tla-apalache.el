;;; tla-apalache.el --- Apalache support for TLA+ major mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Matt Curtis

;; Author: Matt Curtis <matt.r.curtis@gmail.com>
;; Keywords: languages, tools
;; Package-Requires: ((emacs "26.1") (transient "0.3"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Support for the Apalache symbolic model checker for TLA+.
;; Provides commands for running check, parse, typecheck, simulate, and test.

;;; Code:

(require 'transient)
(require 'seq)

(defgroup tla-apalache nil
  "Apalache symbolic model checker support for TLA+."
  :group 'languages
  :tag "Apalache")

(defcustom tla-apalache-command "apalache-mc"
  "The command to run the Apalache symbolic model checker.
Can be the apalache-mc script, or e.g. `java -jar apalache.jar'.

Apalache is a bounded symbolic model checker for TLA+ that uses
SMT solving. Unlike TLC's explicit enumeration, Apalache handles
large/infinite domains symbolically."
  :type 'string
  :risky t
  :group 'tla-apalache)

(defvar tla--apalache-inv "Inv"
  "Default invariant for Apalache model checking.")

(defvar tla--apalache-length "10"
  "Default execution length for Apalache bounded model checking.")

(defvar tla--apalache-cinit nil
  "Constant initializer predicate for Apalache (optional).")

(defvar tla--apalache-max-run "100"
  "Number of simulation runs for Apalache simulate command (default: 100).")

(defvar tla-pcal--apalache-output-traces nil
  "Output trace option for Apalache (optional).
Accepts \"true\" or \"false\".
When nil, the option is omitted and Apalache uses its default.")

(transient-define-infix tla--apalache-max-run-infix ()
  :description "Max runs (simulate)"
  :class 'transient-lisp-variable
  :variable 'tla--apalache-max-run
  :key "-r"
  :shortarg "-r"
  :argument "--max-run="
  :reader (lambda (prompt _initial-input _history)
            (read-string prompt tla--apalache-max-run)))

(transient-define-infix tla--apalache-inv-infix ()
  :description "Invariant"
  :class 'transient-lisp-variable
  :variable 'tla--apalache-inv
  :key "-i"
  :shortarg "-i"
  :argument "--inv="
  :reader (lambda (prompt _initial-input _history)
            (read-string prompt tla--apalache-inv)))

(transient-define-infix tla--apalache-length-infix ()
  :description "Length (steps)"
  :class 'transient-lisp-variable
  :variable 'tla--apalache-length
  :key "-l"
  :shortarg "-l"
  :argument "--length="
  :reader (lambda (prompt _initial-input _history)
            (read-string prompt tla--apalache-length)))

(transient-define-infix tla--apalache-config-infix ()
  :description "Config file"
  :class 'transient-lisp-variable
  :variable 'tla--current-config-file
  :key "-c"
  :shortarg "-c"
  :argument "--config="
  :reader (lambda (prompt _initial-input _history)
            (read-file-name
              prompt
              (file-name-directory (or tla--current-config-file ""))
              (file-name-nondirectory (or tla--current-config-file ""))
              nil
              nil
              (lambda (f)
                (or (not (stringp f))
                    (directory-name-p f)
                    (string= (file-name-extension f) "cfg"))))))

(transient-define-infix tla--apalache-cinit-infix ()
  :description "ConstInit predicate"
  :class 'transient-lisp-variable
  :variable 'tla--apalache-cinit
  :key "-C"
  :shortarg "-C"
  :argument "--cinit="
  :reader (lambda (prompt _initial-input _history)
            (read-string prompt (or tla--apalache-cinit ""))))

(transient-define-infix tla-pcal--apalache-output-traces-infix ()
  :description "Output trace"
  :class 'transient-lisp-variable
  :variable 'tla-pcal--apalache-output-traces
  :key "-o"
  :shortarg "-o"
  :argument "--output-traces="
  :reader (lambda (_prompt _initial-input _history) "true"))

(defun tla--run-apalache (&optional args)
  "Run Apalache symbolic model checker on current TLA+ spec.
Apalache uses bounded model checking with SMT solving.
Requires --inv and --length parameters (mandatory for check command)."
  (interactive
   (list (transient-args 'tla-pcal-transient)))
  (transient-set)
  (let* ((filename (file-relative-name buffer-file-name))
         (inv-arg (car (seq-filter (lambda (a) (string-prefix-p "--inv=" a)) args)))
         (inv (if inv-arg (substring inv-arg 6) tla--apalache-inv))
         (length-arg (car (seq-filter (lambda (a) (string-prefix-p "--length=" a)) args)))
         (length (if length-arg (substring length-arg 9) tla--apalache-length))
         (config-arg (car (seq-filter (lambda (a) (string-prefix-p "--config=" a)) args)))
         (config (when config-arg (substring config-arg 9)))
         (cinit-arg (car (seq-filter (lambda (a) (string-prefix-p "--cinit=" a)) args)))
         (cinit (when cinit-arg (substring cinit-arg 7)))
         (no-deadlock (member "--no-deadlock" args))
         (output-traces-arg (car (seq-filter (lambda (a) (string-prefix-p "--output-traces=" a)) args)))
         (output-traces (if output-traces-arg (substring output-traces-arg 15) tla-pcal--apalache-output-traces)))
    (set (make-local-variable 'compile-command)
         (concat tla-apalache-command " check "
                 "--inv=" inv " "
                 "--length=" length " "
                 (when config (concat "--config=" config " "))
                 (when cinit (concat "--cinit=" cinit " "))
                 (when no-deadlock "--no-deadlock ")
                 (when output-traces "--output-traces=true ")
                 (shell-quote-argument filename)))
    (compile compile-command)))

(defun tla--run-apalache-parse ()
  "Run Apalache parse on current TLA+ spec.
Parses and flattens the specification for syntax validation."
  (interactive)
  (let ((filename (file-relative-name buffer-file-name)))
    (set (make-local-variable 'compile-command)
         (concat tla-apalache-command " parse "
                 (shell-quote-argument filename)))
    (compile compile-command)))

(defun tla--run-apalache-typecheck ()
  "Run Apalache typecheck on current TLA+ spec.
Runs Snowcat type checker to catch type errors early."
  (interactive)
  (let ((filename (file-relative-name buffer-file-name)))
    (set (make-local-variable 'compile-command)
         (concat tla-apalache-command " typecheck "
                 (shell-quote-argument filename)))
    (compile compile-command)))

(defun tla--run-apalache-simulate (&optional args)
  "Run Apalache simulate on current TLA+ spec.
Randomized symbolic execution, faster than check for finding violations.
Uses same parameters as check plus --max-run for number of simulations."
  (interactive
   (list (transient-args 'tla-pcal-transient)))
  (transient-set)
  (let* ((filename (file-relative-name buffer-file-name))
         (inv-arg (car (seq-filter (lambda (a) (string-prefix-p "--inv=" a)) args)))
         (inv (if inv-arg (substring inv-arg 6) tla--apalache-inv))
         (length-arg (car (seq-filter (lambda (a) (string-prefix-p "--length=" a)) args)))
         (length (if length-arg (substring length-arg 9) tla--apalache-length))
         (max-run-arg (car (seq-filter (lambda (a) (string-prefix-p "--max-run=" a)) args)))
         (max-run (if max-run-arg (substring max-run-arg 10) tla--apalache-max-run))
         (config-arg (car (seq-filter (lambda (a) (string-prefix-p "--config=" a)) args)))
         (config (when config-arg (substring config-arg 9)))
         (cinit-arg (car (seq-filter (lambda (a) (string-prefix-p "--cinit=" a)) args)))
         (cinit (when cinit-arg (substring cinit-arg 7)))
         (no-deadlock (member "--no-deadlock" args))
         (output-traces-arg (car (seq-filter (lambda (a) (string-prefix-p "--output-traces=" a)) args)))
         (output-traces (if output-traces-arg (substring output-traces-arg 15) tla-pcal--apalache-output-traces)))
    (set (make-local-variable 'compile-command)
         (concat tla-apalache-command " simulate "
                 "--inv=" inv " "
                 "--length=" length " "
                 "--max-run=" max-run " "
                 (when config (concat "--config=" config " "))
                 (when cinit (concat "--cinit=" cinit " "))
                 (when no-deadlock "--no-deadlock ")
                 (when output-traces (concat "--output-traces=" (shell-quote-argument output-traces) " "))
                 (shell-quote-argument filename)))
    (compile compile-command)))

(defun tla--run-apalache-test (&optional args)
  "Run Apalache test on current TLA+ spec.
Single action testing mode for unit testing individual actions."
  (interactive
   (list (transient-args 'tla-pcal-transient)))
  (transient-set)
  (let* ((filename (file-relative-name buffer-file-name))
         (config-arg (car (seq-filter (lambda (a) (string-prefix-p "--config=" a)) args)))
         (config (when config-arg (substring config-arg 9)))
         (output-traces-arg (car (seq-filter (lambda (a) (string-prefix-p "--output-traces=" a)) args)))
         (output-traces (if output-traces-arg (substring output-traces-arg 15) tla-pcal--apalache-output-traces)))
    (set (make-local-variable 'compile-command)
         (concat tla-apalache-command " test "
                 (when config (concat "--config=" config " "))
                 (when output-traces (concat "--output-traces=" (shell-quote-argument output-traces) " "))
                 (shell-quote-argument filename)))
    (compile compile-command)))

(provide 'tla-apalache)
;;; tla-apalache.el ends here

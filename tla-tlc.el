;;; tla-tlc.el --- TLC support for TLA+ major mode  -*- lexical-binding: t; -*-

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

;; Support for the TLC model checker for TLA+.
;; Provides commands for creating config files and running TLC.

;;; Code:

(require 'transient)

(defgroup tla-tlc nil
  "TLC model checker support for TLA+."
  :group 'languages
  :tag "TLC")

(defcustom tla-tlc-command "tlc"
  "The command to run the TLC model checker.
Can be a script, or e.g. directly `java -cp tla2tools.jar tlc2.TLC'."
  :type 'string
  :risky t
  :group 'tla-tlc)

(defvar-local tla--current-config-file nil
  "The most recently-used or created configuration file for TLC.")

(defun tla-create-tlc-config-file (config-file)
  "Generate an empty TLC configuration in file CONFIG-FILE."
  (interactive "FTLC configuration filename: ")
  ;; TODO: we could detect all constants, and insert "X <-" for each
  (when (or (not (file-exists-p config-file))
            (yes-or-no-p "File exists, overwrite? "))
    (let ((buffer (find-file-noselect config-file)))
      (with-current-buffer buffer
        (erase-buffer)
        (insert "\\* -*- mode: tla; -*-

\\* For documentation of this file, see e.g. Lamport,
\\* \"Specifying Systems\" Section 14.7.1 (Page 262), available
\\* online at http://lamport.azurewebsites.net/tla/book-21-07-04.pdf

\\* CONSTANT definitions
CONSTANTS
\\* X <- const_X_1 \\* All constant definitions here

\\* INIT definition
INIT
\\* Init \\* The name of the Init formula.

\\* NEXT definition
NEXT
\\* Next \\* The name of the Next formula.

\\* INVARIANT definitions
INVARIANTS
\\* TypeOk OtherInvariantOk \\* Any invariant formulas

")
        (tla-mode))
      (setq tla--current-config-file config-file)
      (pop-to-buffer buffer))))

(transient-define-infix tla--tlc-config-file ()
  :description "TLC configuration"
  :class 'transient-lisp-variable
  :variable 'tla--current-config-file
  :key "-m"
  :shortarg "-m"
  :argument "-config "
  :reader (lambda (prompt _initial-input _history)
            (read-file-name
              prompt
              (file-name-directory (or tla--current-config-file ""))
              (file-name-nondirectory (or tla--current-config-file ""))
              t
              nil
              (lambda (f)
                ;; If the extension isn't ".cfg", TLC will add ".cfg" to the
                ;; filename by itself and then fail to find the config file
                (or (not (stringp f))
                    (directory-name-p f)
                    (string= (file-name-extension f) "cfg"))))))

(defun tla--run-tlc (&optional args)
  (interactive
   (list (transient-args 'tla-pcal-transient)))
  (transient-set)
  (set (make-local-variable 'compile-command)
         (concat tla-tlc-command " "
                 "-config " tla--current-config-file " "
                 (if (member "-deadlock" args) "-deadlock " "")
                 (shell-quote-argument (file-relative-name buffer-file-name))))
  (compile compile-command))

(provide 'tla-tlc)
;;; tla-tlc.el ends here

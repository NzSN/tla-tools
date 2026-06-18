;;; tla-tlapm.el --- TLAPS support for TLA+ major mode  -*- lexical-binding: t; -*-

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

;; Support for the TLA+ Proof System (TLAPS / tlapm).
;; Provides font-lock for proof constructs, commands for running tlapm,
;; and LSP integration for tlapm_lsp (eglot / lsp-mode).

;;; Code:

(require 'transient)

(defgroup tla-tlapm nil
  "TLAPS proof system support for TLA+."
  :group 'languages
  :tag "TLA+ Proof System")

(defface tla-tlaps-step-face
  '((t (:foreground "forest green" :weight bold)))
  "Face for TLAPS proof step labels like <1>1. <2>3a. <A>2."
  :group 'tla-tlapm)

(defface tla-tlaps-keyword-face
  '((t (:foreground "forest green" :weight bold)))
  "Face for TLAPS-specific keywords."
  :group 'tla-tlapm)

(defcustom tla-tlapm-command "tlapm"
  "The command to run the TLA+ Proof Manager (TLAPS)."
  :type 'string
  :risky t
  :group 'tla-tlapm)

(defcustom tla-tlapm-lsp-command "tlapm_lsp"
  "The command to run the TLAPS LSP server."
  :type 'string
  :risky t
  :group 'tla-tlapm)

;;;###autoload
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((tla-mode tla-pcal-mode) . (,tla-tlapm-lsp-command "--stdio")))
  (add-hook 'tla-mode-hook #'eglot-ensure))

;;;###autoload
(with-eval-after-load 'lsp-mode
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection
                                     (lambda () (list tla-tlapm-lsp-command "--stdio")))
                    :major-modes '(tla-mode tla-pcal-mode)
                    :server-id 'tlapm-lsp
                    :activation-fn 'lsp-activate-on
                    :priority -1))
  (add-hook 'tla-mode-hook #'lsp-deferred))

(defvar tla-tlapm-font-lock-keywords
  `((,(regexp-opt
       '("ACTION" "ASSUME" "BY" "COROLLARY" "DEF" "DEFINE" "DEFS"
         "HAVE" "HIDE" "LEMMA" "NEW" "OBVIOUS" "OMITTED" "ONLY"
         "PICK" "PROOF" "PROPOSITION" "PROVE" "QED" "RECURSIVE"
         "STATE" "SUFFICES" "TAKE" "TEMPORAL" "THEOREM" "USE"
         "WITNESS" "AXIOM")
       'symbols)
     . 'tla-tlaps-keyword-face)
    ("<[[:word:]]>+\\([[:word:]]*\\.?\\)?"
     . 'tla-tlaps-step-face))
  "Font lock keywords for TLAPS proof constructs.")

(defun tla--run-tlapm (&optional _args)
  "Run TLAPS proof manager on the current buffer."
  (interactive)
  (transient-set)
  (let ((filename (file-relative-name buffer-file-name)))
    (set (make-local-variable 'compile-command)
         (concat tla-tlapm-command " "
                 (shell-quote-argument filename)))
    (compile compile-command)))

(provide 'tla-tlapm)
;;; tla-tlapm.el ends here

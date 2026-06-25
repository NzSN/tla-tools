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

(declare-function lsp-get "ext:lsp-mode" (plist key))
(declare-function lsp--position-to-point "ext:lsp-mode" (position))
(declare-function lsp-warn "ext:lsp-mode" (format &rest args))
(declare-function lsp-register-client "ext:lsp-mode" (client))
(declare-function make-lsp-client "ext:lsp-mode" (&rest args))
(declare-function lsp-stdio-connection "ext:lsp-mode" (command))
(declare-function lsp-deferred "ext:lsp-mode" ())

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

(defface tla-tlapm-proved-face
  '((t (:underline "green" :extend nil)))
  "Face for proved proof steps."
  :group 'tla-tlapm)

(defface tla-tlapm-failed-face
  '((t (:underline "red" :extend nil)))
  "Face for failed proof steps."
  :group 'tla-tlapm)

(defface tla-tlapm-omitted-face
  '((t (:underline "#4e342e" :extend nil)))
  "Face for omitted proof steps."
  :group 'tla-tlapm)

(defface tla-tlapm-missing-face
  '((t (:underline "#e65100" :extend nil)))
  "Face for missing proof steps."
  :group 'tla-tlapm)

(defface tla-tlapm-pending-face
  '((t (:underline "#f57f17" :extend nil)))
  "Face for pending/progress proof steps."
  :group 'tla-tlapm)

(defcustom tla-tlapm-command "tlapm"
  "The command to run the TLA+ Proof Manager (TLAPS)."
  :type 'string
  :risky t
  :group 'tla-tlapm)

(defvar tla--tlapm-include-path nil
  "Directory to search for TLA+ modules (tlapm -I flag).")

(transient-define-infix tla--tlapm-include-path-infix ()
  :description "Include path"
  :class 'transient-lisp-variable
  :variable 'tla--tlapm-include-path
  :key "-I"
  :shortarg "-I"
  :argument "-I "
  :reader (lambda (prompt _initial-input _history)
            (read-directory-name prompt nil tla--tlapm-include-path t)))

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

(defvar-local tla-tlapm--proof-step-markers nil
  "Buffer-local proof step markers from the tlapm_lsp server.
Each element is an alist with keys :status, :range, :hover.")

(defvar-local tla-tlapm--step-overlays nil
  "Overlays currently showing proof step status in this buffer.")

(defvar-local tla-tlapm--current-proof-step nil
  "Buffer-local current proof step details from the tlapm_lsp server.
An alist with keys :kind, :status, :location, :obligations, :sub_count.")

(defun tla-tlapm--uri-to-path (uri)
  "Convert a file:// URI to a file path."
  (if (string-match "\\`file://\\([^/]\\|\\'\\)?\\(.*\\)\\'" uri)
      (match-string 2 uri)
    uri))

(defun tla-tlapm--status-face (status)
  "Return the face for a proof step STATUS."
  (pcase status
    ("proved"   'tla-tlapm-proved-face)
    ("failed"   'tla-tlapm-failed-face)
    ("omitted"  'tla-tlapm-omitted-face)
    ("missing"  'tla-tlapm-missing-face)
    ("pending"  'tla-tlapm-pending-face)
    ("progress" 'tla-tlapm-pending-face)
    (_          'tla-tlapm-pending-face)))

(defun tla-tlapm--clear-step-overlays ()
  "Remove all tlapm step overlays in the current buffer."
  (dolist (ov tla-tlapm--step-overlays)
    (delete-overlay ov))
  (setq tla-tlapm--step-overlays nil))

(defun tla-tlapm--make-step-overlays (beg end face hover)
  "Create overlays between BEG and END with FACE and HOVER.
Skips TLAPS keywords and leading whitespace on each line.
Returns a list of created overlays."
  (let ((overlays nil)
        (skip-re (concat "\\_<" (regexp-opt tla-tlapm--keywords) "\\_>"
                         "\\|^[ \t]+"))
        (pos beg))
    (save-excursion
      (while (< pos end)
        (goto-char pos)
        (if (re-search-forward skip-re end t)
            (let ((skip-beg (match-beginning 0))
                  (skip-end (match-end 0)))
              (when (> skip-beg pos)
                (let ((ov (make-overlay pos skip-beg)))
                  (overlay-put ov 'face face)
                  (when hover (overlay-put ov 'help-echo hover))
                  (overlay-put ov 'tlapm-step t)
                  (push ov overlays)))
              (setq pos (max pos skip-end)))
          (when (> end pos)
            (let ((ov (make-overlay pos end)))
              (overlay-put ov 'face face)
              (when hover (overlay-put ov 'help-echo hover))
              (overlay-put ov 'tlapm-step t)
              (push ov overlays)))
          (setq pos end))))
    (nreverse overlays)))

(defun tla-tlapm--apply-step-markers (markers)
  "Apply overlays for proof step MARKERS in the current buffer."
  (tla-tlapm--clear-step-overlays)
  (dolist (m markers)
    (let* ((range (lsp-get m :range))
           (status (lsp-get m :status))
           (hover (lsp-get m :hover))
           (beg (lsp--position-to-point (lsp-get range :start)))
           (end (lsp--position-to-point (lsp-get range :end)))
           (ovs (tla-tlapm--make-step-overlays
                 beg end (tla-tlapm--status-face status) hover)))
      (setq tla-tlapm--step-overlays
            (nconc ovs tla-tlapm--step-overlays)))))

(defun tla-tlapm--lsp-handle-proof-step-markers (_workspace params)
  "Handle tlaplus/tlaps/proofStepMarkers notification from tlapm_lsp."
  (condition-case err
      (when (vectorp params)
        (let* ((uri (aref params 0))
               (markers (aref params 1))
               (path (tla-tlapm--uri-to-path uri))
               buffer)
          (when (and path (setq buffer (find-buffer-visiting path)))
            (with-current-buffer buffer
              (setq tla-tlapm--proof-step-markers (append markers nil))
              (tla-tlapm--apply-step-markers tla-tlapm--proof-step-markers)))))
    (error
     (lsp-warn "tlapm_lsp proofStepMarkers: %s" (error-message-string err)))))

(defun tla-tlapm--lsp-handle-current-proof-step (_workspace params)
  "Handle tlaplus/tlaps/currentProofStep notification from tlapm_lsp."
  (condition-case err
      (when (and params (not (eq params :json-null)))
        (let* ((loc (lsp-get params :location))
               (uri (lsp-get loc :uri))
               (path (tla-tlapm--uri-to-path uri))
               buffer
               (counts (lsp-get params :sub_count)))
          (when (and path (setq buffer (find-buffer-visiting path)))
            (with-current-buffer buffer
              (setq tla-tlapm--current-proof-step params)
              (when counts
                (message "TLAPS: proved %s / failed %s / omitted %s / missing %s"
                         (lsp-get counts :proved)
                         (lsp-get counts :failed)
                         (lsp-get counts :omitted)
                         (lsp-get counts :missing)))))))
    (error
     (lsp-warn "tlapm_lsp currentProofStep: %s" (error-message-string err)))))

;;;###autoload
(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-language-id-configuration '(tla-mode . "tlaplus"))
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection
                                     (lambda () (list tla-tlapm-lsp-command "--stdio")))
                    :major-modes '(tla-mode tla-pcal-mode)
                    :language-id "tlaplus"
                    :server-id 'tlapm-lsp
                    :notification-handlers
                    (let ((ht (make-hash-table :test 'equal)))
                      (puthash "tlaplus/tlaps/proofStepMarkers"
                               #'tla-tlapm--lsp-handle-proof-step-markers ht)
                      (puthash "tlaplus/tlaps/currentProofStep"
                               #'tla-tlapm--lsp-handle-current-proof-step ht)
                      ht)
                     :priority -1))
  (add-hook 'tla-mode-hook #'lsp-deferred))

(defvar tla-tlapm--keywords
  '("ACTION" "ASSUME" "BY" "COROLLARY" "DEF" "DEFINE" "DEFS"
    "HAVE" "HIDE" "LEMMA" "NEW" "OBVIOUS" "OMITTED" "ONLY"
    "PICK" "PROOF" "PROPOSITION" "PROVE" "QED" "RECURSIVE"
    "STATE" "SUFFICES" "TAKE" "TEMPORAL" "THEOREM" "USE"
    "WITNESS" "AXIOM")
  "List of TLAPS keywords.")

(defvar tla-tlapm-font-lock-keywords
  `((,(regexp-opt tla-tlapm--keywords 'symbols)
     . 'tla-tlaps-keyword-face)
    ("<[[:word:]]>+\\([[:word:]]*\\.?\\)?"
     . 'tla-tlaps-step-face))
  "Font lock keywords for TLAPS proof constructs.")

(defun tla-tlapm--prove-range (beg end)
  "Ask tlapm_lsp to check proofs in range BEG to END."
  (lsp-request-async "workspace/executeCommand"
    (list :command "tlaplus.tlaps.check-step.lsp"
          :arguments (vector
                      (lsp--versioned-text-document-identifier)
                      (lsp--region-to-range beg end)))
    (lambda (_response) nil)
    :mode 'detached))

(defun tla-tlapm-prove-step ()
  "Ask tlapm_lsp to prove the proof step at point."
  (interactive)
  (tla-tlapm--prove-range (line-beginning-position) (line-end-position)))

(defun tla-tlapm-prove-region ()
  "Ask tlapm_lsp to prove the region, or entire buffer if no region is active."
  (interactive)
  (let ((beg (if (use-region-p) (region-beginning) (point-min)))
        (end (if (use-region-p) (region-end) (point-max))))
    (tla-tlapm--prove-range beg end)))

(defun tla-tlapm-run (&optional args)
  "Run TLAPS proof manager on the current buffer."
  (interactive
   (list (transient-args 'tla-pcal-transient)))
  (transient-set)
  (let* ((filename (file-relative-name buffer-file-name))
         (include-args (seq-filter (lambda (a) (string-prefix-p "-I " a)) args)))
    (set (make-local-variable 'compile-command)
         (concat tla-tlapm-command " "
                 (mapconcat #'identity include-args " ")
                 (when include-args " ")
                 (shell-quote-argument filename)))
    (compile compile-command)))

(provide 'tla-tlapm)
;;; tla-tlapm.el ends here

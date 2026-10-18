;;; dsh-test.el --- Unit-suite loader and batch entry point -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

;;; Commentary:
;; Run all unit tests: emacs -Q --batch -l test/dsh-test.el
;; Load individual dsh-test-SUBSYSTEM files to select tests with M-x ert.
;; Bind `dsh-emacs-test-no-run' when loading this entry point from another
;; batch tool, then call `dsh-emacs-test-run' without terminating Emacs.

;;; Code:

(add-to-list 'load-path
             (file-name-directory (or load-file-name buffer-file-name)))
(require 'dsh-test-support)

(defvar dsh-emacs-test-no-run nil
  "Non-nil prevents this entry point from running tests on batch load.")

(dolist (file (directory-files dsh-emacs-test-directory t
                               "\\`dsh-test-.*\\.el\\'"))
  (unless (member (file-name-nondirectory file)
                  '("dsh-test-support.el" "dsh-test-runner-test.el"))
    (load file nil t)))

(defun dsh-emacs-test-run (&optional selector)
  "Run unit tests selected by SELECTOR and return ERT statistics.
SELECTOR defaults to the `dsh-unit' tag.  An empty selection is an error.
This function does not exit Emacs, so coverage tools can report afterward."
  (setq selector (or selector '(tag dsh-unit)))
  (unless (ert-select-tests selector t)
    (error "No unit tests match %S" selector))
  ;; Batch environments need not have gcc for native subr trampolines.
  ;; Bind only an existing option, preserving the Emacs 27 baseline and
  ;; the caller's native-compilation policy after the run.
  (cl-progv (when (boundp 'comp-enable-subr-trampolines)
              '(comp-enable-subr-trampolines))
      '(nil)
    (ert-run-tests-batch selector)))

(when (and noninteractive (not dsh-emacs-test-no-run))
  (let ((stats (dsh-emacs-test-run)))
    (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1))))

(provide 'dsh-test)
;;; dsh-test.el ends here

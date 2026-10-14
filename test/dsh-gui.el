;;; dsh-gui.el --- GUI display regression tests -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026
;; Author: dsh-emacs contributors
;; Keywords: tools
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Run from the repository root in a separate graphical Emacs:
;;   DSH_GUI_TEST_LOG=/tmp/dsh-gui.log emacs -Q -l "$PWD/test/dsh-gui.el" \
;;     -f dsh-emacs-gui-test-start
;; The runner writes ERT diagnostics to the log and exits 0 on success, 1 on
;; failure.  It requires a real GUI, but no dsh server or model provider.
;; Loading this file only defines the tests and runner; it never starts them.

;;; Code:

(add-to-list 'load-path
             (expand-file-name ".." (file-name-directory load-file-name)))
(require 'ert)
(require 'face-remap)
(require 'dsh-emacs-composer)

(ert-deftest dsh-emacs-gui-goal-row-short-goal-stays-on-one-visual-line ()
  "Text scaling must not wrap short goals through expanded padding."
  (should (display-graphic-p))
  (let* ((frame (selected-frame))
         (width (frame-width frame))
         (height (frame-height frame))
         (text-scale-mode-step 1.2)
         (goal (dsh-emacs-composer-goal-from-projection
                '((goal . ((objective . "short") (phase . "active")))))))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (set-frame-size frame 80 20)
          (with-temp-buffer
            (switch-to-buffer (current-buffer))
            (setq-local truncate-lines nil)
            (setq-local word-wrap t)
            (should (= (window-text-width) 80))
            (dolist (scale '(0 1))
              (text-scale-set scale)
              (dolist (actions '(t nil))
                (ert-info ((format "text-scale=%s, inline-actions=%S"
                                   scale actions))
                  (let ((dsh-emacs-composer-goal-actions actions))
                    (erase-buffer)
                    (insert (dsh-emacs-composer--render-row goal) "\nNEXT\n")
                    (goto-char (point-min))
                    (should (search-forward "Ongoing Goal" (line-end-position) t))
                    (should (search-forward "short" (line-end-position) t))
                    (goto-char (point-min))
                    (set-window-start (selected-window) (point-min))
                    (redisplay t)
                    ;; A buffer newline is not proof of a single visual line.
                    ;; One screen row must reach NEXT, not wrapped goal text.
                    (let ((next-line (1+ (line-end-position))))
                      (should (= (vertical-motion 1) 1))
                      (should (= (point) next-line))
                      (should (looking-at "NEXT$")))))))))
      (set-frame-size frame width height))))

(defun dsh-emacs-gui-test-run-and-exit ()
  "Run GUI display tests, write their log, then exit this Emacs process."
  (let ((log (or (getenv "DSH_GUI_TEST_LOG")
                 (expand-file-name "dsh-emacs-gui-test.log"
                                   temporary-file-directory)))
        (message-log-max t)
        (inhibit-message t)
        (failed t)
        (exit-code 1))
    (unwind-protect
        (progn
          (condition-case err
              (progn
                (unless (and (not noninteractive) (display-graphic-p))
                  (error "GUI display tests require a graphical Emacs"))
                (let ((stats (ert-run-tests-batch "^dsh-emacs-gui-")))
                  (setq failed
                        (> (ert-stats-completed-unexpected stats) 0))))
            (error (message "GUI display tests failed: %S" err)))
          (with-temp-file log
            (insert (with-current-buffer (messages-buffer) (buffer-string))))
          (unless failed (setq exit-code 0)))
      (kill-emacs exit-code))))

(defun dsh-emacs-gui-test-start ()
  "Schedule GUI tests after startup and exit with their result.
Use only in a separate test process; see the invocation in this file."
  (unless (and (not noninteractive) (display-graphic-p))
    (error "GUI display tests require a graphical Emacs; omit --batch"))
  (run-with-idle-timer 0 nil #'dsh-emacs-gui-test-run-and-exit))

;;; dsh-gui.el ends here

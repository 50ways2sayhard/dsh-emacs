;;; dsh-gui.el --- GUI display regression tests -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026
;; Author: dsh-emacs contributors
;; Keywords: tools
;; Package-Requires: ((emacs "28.1"))

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
(require 'dsh-emacs)

(ert-deftest dsh-emacs-gui-goal-row-short-goal-stays-on-one-visual-line ()
  "Text scaling must not wrap short goals through expanded padding."
  (should (display-graphic-p))
  (let* ((frame (selected-frame))
         (width (frame-width frame))
         (height (frame-height frame))
         (text-scale-mode-step 1.2)
         (goal (dsh-protocol-goal-projection--from-alist
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

(ert-deftest dsh-emacs-gui-history-rounds-and-readers ()
  "Visit requested rounds unless point moved; retain independent readers."
  (should (display-graphic-p))
  (save-window-excursion
    (dolist (trim-header '(nil t))
      (with-temp-buffer
        (dsh-emacs-mode)
        (switch-to-buffer (current-buffer))
        (delete-other-windows)
        (setq-local dsh-emacs--buffer-session "gui-history")
        (let ((dsh-emacs-max-buffer-size nil))
          (dsh-emacs-render-history-events
           `(((type . "event")
              (event . ((type . "user/message") (seq . 20)
                        (data . ((content . [((type . "text")
                                              (text . "CURRENT QUESTION"))]))))))
             ((type . "event")
              (event . ((type . "assistant/message") (seq . 21)
                        (data . ((message . ((content . [((type . "text")
                                                          (text . ,(mapconcat
                                                                    (lambda (n) (format "line %d" n))
                                                                    (number-sequence 1 100) "\n")))])))))))))))
        (setq dsh-emacs--history-earliest-seq 20
              dsh-emacs--history-cursor 21
              dsh-emacs--history-has-more t)
        (goto-char (point-max))
        (insert "KEEP DRAFT")
        (when trim-header
          (let ((inhibit-read-only t))
            (delete-region (point-min)
                           (text-property-any (point-min) (point-max)
                                              'dsh-emacs-transcript-block t))))
        (let* ((first (selected-window))
               (second (split-window-below))
               (boundary (dsh-emacs-render--history-prepend-marker))
               (inside (save-excursion
                         (goto-char (point-min))
                         (search-forward "line 30")
                         (copy-marker (line-beginning-position) t)))
               (page '((records . [((type . "event")
                                    (event . ((type . "turn/start") (seq . 9)
                                              (data . ((turn . 1))))))
                                   ((type . "event")
                                    (event . ((type . "user/message") (seq . 10)
                                              (data . ((content . [((type . "text")
                                                                    (text . "OLDER QUESTION"))]))))))
                                   ((type . "event")
                                    (event . ((type . "tool/call") (seq . 11)
                                              (data . ((callId . "history-tool")
                                                       (name . "shell")
                                                       (arguments . "{\"command\":\"pwd\"}"))))))])
                       (hasMore . :json-false))))
          (set-window-buffer second (current-buffer))
          (set-window-start first boundary t)
          (set-window-point first boundary)
          (set-window-start second inside t)
          (set-window-point second inside)
          (redisplay t)
          (let (reply)
            (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                       (lambda (method args callback &rest _)
                         (should (equal method "session/page"))
                         (should (= (alist-get 'minTurns
                                               (alist-get 'turnWindow
                                                          (alist-get 'request args))) 1))
                         (setq reply callback))))
              (execute-kbd-macro (kbd "C-u 1 C-c C-o")))
            ;; A user's movement during an asynchronous request takes priority
            ;; over visiting the newly loaded range, even at the prepend edge.
            (when trim-header (forward-char 1))
            (let ((dsh-emacs-max-buffer-size 80))
              (funcall reply t page)))
          (redisplay t)
          (if trim-header
              (progn
                (should (= (window-start first) boundary))
                (should (= (window-point first) (1+ boundary))))
            (should (looking-at "[ \t\n]*OLDER QUESTION"))
            (should (= (window-start first) (point)))
            (should (< (point) boundary)))
          (should (= (window-start second) inside))
          (should (= (window-point second) inside))
          (execute-kbd-macro (kbd "C-c >"))
          (redisplay t)
          (should (= (point) (point-max)))
          (should (equal (dsh-emacs-render--following-windows) (list first)))
          (dsh-emacs-ui-update-fragment
           `((:namespace-id . "gui") (:block-id . "live")
             (:label-left . "Live tool")
             (:body . ,(mapconcat #'number-to-string (number-sequence 1 80) "\n")))
           :expanded t :insert-before (dsh-emacs-render--input-insert-point))
          (redisplay t)
          (should (pos-visible-in-window-p (1- (point-max)) first))
          (should (= (window-start second) inside))
          (should (= (window-point second) inside))
          (let ((dsh-emacs-max-buffer-size 80)
                (before (buffer-string)))
            (dsh-emacs-render--trim-buffer)
            (should (equal-including-properties before (buffer-string))))
          (should (equal (buffer-substring-no-properties dsh-emacs--input-marker
                                                         (point-max)) "KEEP DRAFT"))
          (set-marker boundary nil)
          (set-marker inside nil))))))

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

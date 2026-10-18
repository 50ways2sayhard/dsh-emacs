;;; dsh-test-copy.el --- Copy tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

;; --- Test 49: code block copy ---
(ert-deftest dsh-emacs-test-copy-copy-code-block-copies-body ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-copy-block*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "before\n```elisp\n(message \"hi\")\n```\nafter\n")
          (dsh-emacs-markdown-replace-markup :force t :highlight-blocks nil)
          ;; Point inside the code block body -> copy
          (goto-char (point-min))
          (when (search-forward "(message" nil t)
            (dsh-emacs-copy-code-block)
            (ert-info ((format "%s" "copy-code-block-copies-body"))
              (should (string= "(message \"hi\")" (car kill-ring)))))
          ;; Point outside the block -> explicit error instead of silence
          (goto-char (point-min))
          (let ((err (condition-case e
                         (progn (dsh-emacs-copy-code-block) nil)
                       (error (error-message-string e)))))
            (ert-info ((format "%s" "copy-code-block-errors-outside"))
              (should (and (stringp err)
                           (string-match-p "not inside" err))))))
      (kill-buffer buf))))

;; The scan must stop at point-max: no code block there is not a code block.
(ert-deftest dsh-emacs-test-copy-copy-code-block-errors-at-point-max ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-copy-block-max*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (insert "plain transcript text\n")
          (goto-char (point-max))
          (ert-info ((format "%s" "copy-code-block-errors-at-point-max"))
            (should (equal "Point is not inside a code block"
                           (condition-case e
                               (progn (dsh-emacs-copy-code-block) nil)
                             (user-error (error-message-string e)))))))
      (kill-buffer buf))))

;; --- Test 49b: copy command (assistant message / dwim) ---
(ert-deftest dsh-emacs-test-copy-copy-assistant-message-excludes-other-roles ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-copy-assistant*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-render-user-message
           '((seq . 1) (data . ((content . [((type . "text") (text . "ask me"))])))))
          (dsh-emacs-render-assistant-message
           '((seq . 2)
             (data . ((turn . 1) (step . 1)
                      (message . ((content . [((type . "text")
                                               (text . "First **reply**."))])))))))
          (dsh-emacs-render-tool-call
           '((type . "tool/call") (seq . 3)
             (data . ((callId . "c1") (name . "read")
                      (arguments . "{\"path\":\"/tmp/x\"}")))))
          (dsh-emacs-render-assistant-message
           '((seq . 4)
             (data . ((turn . 1) (step . 2)
                      (message . ((content . [((type . "text")
                                               (text . "Second reply."))])))))))
          (dsh-emacs-copy-assistant-message)
          (ert-info ((format "%s" "copy-assistant-message-excludes-other-roles"))
            (should (equal (car kill-ring) "First reply.\n\nSecond reply."))))
      (kill-buffer buf))))

(defun dsh-test--copy-dwim-fixture ()
  "Return a chat buffer with a user prompt, a reply and a fenced-code reply."
  (let ((buf (generate-new-buffer " *dsh-copy-dwim*")))
    (with-current-buffer buf
      (dsh-emacs-mode)
      (dsh-emacs-render-user-message
       '((seq . 1) (data . ((content . [((type . "text") (text . "ask me"))])))))
      (dsh-emacs-render-assistant-message
       '((seq . 2) (data . ((turn . 1) (step . 1)
                            (message . ((content . [((type . "text")
                                                     (text . "First reply."))])))))))
      (dsh-emacs-render-assistant-message
       '((seq . 3) (data . ((turn . 1) (step . 2)
                            (message . ((content . [((type . "text")
                                                     (text . "Code:\n\n```elisp\n(+ 1 2)\n```"))]))))))))
    buf))

;; copy-dwim: region > code block > message at point > all assistant messages.
(ert-deftest dsh-emacs-test-copy-copy-dwim-prefers-code-block-at-point ()
  :tags '(dsh-unit)
  (let ((buf (dsh-test--copy-dwim-fixture)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "(+ 1 2)")
          (goto-char (match-beginning 0))
          (dsh-emacs-copy-dwim)
          (ert-info ((format "%s" "copy-dwim-prefers-code-block-at-point"))
            (should (equal (car kill-ring) "(+ 1 2)")))
          (setq kill-ring nil)
          (goto-char (point-min))
          (search-forward "First reply.")
          (goto-char (match-beginning 0))
          (dsh-emacs-copy-dwim)
          (ert-info ((format "%s" "copy-dwim-copies-message-at-point"))
            (should (equal (car kill-ring) "First reply.")))
          (setq kill-ring nil)
          (let ((transient-mark-mode t))
            (goto-char (point-min))
            (search-forward "ask me")
            (set-mark (match-beginning 0))
            (goto-char (match-end 0))
            (activate-mark)
            (dsh-emacs-copy-dwim))
          (ert-info ((format "%s" "copy-dwim-copies-active-region"))
            (should (equal (car kill-ring) "ask me")))
          (deactivate-mark)
          (setq kill-ring nil)
          (goto-char (point-max))
          (dsh-emacs-copy-dwim)
          (let ((last (car kill-ring)))
            (ert-info ((format "%s" "copy-dwim-falls-back-to-last-assistant-message"))
              (should (string-match-p "Code:" last))
              (should (string-match-p (regexp-quote "(+ 1 2)") last))
              (should (not (string-match-p "First reply" last)))
              (should (not (string-match-p "ask me" last))))
            (setq kill-ring nil)
            (dsh-emacs-copy-last-assistant-message)
            (ert-info ((format "%s" "copy-last-assistant-message-matches-dwim-fallback"))
              (should (equal (car kill-ring) last))))
          (setq kill-ring nil)
          (dsh-emacs-copy-assistant-message)
          (ert-info ((format "%s" "copy-assistant-message-keeps-every-reply"))
            (should (string-match-p "First reply" (car kill-ring)))
            (should (string-match-p "Code:" (car kill-ring))))
          (ert-info ((format "%s" "copy-dwim-keybinding"))
            (should (eq (lookup-key dsh-emacs-mode-map (kbd "C-c C-w"))
                        #'dsh-emacs-copy-dwim))
            (should (null (lookup-key dsh-emacs-mode-map (kbd "C-c C-k"))))))
      (kill-buffer buf))))

(ert-deftest dsh-emacs-test-copy-copy-assistant-message-errors-without-replies ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-copy-assistant-empty*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-render-user-message
           '((seq . 1) (data . ((content . [((type . "text") (text . "hi"))])))))
          (ert-info ((format "%s" "copy-assistant-message-errors-without-replies"))
            (should (equal "No assistant messages in this transcript"
                           (condition-case e
                               (progn (dsh-emacs-copy-assistant-message) nil)
                             (user-error (error-message-string e)))))))
      (kill-buffer buf))))

;; A live stream is tagged from its first delta, before its final message.
(ert-deftest dsh-emacs-test-copy-copy-assistant-message-includes-live-stream ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-copy-assistant-stream*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-render--start-assistant-stream
           '((data . ((turn . 1) (step . 1)))) "partial")
          (dsh-emacs-copy-assistant-message)
          (ert-info ((format "%s" "copy-assistant-message-includes-live-stream"))
            (should (equal (car kill-ring) "partial"))))
      (kill-buffer buf))))

;; A timer flush appends to the same tagged run, even while Markdown is
;; deferred, so a copy mid-stream never returns only the first delta.
(ert-deftest dsh-emacs-test-copy-copy-last-assistant-message-includes-flushed-deltas ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-copy-assistant-flush*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (let* ((dsh-emacs-stream-markdown-limit 1)
                 (event '((data . ((turn . 1) (step . 1))))))
            (dsh-emacs-render--start-assistant-stream event "Hello ")
            (dsh-emacs-render--start-assistant-stream event "world")
            (dsh-emacs-render--flush-stream)
            (dsh-emacs-copy-last-assistant-message)
            (ert-info ((format "%s" "copy-last-assistant-message-includes-flushed-deltas"))
              (should (equal (car kill-ring) "Hello world")))))
      (kill-buffer buf))))

(provide 'dsh-test-copy)
;;; dsh-test-copy.el ends here

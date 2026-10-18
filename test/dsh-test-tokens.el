;;; dsh-test-tokens.el --- Tokens tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

;; --- Test 2: Token formatting ---
(ert-deftest dsh-emacs-test-tokens-format-tokens-1234 ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "format-tokens 1234"))
    (should (string= "1.2k" (dsh-emacs-format-tokens 1234)))))

(ert-deftest dsh-emacs-test-tokens-format-tokens-1500000 ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "format-tokens 1500000"))
    (should (string= "1.5M" (dsh-emacs-format-tokens 1500000)))))

(ert-deftest dsh-emacs-test-tokens-format-tokens-100 ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "format-tokens 100"))
    (should (string= "100" (dsh-emacs-format-tokens 100)))))

;; --- Test 3: Token structure ---
(ert-deftest dsh-emacs-test-tokens-usage-create ()
  :tags '(dsh-unit)
  (let ((usage (dsh-emacs-make-usage)))
    (ert-info ((format "%s" "usage-create"))
      (should (and (= 0 (dsh-emacs-usage-input usage))
                   (= 0 (dsh-emacs-usage-output usage)))))))

(ert-deftest dsh-emacs-test-tokens-usage-create-with-args ()
  :tags '(dsh-unit)
  (let ((usage (dsh-emacs-make-usage 100 50)))
    (ert-info ((format "%s" "usage-create with args"))
      (should (and (= 100 (dsh-emacs-usage-input usage))
                   (= 50 (dsh-emacs-usage-output usage)))))))

;; --- Test 4: Token accumulation ---
(ert-deftest dsh-emacs-test-tokens-usage-add ()
  :tags '(dsh-unit)
  (let ((u1 (dsh-emacs-make-usage 100 50))
        (u2 (dsh-emacs-make-usage 200 100)))
    (dsh-emacs-usage-add u1 u2)
    (ert-info ((format "%s" "usage-add"))
      (should (and (= 300 (dsh-emacs-usage-input u1))
                   (= 150 (dsh-emacs-usage-output u1)))))))

;; --- Test 5b: usage parsing (real dsh event shape: data.usage + camelCase) ---
(ert-deftest dsh-emacs-test-tokens-usage-from-event-parses-real-data-usage ()
  :tags '(dsh-unit)
  (let* ((event '(("type" . "assistant/message")
                  ("seq" . 103)
                  ("data" . (("usage" . (("inputTokens" . 626)
                                         ("outputTokens" . 155)
                                         ("cacheReadTokens" . 7168)))))))
         (usage (dsh-emacs-usage-from-event event)))
    (ert-info ((format "%s" "usage-from-event parses real data.usage"))
      (should (and (= 626 (dsh-emacs-usage-input usage))
                   (= 155 (dsh-emacs-usage-output usage))
                   (= 7168 (dsh-emacs-usage-cache-read usage)))))))

(ert-deftest dsh-emacs-test-tokens-usage-from-event-no-usage-yields-zero ()
  :tags '(dsh-unit)
  (let* ((usage (dsh-emacs-usage-from-event
                 '(("type" . "assistant/message")
                   ("data" . (("message" . (("content" . "no usage here"))))))))
         (all-zero (and (= 0 (dsh-emacs-usage-input usage))
                        (= 0 (dsh-emacs-usage-output usage)))))
    (ert-info ((format "%s" "usage-from-event no-usage yields zero"))
      (should all-zero))))

(provide 'dsh-test-tokens)
;;; dsh-test-tokens.el ends here

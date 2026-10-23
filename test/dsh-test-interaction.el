;;; dsh-test-interaction.el --- Composer form interaction tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

(defun dsh-emacs-test--interaction-chat (name session)
  "Return a chat buffer NAME registered as SESSION with an input area."
  (let ((chat (get-buffer-create name)))
    (with-current-buffer chat
      (dsh-emacs-mode)
      (setq-local dsh-emacs--buffer-session session)
      (dsh-emacs--setup-input-area))
    chat))

(defun dsh-emacs-test--interaction-question
    (&optional id text options multi)
  "Wire-shaped question alist for Composer form tests."
  (list (cons 'id (or id "q1"))
        (cons 'question (or text "Pick one"))
        (cons 'header "Choice")
        (cons 'multiSelect (if multi t :json-false))
        (cons 'options
              (mapcar (lambda (label)
                        (list (cons 'label label)
                              (cons 'description (format "%s desc" label))))
                      (or options '("Alpha" "Beta"))))))

(ert-deftest dsh-emacs-test-interaction-decodes-raw-waterfall-questions ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-decode*" "sess-d")))
    (unwind-protect
        (let ((dsh-emacs-enable-notifications nil))
          (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs-composer--row-width)
                     (lambda () 80)))
            (with-current-buffer chat
              (dsh-emacs-interaction--question-requested
               chat "evt-d" "sess-d"
               (list (dsh-emacs-test--interaction-question)) nil)
              (let* ((request (car dsh-emacs-interaction--requests))
                     (question (car (plist-get request :questions)))
                     (chrome (cdr (dsh-emacs-interaction--chrome))))
                (ert-info ((format "%s" "decodes-raw-waterfall-questions"))
                  (should (dsh-protocol-question-p question))
                  (should (equal "Pick one"
                                 (dsh-protocol-question-text question)))
                  (should (equal '("Alpha" "Beta")
                                 (mapcar #'dsh-protocol-question-option-label
                                         (dsh-protocol-question-options question))))
                  (should (string-match-p "1 Alpha" chrome))
                  (should (string-match-p "2 Beta" chrome)))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-interpret-numbers-labels-and-custom ()
  :tags '(dsh-unit)
  (let ((question (dsh-protocol-question--from-alist
                   (dsh-emacs-test--interaction-question
                    "q1" "Pick" '("Alpha" "Beta" "Gamma") t)))
        (single (dsh-protocol-question--from-alist
                 (dsh-emacs-test--interaction-question
                  "q2" "Pick one" '("Alpha" "Beta" "Gamma") nil))))
    (ert-info ((format "%s" "interpret-skip"))
      (should (equal '(skip . nil)
                     (dsh-emacs-interaction--interpret question ""))))
    (ert-info ((format "%s" "interpret-numbers-in-option-order"))
      (should (equal '(labels . ("Alpha" "Gamma"))
                     (dsh-emacs-interaction--interpret question "3, 1"))))
    (ert-info ((format "%s" "interpret-labels"))
      (should (equal '(labels . ("Beta"))
                     (dsh-emacs-interaction--interpret single "Beta"))))
    (ert-info ((format "%s" "interpret-custom"))
      (should (equal '(custom . "make it blue")
                     (dsh-emacs-interaction--interpret
                      single "make it blue"))))))

(ert-deftest dsh-emacs-test-interaction-single-select-click-submits ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-submit*" "sess-s"))
        (sent nil))
    (unwind-protect
        (let ((dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs-composer--row-width)
                     (lambda () 80))
                    ((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (_c e o cb)
                       (setq sent (list e o))
                       (funcall cb t t))))
            (with-current-buffer chat
              (dsh-emacs-interaction--question-requested
               chat "evt-s" "sess-s"
               (list (dsh-emacs-test--interaction-question)) nil)
              (let* ((request (car dsh-emacs-interaction--requests))
                     (id (plist-get request :id)))
                (dsh-emacs-interaction--stage-option id 0 2)
                (ert-info ((format "%s" "single-select-click-submits"))
                  (should (string-empty-p (dsh-emacs-interaction--input-text)))
                  (should (equal "evt-s" (car sent)))
                  (should (equal '((kind . "result")
                                   (value . ((answers .
                                                      (((id . "q1")
                                                        (selected "Beta")))))))
                                 (cadr sent))))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-multi-select-click-stages ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-multi*" "sess-m"))
        (sent nil))
    (unwind-protect
        (let ((dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs-composer--row-width)
                     (lambda () 80))
                    ((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (_c e o cb)
                       (setq sent (list e o))
                       (funcall cb t t))))
            (with-current-buffer chat
              (dsh-emacs-interaction--question-requested
               chat "evt-m" "sess-m"
               (list (dsh-emacs-test--interaction-question
                      "q1" "Pick many" '("Alpha" "Beta" "Gamma") t))
               nil)
              (let* ((request (car dsh-emacs-interaction--requests))
                     (id (plist-get request :id)))
                (dsh-emacs-interaction--stage-option id 0 1)
                (dsh-emacs-interaction--stage-option id 0 3)
                (should (equal "1, 3" (dsh-emacs-interaction--input-text)))
                (should (null sent))
                (should (dsh-emacs-interaction--submit-pending))
                (ert-info ((format "%s" "multi-select-click-stages"))
                  (should (equal "evt-m" (car sent)))
                  (should (equal '((kind . "result")
                                   (value . ((answers .
                                                      (((id . "q1")
                                                        (selected "Alpha" "Gamma")))))))
                                 (cadr sent))))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-empty-input-skips ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-skip*" "sess-k"))
        (sent nil))
    (unwind-protect
        (let ((dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (_c e o cb)
                       (setq sent (list e o))
                       (funcall cb t t))))
            (with-current-buffer chat
              (dsh-emacs-interaction--question-requested
               chat "evt-k" "sess-k"
               (list (dsh-emacs-test--interaction-question)) nil)
              (dsh-emacs--clear-input)
              (should (dsh-emacs-interaction--submit-pending))
              (ert-info ((format "%s" "empty-input-skips"))
                (should (equal '((kind . "result")
                                 (value . ((answers .
                                                    (((id . "q1")
                                                      (selected . [])))))))
                               (cadr sent)))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-approval-allow-and-reject ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-ap*" "sess-a"))
        (sent nil))
    (unwind-protect
        (let ((dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (_c e o cb)
                       (push (list e o) sent)
                       (funcall cb t t))))
            (with-current-buffer chat
              (dsh-emacs-interaction--approval-requested
               chat "evt-a1" "sess-a"
               (dsh-protocol-approval-request--from-alist
                '((toolName . "Bash") (reason . "rm") (callId . "c-a1"))))
              (dsh-emacs-interaction-allow)
              (dsh-emacs-interaction--approval-requested
               chat "evt-a2" "sess-a"
               (dsh-protocol-approval-request--from-alist
                '((toolName . "Bash") (reason . "rm2") (callId . "c-a2"))))
              (dsh-emacs-interaction-decline)
              (ert-info ((format "%s" "approval-allow-and-reject"))
                (should (equal '(("evt-a2" ((kind . "result")
                                            (value . "rejected")))
                                 ("evt-a1" ((kind . "result")
                                            (value . "allowed-once"))))
                               sent))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-approval-empty-send-errors ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-ae*" "sess-ae")))
    (unwind-protect
        (let ((dsh-emacs-enable-notifications nil))
          (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                     (lambda (&rest _) nil)))
            (with-current-buffer chat
              (dsh-emacs-interaction--approval-requested
               chat "evt-ae" "sess-ae"
               (dsh-protocol-approval-request--from-alist
                '((toolName . "Bash") (reason . "rm") (callId . "c-ae"))))
              (dsh-emacs--clear-input)
              (should-error (dsh-emacs-interaction--submit-pending)
                            :type 'user-error))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-timed-withdraw-becomes-late ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-late*" "sess-l"))
        (rpc nil))
    (unwind-protect
        (let ((dsh-emacs--chat-buffers (make-hash-table :test 'equal))
              (dsh-emacs-enable-notifications nil))
          (puthash "sess-l" chat dsh-emacs--chat-buffers)
          (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs-events-open-stream)
                     (lambda (&rest _) (cons 'proc "stream-1")))
                    ((symbol-function 'dsh-emacs-events-close-stream)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs--rpc-async)
                     (lambda (method args cb)
                       (setq rpc (list method args))
                       (funcall cb t t))))
            (with-current-buffer chat
              (let ((dsh-emacs--event-process
                     (make-pipe-process :name "ix-late" :noquery t)))
                (unwind-protect
                    (progn
                      (dsh-emacs-interaction--question-requested
                       chat "evt-l" "sess-l"
                       (list (dsh-emacs-test--interaction-question))
                       (dsh-protocol-question-wait--from-alist
                        '((callId . "call-l") (timed . t))))
                      (should (eq 'pending
                                  (plist-get (car dsh-emacs-interaction--requests)
                                             :state)))
                      (dsh-emacs-interaction--withdrawn "evt-l")
                      (let ((request (car dsh-emacs-interaction--requests)))
                        (ert-info ((format "%s" "timed-withdraw-becomes-late"))
                          (should (equal "call:call-l"
                                         (plist-get request :id)))
                          (should (eq 'late (plist-get request :state)))))
                      (dsh-emacs--clear-input)
                      (goto-char dsh-emacs--input-marker)
                      (insert "2")
                      (should (dsh-emacs-interaction--submit-pending))
                      (ert-info ((format "%s" "late-submit-uses-userquestions-answer"))
                        (should (equal "userQuestions/answer" (car rpc)))
                        (should (equal "call-l"
                                       (alist-get 'callId (cadr rpc))))))
                  (when (process-live-p dsh-emacs--event-process)
                    (delete-process dsh-emacs--event-process)))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-pending-p-and-reload-guard ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-pend*" "sess-p"))
        (dsh-emacs--chat-buffers (make-hash-table :test 'equal)))
    (unwind-protect
        (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                   (lambda (&rest _) nil)))
          (puthash "sess-p" chat dsh-emacs--chat-buffers)
          (with-current-buffer chat
            (should-not (dsh-emacs-interaction--pending-p))
            (dsh-emacs-interaction--question-requested
             chat "evt-p" "sess-p"
             (list (dsh-emacs-test--interaction-question)) nil)
            (should (dsh-emacs-interaction--pending-p))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-wraps-question-text-and-packs-options ()
  :tags '(dsh-unit)
  (let* ((chat (dsh-emacs-test--interaction-chat " *ix-wrap*" "sess-w"))
         (url (concat "https://project.feishu.cn/b/auth/mcp"
                      "?channel=meegle-cli&mode=device&usercode=VMQVZ-G2SJZ"))
         (text (concat "Open this link to finish Meegle login: " url))
         (question `((id . "q1")
                     (question . ,text)
                     (header . "Login")
                     (options . (((label . "Done")
                                  (description . "Continue"))
                                 ((label . "Retry with a longer option label")
                                  (description . "Another path")))))))
    (unwind-protect
        (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dsh-emacs-composer--row-width)
                   ;; Narrow enough that the URL hard-breaks and the two
                   ;; option cells cannot share one Composer row.
                   (lambda () 40)))
          (with-current-buffer chat
            (dsh-emacs-interaction--question-requested
             chat "evt-w" "sess-w" (list question) nil)
            (let* ((chrome (cdr (dsh-emacs-interaction--chrome)))
                   ;; Hard-break continuations omit indent, so joining on
                   ;; newlines restores the original URL for copy/paste.
                   (flat (replace-regexp-in-string "\n" "" chrome))
                   (url-pos (string-match "https://project\\.feishu" chrome)))
              (ert-info ((format "%s" "wraps-question-text-and-packs-options"))
                (should (string-match-p (regexp-quote url) flat))
                (should-not (string-match-p "project\\.feishu…" chrome))
                (should (string-match-p "1 Done" chrome))
                (should (string-match-p
                         "2 Retry with a longer option label" chrome))
                (should (string-match-p "1 Done\n   2 Retry" chrome))
                (should url-pos)
                (should (equal url
                               (get-text-property
                                url-pos 'dsh-emacs-interaction-url chrome)))
                ;; A hard-broken continuation fragment keeps the same URL.
                (let ((cont (and url-pos
                                 (string-match "\n" chrome url-pos))))
                  (should cont)
                  (should (equal url
                                 (get-text-property
                                  (1+ cont)
                                  'dsh-emacs-interaction-url chrome))))))))
      (when (buffer-live-p chat)
        (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-interaction-replay-dedupes-event-and-call ()
  :tags '(dsh-unit)
  (let ((chat (dsh-emacs-test--interaction-chat " *ix-dedup*" "sess-u"))
        (wait (dsh-protocol-question-wait--from-alist
               '((callId . "call-u") (timed . t)))))
    (unwind-protect
        (cl-letf (((symbol-function 'dsh-emacs-notify--post)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dsh-emacs-events-open-stream)
                   (lambda (&rest _) (cons 'proc "stream")))
                  ((symbol-function 'dsh-emacs-events-close-stream)
                   (lambda (&rest _) nil)))
          (with-current-buffer chat
            (let ((dsh-emacs--event-process
                   (make-pipe-process :name "ix-dedup" :noquery t)))
              (unwind-protect
                  (progn
                    (dsh-emacs-interaction--question-requested
                     chat "evt-u" "sess-u"
                     (list (dsh-emacs-test--interaction-question))
                     wait)
                    ;; Same event id is a replay.
                    (dsh-emacs-interaction--question-requested
                     chat "evt-u" "sess-u"
                     (list (dsh-emacs-test--interaction-question))
                     wait)
                    ;; Same timed call with a different event id is also a
                    ;; duplicate while the first form is still pending.
                    (dsh-emacs-interaction--question-requested
                     chat "evt-u2" "sess-u"
                     (list (dsh-emacs-test--interaction-question))
                     wait)
                    (ert-info ((format "%s" "replay-dedupes-event-and-call"))
                      (should (= 1 (length dsh-emacs-interaction--requests)))))
                (when (process-live-p dsh-emacs--event-process)
                  (delete-process dsh-emacs--event-process))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

;;; dsh-test-interaction.el ends here

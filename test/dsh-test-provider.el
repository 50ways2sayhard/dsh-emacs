;;; dsh-test-provider.el --- Provider characterization tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

;;; Code:

(require 'dsh-test-support)
(require 'dsh-emacs-provider)

(defun dsh-emacs-test-provider--section (&optional profiles)
  "Return a typed provider settings fixture containing wire PROFILES."
  (let ((section
         (dsh-protocol-provider-settings--from-alist
          `((ns . "llm-fixture") (revision . 37)
            (value . ((providers . ,profiles)))))))
    (setf (dsh-protocol-provider-settings-protocols section)
          '("openai-completions" "anthropic-messages"))
    section))

(ert-deftest dsh-emacs-test-provider-new-custom-route-orders-writes ()
  :tags '(dsh-unit)
  (let ((section (dsh-emacs-test-provider--section))
        (choices '("fixture-route" "anthropic-messages"))
        (answers '(" https://fixture.invalid/v1 "
                   "model-b, model-a,model-b  model-c"))
        calls callback messages)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () "http://fixture.invalid"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method args done)
                 (push (list method args) calls)
                 (setq callback done)))
              ((symbol-function 'completing-read)
               (lambda (&rest _) (pop choices)))
              ((symbol-function 'read-string)
               (lambda (&rest _) (pop answers)))
              ((symbol-function 'read-passwd)
               (lambda (&rest _) " synthetic-custom-key "))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (dsh-emacs-provider--choose "http://fixture.invalid" (list section) nil)
      (should (equal calls
                     '(("credentials/describe"
                        ((refs . ["FIXTURE_ROUTE_API_KEY"]))))))
      (funcall callback t
               '(("FIXTURE_ROUTE_API_KEY" . ((writable . t)))))
      (should (= (length calls) 2))
      (should (equal
               (car calls)
               '("settings/mutate"
                 ((ns . "llm-fixture") (expectedRevision . 37)
                  (ops . [((op . "set")
                           (path . ["providers" "fixture-route"])
                           (value . ((apiKeyEnv . "FIXTURE_ROUTE_API_KEY")
                                     (models . [((id . "model-b"))
                                                ((id . "model-a"))
                                                ((id . "model-c"))])
                                     (api . "anthropic-messages")
                                     (baseURL . "https://fixture.invalid/v1"))))])))))
      (should-not messages)
      (funcall callback t nil)
      (should (= (length calls) 3))
      (should (equal (car calls)
                     '("credentials/set"
                       ((ref . "FIXTURE_ROUTE_API_KEY")
                        (value . "synthetic-custom-key")))))
      (should-not messages)
      (funcall callback t nil)
      (should (equal messages
                     '("Provider fixture-route saved; use C-c C-m to select a model"))))))

(ert-deftest dsh-emacs-test-provider-existing-route-updates-only-endpoint ()
  :tags '(dsh-unit)
  (let* ((section
          (dsh-emacs-test-provider--section
           '((fixture-route . ((baseURL . "https://old.invalid/v1")
                              (apiKeyEnv . "SYNTHETIC_EXISTING_REF"))))))
         (entry
          (dsh-protocol-configurable-provider--from-alist
           '((provider . "fixture-route") (settingsNs . "llm-fixture")
             (settingsPath . ["providers" "fixture-route"])
             (declared . t))))
         calls callback prompts)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () "http://fixture.invalid"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method args done)
                 (push (list method args) calls)
                 (setq callback done)))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "fixture-route"))
              ((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (push prompt prompts)
                 " https://new.invalid/v2 "))
              ((symbol-function 'read-passwd) (lambda (&rest _) "  "))
              ((symbol-function 'message) #'ignore))
      (dsh-emacs-provider--choose
       "http://fixture.invalid" (list section) (list entry))
      (should (equal calls
                     '(("credentials/describe"
                        ((refs . ["SYNTHETIC_EXISTING_REF"]))))))
      (funcall callback t
               '(("SYNTHETIC_EXISTING_REF" . ((writable . t)
                                             (configured . t)))))
      (should (equal prompts '("Base URL (empty keeps current): ")))
      (should (equal
               (car calls)
               '("settings/mutate"
                 ((ns . "llm-fixture") (expectedRevision . 37)
                  (ops . [((op . "set")
                           (path . ["providers" "fixture-route" "baseURL"])
                           (value . "https://new.invalid/v2"))])))))
      (funcall callback t nil)
      (should (= (length calls) 2)))))

(ert-deftest dsh-emacs-test-provider-new-catalog-route-sends-empty-object ()
  :tags '(dsh-unit)
  (let ((section (dsh-emacs-test-provider--section)) calls callback)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () "http://fixture.invalid"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method args done)
                 (push (list method args) calls)
                 (setq callback done)))
              ((symbol-function 'read-string) (lambda (&rest _) ""))
              ((symbol-function 'completing-read)
               (lambda (&rest _) (ert-fail "Catalog must not prompt for protocol")))
              ((symbol-function 'read-passwd) (lambda (&rest _) ""))
              ((symbol-function 'message) #'ignore))
      (dsh-emacs-provider--edit
       "http://fixture.invalid" section "catalog-route" nil nil
       "CATALOG_ROUTE_API_KEY"
       (dsh-protocol-provider-credential--from-alist
        '(("CATALOG_ROUTE_API_KEY" . ((writable . t))))
        "CATALOG_ROUTE_API_KEY"))
      (should (= (length calls) 1))
      (should (equal (caar calls) "settings/mutate"))
      (let* ((args (cadar calls))
             (ops (alist-get 'ops args))
             (op (aref ops 0))
             (value (alist-get 'value op)))
        (should (equal (alist-get 'ns args) "llm-fixture"))
        (should (equal (alist-get 'expectedRevision args) 37))
        (should (vectorp ops))
        (should (= (length ops) 1))
        (should (equal (alist-get 'op op) "set"))
        (should (equal (alist-get 'path op) ["providers" "catalog-route"]))
        (should (hash-table-p value))
        (should (= (hash-table-count value) 0))
        (should (equal (dsh-protocol-write-json value) "{}")))
      (funcall callback t nil)
      (should (= (length calls) 1)))))

(ert-deftest dsh-emacs-test-provider-unchanged-route-sends-empty-ops ()
  :tags '(dsh-unit)
  (let ((section (dsh-emacs-test-provider--section))
        (profile
         (dsh-protocol-provider-profile--from-alist
          '((baseURL . "https://old.invalid/v1")
            (apiKeyEnv . "SYNTHETIC_EXISTING_REF"))))
        calls callback)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () "http://fixture.invalid"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method args done)
                 (push (list method args) calls)
                 (setq callback done)))
              ((symbol-function 'read-string) (lambda (&rest _) ""))
              ((symbol-function 'read-passwd)
               (lambda (&rest _) (ert-fail "Read-only credentials must not prompt")))
              ((symbol-function 'message) #'ignore))
      (dsh-emacs-provider--edit
       "http://fixture.invalid" section "fixture-route" profile t
       "SYNTHETIC_EXISTING_REF"
       (dsh-protocol-provider-credential--from-alist
        '(("SYNTHETIC_EXISTING_REF" . ((writable . :json-false)
                                      (configured . t))))
        "SYNTHETIC_EXISTING_REF"))
      (should (equal calls
                     '(("settings/mutate"
                        ((ns . "llm-fixture") (expectedRevision . 37)
                         (ops . []))))))
      (funcall callback t nil)
      (should (= (length calls) 1)))))

(ert-deftest dsh-emacs-test-provider-settings-cas-failure-stops-credential-write ()
  :tags '(dsh-unit)
  (let ((section (dsh-emacs-test-provider--section)) calls callback messages)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () "http://fixture.invalid"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method args done)
                 (push (list method args) calls)
                 (setq callback done)))
              ((symbol-function 'read-string) (lambda (&rest _) ""))
              ((symbol-function 'read-passwd)
               (lambda (&rest _) "synthetic-cas-key"))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (dsh-emacs-provider--edit
       "http://fixture.invalid" section "catalog-route" nil nil
       "CATALOG_ROUTE_API_KEY"
       (dsh-protocol-provider-credential--from-alist
        '(("CATALOG_ROUTE_API_KEY" . ((writable . t))))
        "CATALOG_ROUTE_API_KEY"))
      (should (equal (mapcar #'car calls) '("settings/mutate")))
      (should-not messages)
      (funcall callback nil '((code . "REVISION_CONFLICT")
                              (message . "fixture revision mismatch")))
      (should (equal (mapcar #'car calls) '("settings/mutate")))
      (should (equal messages
                     '("Provider configuration failed: fixture revision mismatch")))
      (should-not (string-match-p "synthetic-cas-key" (car messages))))))

(ert-deftest dsh-emacs-test-provider-credential-failure-redacts-diagnostic ()
  :tags '(dsh-unit)
  (let ((section (dsh-emacs-test-provider--section)) calls callback messages)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () "http://fixture.invalid"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method args done)
                 (push (list method args) calls)
                 (setq callback done)))
              ((symbol-function 'read-string) (lambda (&rest _) ""))
              ((symbol-function 'read-passwd)
               (lambda (&rest _) "synthetic-rejected-key"))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (dsh-emacs-provider--edit
       "http://fixture.invalid" section "catalog-route" nil nil
       "CATALOG_ROUTE_API_KEY"
       (dsh-protocol-provider-credential--from-alist
        '(("CATALOG_ROUTE_API_KEY" . ((writable . t))))
        "CATALOG_ROUTE_API_KEY"))
      (should (equal (mapcar #'car calls) '("settings/mutate")))
      (funcall callback t nil)
      (should (equal (mapcar #'car (reverse calls))
                     '("settings/mutate" "credentials/set")))
      (should (equal (car calls)
                     '("credentials/set"
                       ((ref . "CATALOG_ROUTE_API_KEY")
                        (value . "synthetic-rejected-key")))))
      (should-not messages)
      (funcall callback nil
               '((code . "STORE_DENIED")
                 (message . "server echoed synthetic-rejected-key")))
      (should (= (length calls) 2))
      (should (equal messages
                     '("Provider catalog-route saved, API key not confirmed; run dsh-emacs-add-provider again to retry: STORE_DENIED")))
      (should-not (string-match-p "synthetic-rejected-key" (car messages)))
      (should-not (string-match-p "server echoed" (car messages))))))

(ert-deftest dsh-emacs-test-provider-server-change-blocks-pending-callback ()
  :tags '(dsh-unit)
  (let ((section (dsh-emacs-test-provider--section))
        (server "http://fixture.invalid") calls callback messages)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () server))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method args done)
                 (push (list method args) calls)
                 (setq callback done)))
              ((symbol-function 'read-string) (lambda (&rest _) ""))
              ((symbol-function 'read-passwd)
               (lambda (&rest _) "synthetic-stale-key"))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (dsh-emacs-provider--edit
       server section "catalog-route" nil nil "CATALOG_ROUTE_API_KEY"
       (dsh-protocol-provider-credential--from-alist
        '(("CATALOG_ROUTE_API_KEY" . ((writable . t))))
        "CATALOG_ROUTE_API_KEY"))
      (should (equal (mapcar #'car calls) '("settings/mutate")))
      (setq server "http://other.invalid")
      (funcall callback t nil)
      (should (equal (mapcar #'car calls) '("settings/mutate")))
      (should (equal messages
                     '("Provider operation finished: server changed; check the original server")))
      (should-not (string-match-p "synthetic-stale-key" (car messages))))))

(ert-deftest dsh-emacs-test-provider-server-change-during-prompt-blocks-write ()
  :tags '(dsh-unit)
  (let ((section (dsh-emacs-test-provider--section))
        (server "http://fixture.invalid") calls)
    (cl-letf (((symbol-function 'dsh-emacs--server-base-url)
               (lambda () server))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (&rest args) (push args calls)))
              ((symbol-function 'read-string) (lambda (&rest _) ""))
              ((symbol-function 'read-passwd)
               (lambda (&rest _)
                 (setq server "http://other.invalid")
                 "synthetic-changed-server-key")))
      (let ((err
             (should-error
              (dsh-emacs-provider--edit
               server section "catalog-route" nil nil "CATALOG_ROUTE_API_KEY"
               (dsh-protocol-provider-credential--from-alist
                '(("CATALOG_ROUTE_API_KEY" . ((writable . t))))
                "CATALOG_ROUTE_API_KEY"))
              :type 'user-error)))
        (should (equal (error-message-string err)
                       "Provider configuration cancelled: server changed")))
      (should-not calls))))

(provide 'dsh-test-provider)
;;; dsh-test-provider.el ends here

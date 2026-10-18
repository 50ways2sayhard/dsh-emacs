;;; dsh-test-rpc.el --- Rpc tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)
(require 'url-auth)
(require 'url-http)

;; --- Test 14: RPC JSON booleans and empty payload ---
(ert-deftest dsh-emacs-test-rpc-rpc-empty-payload-is-object ()
  :tags '(dsh-unit)
  (let ((request (dsh-emacs--wrap-request "session/list" nil)))
    (ert-info ((format "%s" "rpc-empty-payload-is-object"))
      (should (string-match-p "\"payload\":{\"args\":{}}" request)))))

;; --- Test 14b: session/list carries the _request argument (real 0.1.2
;; descriptor) ---
;; In 0.1.2-rc.1 the sole argument of `session/list' is named `_request' (an empty
;; list request object), not `request' as in the other session methods. Sending
;; `{}' is rejected by the server (`missing "_request"'); args must carry the
;; `_request' key with value `{}'.
(ert-deftest dsh-emacs-test-rpc-session-list-args-carries-request ()
  :tags '(dsh-unit)
  (let* ((args (dsh-emacs--session-list-args))
         (wrap (dsh-emacs--wrap-request "session/list" args)))
    (ert-info ((format "%s" "session-list-args-carries-_request"))
      (should (and (= 1 (length args))
                   (eq '_request (car (car args))))))
    (ert-info ((format "%s" "session-list-wrap-encodes-_request-object"))
      (should (string-match-p "\"args\":{\"_request\":{}}" wrap)))))

(ert-deftest dsh-emacs-test-rpc-rpc-false-result-is-error ()
  :tags '(dsh-unit)
  (let* ((response (json-read-from-string
                    "{\"result\":{\"ok\":false,\"error\":{\"code\":\"bad-request\"}}}"))
         (unwrapped (dsh-protocol-rpc-result--from-alist response)))
    (ert-info ((format "%s" "rpc-false-result-is-error"))
      (should (and (not (car unwrapped))
                   (equal (cdr (assq 'code (cdr unwrapped))) "bad-request"))))))

;; Native and Lisp wire readers must preserve the same protocol shapes,
;; independently of a user's json.el customization.
(ert-deftest dsh-emacs-test-rpc-wire-json-string-shapes-native-case ()
  :tags '(dsh-unit)
  (dolist (native (if (and (fboundp 'json-available-p) (json-available-p))
                      '(t nil) '(nil)))
    (let ((json-object-type 'hash-table)
          (json-array-type 'list)
          (json-key-type 'string)
          (json-null :custom-null)
          (json-false :custom-false)
          (json (concat "{\"items\":[{\"sessionId\":\"s\",\"title\":\"中文 😊\","
                        "\"blank\":false,\"running\":true,\"value\":null,"
                        "\"array\":[],\"object\":{},\"count\":42,\"ratio\":1.25}]}"))
          (expected '((items . [((sessionId . "s") (title . "中文 😊")
                                 (blank . :json-false) (running . t) (value)
                                 (array . []) (object) (count . 42)
                                 (ratio . 1.25))]))))
      (cl-letf (((symbol-function 'json-available-p) (lambda () native)))
        (ert-info ((format "%s" (format "wire-json-string-shapes-native-%s" native)))
          (should (equal expected (dsh-protocol-read-json json))))
        (with-temp-buffer
          (insert "prefix " json)
          (goto-char 8)
          (ert-info ((format "%s" (format "wire-json-buffer-shapes-native-%s" native)))
            (should (equal expected (dsh-protocol-read-json)))
            (should (eobp))))
        (dolist (bad '("{\"items\":[" "{\"ok\":tru}" "\"unterminated"))
          (ert-info ((format "%s" (format "wire-json-rejects-malformed-native-%s" native)))
            (should (condition-case nil (progn (dsh-protocol-read-json bad) nil)
                      (error t)))
            (should (with-temp-buffer
                      (insert bad)
                      (goto-char (point-min))
                      (condition-case nil (progn (dsh-protocol-read-json) nil)
                        (error t))))))))))

;; --- Test 15: JSON arrays and working directory ---
(ert-deftest dsh-emacs-test-rpc-json-array-and-symbol-keys-supported ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "json-array-and-symbol-keys-supported"))
    (should (and (equal '(a b) (dsh-emacs--sequence-list [a b]))
                 (equal "assistant/message"
                        (dsh-protocol--field "type"
                                                '((type . "assistant/message"))))))))

(ert-deftest dsh-emacs-test-rpc-client-time-zone-is-iana ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "client-time-zone-is-iana"))
    (should (and (stringp (dsh-emacs--client-time-zone))
                 (not (string-empty-p (dsh-emacs--client-time-zone)))
                 (dsh-emacs--valid-iana-time-zone-p
                  (dsh-emacs--client-time-zone))))))

(ert-deftest dsh-emacs-test-rpc-ambiguous-time-zone-is-replaced ()
  :tags '(dsh-unit)
  (let ((process-environment (cons "TZ=CST" process-environment)))
    (ert-info ((format "%s" "ambiguous-time-zone-is-replaced"))
      (should (dsh-emacs--valid-iana-time-zone-p
               (dsh-emacs--client-time-zone))))))

;; --- Test 18: UTF-8 response decoding ---
(ert-deftest dsh-emacs-test-rpc-rpc-response-decodes-utf8 ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert (encode-coding-string "你好 😊" 'utf-8))
    (goto-char (point-min))
    (dsh-emacs--decode-response-body)
    (ert-info ((format "%s" "rpc-response-decodes-utf8"))
      (should (string= (buffer-string) "你好 😊")))))

;; --- Test 93f: http-error-hint gives auth guidance for 401 ---
(ert-deftest dsh-emacs-test-rpc-http-error-hint-401-mentions-auth ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "http-error-hint-401-mentions-auth"))
    (should (string-match-p "401"
                            (dsh-emacs--http-error-hint '(error http 401))))))

;; RPC auth failure does not enter Basic interaction; the sync path must read the
;; HTTP status rather than parse the error page. Async responses are dispatched
;; after the request's dynamic bindings have exited, mimicking url's buffer-local
;; configuration.
(ert-deftest dsh-emacs-test-rpc-rpc-case-http-case-auth-result ()
  :tags '(dsh-unit)
  (dolist (mode '(sync async))
    (dolist (status '(200 401 403))
      (let ((dsh-emacs-base-url "http://rpc.example:3080")
            (dsh-emacs--server-auth-cookie "dsh-auth-RPC=cached")
            (url-request-noninteractive nil)
            (url-registered-auth-schemes nil)
            (response nil)
            (pending nil)
            (request-headers nil)
            (inhibited-cookies nil)
            (challenges nil)
            (result 'not-called))
        (url-register-auth-scheme "basic" nil 4)
        (cl-labels
            ((make-response (url)
               (setq request-headers url-request-extra-headers
                     response (generate-new-buffer " *dsh-rpc-auth-test*"))
               (with-current-buffer response
                 (setq-local url-http-response-status status)
                 (setq-local url-current-object (url-generic-parse-url url))
                 (setq-local url-http-extra-headers request-headers)
                 (setq-local url-http-noninteractive url-request-noninteractive)
                 (insert (format "HTTP/1.1 %d Test\n\n" status)
                         (if (= status 200)
                             "{\"result\":{\"ok\":true,\"value\":\"accepted\"}}"
                           "Authentication failed")))
               response)
             (authenticate ()
               (when (= status 401)
                 (with-current-buffer response
                   (url-http-handle-authentication nil)))))
          (cl-letf (((symbol-function 'url-get-authentication)
                     (lambda (_url _realm type prompt &rest _)
                       (push (list type prompt (url-interactive-p)) challenges)
                       nil))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (url &optional _silent inhibit-cookies &rest _)
                       (setq inhibited-cookies inhibit-cookies)
                       (make-response url)
                       (authenticate)
                       response))
                    ((symbol-function 'url-retrieve)
                     (lambda (url callback &optional _args _silent inhibit-cookies)
                       (setq pending callback
                             inhibited-cookies inhibit-cookies)
                       (make-response url))))
            (unwind-protect
                (progn
                  (if (eq mode 'sync)
                      (setq result (dsh-emacs--rpc-request "session/list" nil))
                    (dsh-emacs--rpc-async
                     "session/list" nil
                     (lambda (ok value) (setq result (cons ok value))))
                    (authenticate)
                    (with-current-buffer response
                      (funcall pending (when (>= status 400)
                                         (list :error (list 'error 'http status))))))
                  (ert-info ((format "%s" (format "rpc-%s-http-%s-auth-result" mode status)))
                    (should (equal result (if (= status 200) '(t . "accepted") '(nil))))
                    (should (equal (cdr (assoc "Cookie" request-headers))
                                   "dsh-auth-RPC=cached"))
                    (should (eq inhibited-cookies t))
                    (should (equal challenges (and (= status 401) '(("basic" t nil)))))
                    (should (equal dsh-emacs--server-auth-cookie
                                   (unless (= status 401) "dsh-auth-RPC=cached")))
                    (should (not (buffer-live-p response)))))
              (when (buffer-live-p response) (kill-buffer response)))))))))

(provide 'dsh-test-rpc)
;;; dsh-test-rpc.el ends here

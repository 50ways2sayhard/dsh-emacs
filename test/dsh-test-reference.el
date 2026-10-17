;;; dsh-test-reference.el --- Reference tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)
(defvar corfu-auto)

;; ---------------------------------------------------------------------------
;; @ reference (dsh-emacs-reference.el)
;; ---------------------------------------------------------------------------
(defun dsh-test-reference-reset ()
  "Reset the buffer-local @ reference cache state (current buffer)."
  (setq-local dsh-emacs--reference-candidates nil
              dsh-emacs--reference-query nil
              dsh-emacs--reference-requested nil
              dsh-emacs--reference-inflight nil
              dsh-emacs--reference-fetch-gen 0
              dsh-emacs--reference-files nil
              dsh-emacs--reference-sessions nil
              dsh-emacs--reference-pop-token nil))

;; A short @ token must not copy the entire preceding draft on each keypress.
(ert-deftest dsh-emacs-test-reference-active-token-copies-only-the-token ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (insert (make-string 100000 ?x) " @src/file")
    (let ((copied 0)
          (substring (symbol-function 'buffer-substring-no-properties)))
      (cl-letf (((symbol-function 'buffer-substring-no-properties)
                 (lambda (start end)
                   (setq copied (+ copied (- end start)))
                   (funcall substring start end))))
        (ert-info ((format "%s" "active-token-copies-only-the-token"))
          (should (equal (dsh-emacs-reference--active-token)
                         '("@src/file" "src/file" nil)))
          (should (<= copied 20)))))))

;; --- syntax: at-token aligned with web grammar.ts activeAtToken ---
(ert-deftest dsh-emacs-test-reference-at-token ()
  :tags '(dsh-unit)
  (dolist (case '(("bare-at" "@" ("@" "" nil))
                  ("after-whitespace" "hi @fo" ("@fo" "fo" nil))
                  ("quoted-path" "@\"my dir/te" ("@\"my dir/te" "my dir/te" t))
                  ("dir-trailing-slash" "a @src/" ("@src/" "src/" nil))
                  ("email-not-a-trigger" "mail@example" nil)
                  ("mid-word-not-a-trigger" "foo/bar" nil)
                  ("trailing-space-closes-token" "@done " nil)
                  ("quoted-at-is-path-text" "@\"a @b" ("@\"a @b" "a @b" t))
                  ("quote-in-other-token" "x@\"a @b" ("@b" "b" nil))
                  ("multiline-quoted-path" "@\"a\nb" ("@\"a\nb" "a\nb" t))
                  ("last-quote-opens-token" "@\"a @\"b" ("@\"b" "b" t))
                  ("closed-quote-falls-back" "@\"done\"" ("@\"done\"" "\"done\"" nil))
                  ("empty-input" "" nil)))
    (pcase-let ((`(,name ,text ,expected) case))
      (with-temp-buffer
        (insert "@\"outside-input ")
        (let ((start (point)))
          (insert text)
          (let ((end (point)))
            (insert " after-cursor")
            (goto-char start)
            (ert-info ((format "%s" (concat "at-token-" name)))
              (should (equal (dsh-emacs-reference--at-token start end) expected))
              (should (= (point) start)))))))))

;; --- syntax: formatFileMention aligned with web formatFileMention ---
(ert-deftest dsh-emacs-test-reference-format-file-mention-cases ()
  :tags '(dsh-unit)
  (let ((cases
         '(("README.md" "file" nil "@README.md")
           ("src" "directory" nil "@src/")
           ("my dir/a b" "file" nil "@\"my dir/a b\"")
           ("src" "directory" t "@\"src/")
           ("a b" "file" t "@\"a b\""))))
    (ert-info ((format "%s" "format-file-mention-cases"))
      (should (cl-every
               (lambda (c)
                 (string= (apply #'dsh-emacs-reference--format-file-mention
                                 (butlast c))
                          (car (last c))))
               cases)))))

(ert-deftest dsh-emacs-test-reference-format-file-mention-rejects-control ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "format-file-mention-rejects-control"))
    (should (null (dsh-emacs-reference--format-file-mention "a\x01b" "file")))))

(ert-deftest dsh-emacs-test-reference-format-file-mention-rejects-quote ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "format-file-mention-rejects-quote"))
    (should (null (dsh-emacs-reference--format-file-mention "a\"b" "file")))))

;; --- collect-files: wire array → cache entries, unrepresentable paths skipped;
;; the host sorts directories before files (kindRank directory=0), the client
;; stably groups files first, directories after
(ert-deftest dsh-emacs-test-reference-collect-files-texts-and-kinds ()
  :tags '(dsh-unit)
  (let ((entries
         (dsh-emacs-reference--collect-files
          [((path . "src") (kind . "directory"))
           ((path . "README.md") (kind . "file"))
           ((path . "docs") (kind . "directory"))
           ((path . "bad\x01name") (kind . "file"))])))
    (ert-info ((format "%s" "collect-files-texts-and-kinds"))
      (should (equal (mapcar #'car entries)
                     '("@README.md" "@src/" "@docs/")))
      (should (equal (plist-get (cdr (assoc "@src/" entries)) :kind) 'directory))
      (should (equal (plist-get (cdr (assoc "@README.md" entries)) :path)
                     "README.md"))
      (should (equal (mapcar (lambda (e) (plist-get (cdr e) :path))
                             (cl-remove-if-not
                              (lambda (e) (eq (plist-get (cdr e) :kind) 'directory))
                              entries))
                     '("src" "docs"))))))

;; --- collect-sessions: mention is the main text, candidates without a mention
;; are skipped ---
(ert-deftest dsh-emacs-test-reference-collect-sessions-mention-and-drop ()
  :tags '(dsh-unit)
  (let ((entries
         (dsh-emacs-reference--collect-sessions
          [((sessionId . "s1")
            (label . "My Talk")
            (cwd . "/work/a")
            (sameWorkspace . t)
            (createdAt . 123)
            (mention . "@[My Talk](dsh-session:cyJpZCI6InMxIn0)"))
           ((sessionId . "s2") (label . "x"))])))
    (ert-info ((format "%s" "collect-sessions-mention-and-drop"))
      (should (equal (mapcar #'car entries)
                     '("@[My Talk](dsh-session:cyJpZCI6InMxIn0)")))
      (should (equal (plist-get (cdr (car entries)) :label) "My Talk"))
      (should (equal (plist-get (cdr (car entries)) :session-id) "s1"))
      (should (equal (plist-get (cdr (car entries)) :same-workspace) t)))))

;; --- combine: by default keep all files and sessions returned by the host ---
(ert-deftest dsh-emacs-test-reference-combine-default-keeps-all-candidates ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs-reference-max-files nil)
         (dsh-emacs-reference-max-sessions nil)
         (files (list (cons "@a" '(:kind file))
                      (cons "@b" '(:kind directory))
                      (cons "@c" '(:kind file))))
         (sessions (list (cons "@s1" '(:kind session))
                         (cons "@s2" '(:kind session)))))
    (ert-info ((format "%s" "combine-default-keeps-all-candidates"))
      (should (= 5 (length (dsh-emacs-reference--combine files sessions)))))))

;; --- combine: files first, sessions after, each truncated to its cap ---
(ert-deftest dsh-emacs-test-reference-combine-order-and-caps ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs-reference-max-files 2)
         (dsh-emacs-reference-max-sessions 1)
         (files (list (cons "@a" '(:kind file :path "a"))
                      (cons "@b" '(:kind file :path "b"))
                      (cons "@c" '(:kind file :path "c"))))
         (sessions (list (cons "@[s1](dsh-session:x)" '(:kind session))
                         (cons "@[s2](dsh-session:y)" '(:kind session))))
         (combined (dsh-emacs-reference--combine files sessions)))
    (ert-info ((format "%s" "combine-order-and-caps"))
      (should (equal (mapcar #'car combined)
                     '("@a" "@b" "@[s1](dsh-session:x)"))))))

;; --- M-x menu: use the ordered completion helper so the framework does not
;; reorder by text ---
(ert-deftest dsh-emacs-test-reference-reference-menu-preserves-file-dir-session-order ()
  :tags '(dsh-unit)
  (let (collection)
    (with-temp-buffer
      (dsh-test-reference-reset)
      (setq dsh-emacs--reference-query ""
            dsh-emacs--reference-candidates
            (list (cons "@file.txt" '(:kind file :path "file.txt"))
                  (cons "@dir/" '(:kind directory :path "dir"))
                  (cons "@[Session](dsh-session:s)" '(:kind session
                                                            :label "Session"))))
      (cl-letf (((symbol-function 'dsh-emacs-server-ensure) (lambda () nil))
                ((symbol-function 'dsh-emacs--active-session-id)
                 (lambda () "sess"))
                ((symbol-function 'dsh-emacs--completing-read-ordered)
                 (lambda (_prompt coll &rest _args)
                   (setq collection coll)
                   nil)))
        (dsh-emacs-reference))
      (ert-info ((format "%s" "reference-menu-preserves-file-dir-session-order"))
        (should (equal (dsh-test-completion-items collection)
                       '("file.txt" "dir/" "Session")))))))

;; --- Corfu active popup: async refresh must not restart native completion ---
(ert-deftest dsh-emacs-test-reference-reference-refresh-leaves-active-corfu-alone ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-corfu-refresh*"))
        (completed nil)
        (native-refreshed nil))
    (unwind-protect
        (with-current-buffer buf
          (insert "@")
          (setq-local dsh-emacs--input-marker (copy-marker (point-min))
                      dsh-emacs--reference-requested ""
                      dsh-emacs--reference-query "")
          (cl-letf (((symbol-function 'get-buffer-window)
                     (lambda (&rest _args) t))
                    ((symbol-function 'run-with-idle-timer)
                     (lambda (_delay _repeat function &rest _args)
                       (funcall function)))
                    ((symbol-function 'completion-at-point)
                     (lambda () (setq completed t)))
                    ((symbol-function 'corfu-auto--complete-deferred)
                     (lambda (&optional _tick) (setq native-refreshed t))))
            (let ((corfu-auto t)
                  (completion-in-region-mode t))
              (dsh-emacs-reference--schedule-popup-refresh))
            (ert-info ((format "%s" "reference-refresh-leaves-active-corfu-alone"))
              (should (null completed))
              (should (null native-refreshed)))
            (let ((corfu-auto t)
                  (completion-in-region-mode nil))
              (dsh-emacs-reference--schedule-popup-refresh))
            (ert-info ((format "%s" "reference-refresh-does-not-reopen-nondirectory-corfu"))
              (should (null native-refreshed))
              (should (null completed)))
            (let ((corfu-auto nil)
                  (completion-in-region-mode nil))
              (dsh-emacs-reference--schedule-popup-refresh))
            ;; Non-corfu has no auto channel (cooperative, like slash): an async
            ;; refresh never opens the completion UI itself — that stays on TAB.
            (ert-info ((format "%s" "reference-refresh-never-opens-noncorfu"))
              (should (null completed)))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- Corfu native table: edit/backspace only filters current candidates, does
;; not start a remote refresh ---
(ert-deftest dsh-emacs-test-reference-reference-corfu-refreshes-query-without-restarting ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-corfu-native-table*"))
        (corfu-auto t)
        (dsh-emacs-reference-fetch-delay 0.15)
        (fetched nil)
        (opened nil)
        (prefetched nil)
        (delay-seen nil))
    (unwind-protect
        (with-current-buffer buf
          (insert "@")
          (setq-local dsh-emacs--input-marker (copy-marker (point-min))
                      dsh-emacs--reference-query "old"
                      dsh-emacs--reference-requested nil
                      dsh-emacs--reference-pop-token nil)
          (cl-letf (((symbol-function 'dsh-emacs--active-session-id)
                     (lambda () "sess"))
                    ((symbol-function 'dsh-emacs-reference--require-cache)
                     (lambda (_session _query) t))
                    ((symbol-function 'dsh-emacs-reference--fetch-query)
                     (lambda (session-id query)
                       (setq fetched (list session-id query))))
                    ((symbol-function 'dsh-emacs-reference--schedule-popup-refresh)
                     (lambda () (setq prefetched t)))
                    ((symbol-function 'completion-at-point)
                     (lambda () (setq opened t)))
                    ((symbol-function 'run-with-idle-timer)
                     (lambda (delay _repeat function &rest _args)
                       (setq delay-seen delay)
                       (funcall function)))
                    ((symbol-function 'get-buffer-window)
                     (lambda (&rest _args) t)))
            (dsh-emacs-reference--auto-complete)
            (dsh-emacs-reference-prefetch "sess")
            (ert-info ((format "%s" "reference-corfu-refreshes-query-without-restarting"))
              (should (equal fetched '("sess" "")))
              (should (null opened))
              (should (null prefetched)))
            ;; A trailing slash is the one Corfu edit that drills remotely.
            (goto-char (point-max))
            (insert "src/")
            (dsh-emacs-reference--auto-complete)
            (ert-info ((format "%s" "reference-corfu-slash-fetches-directory"))
              (should (equal fetched '("sess" "src/")))
              (should (= delay-seen 0)))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- fetch-query: two remotes concurrently, install the cache after both
;; slices land ---
(ert-deftest dsh-emacs-test-reference-fetch-query-both-remotes-called ()
  :tags '(dsh-unit)
  (let ((rpc-calls nil))
    (with-temp-buffer
      (dsh-test-reference-reset)
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (method params cb)
                   (push (list method params) rpc-calls)
                   (cond
                    ((string= method "fileReferences/list")
                     (funcall cb t [((path . "README.md") (kind . "file"))]))
                    ((string= method "sessionReferenceResolver/candidates")
                     (funcall cb t [((sessionId . "s1") (label . "T")
                                     (mention
                                      . "@[T](dsh-session:cyJpZCI6InMxIn0)"))]))
                    (t (funcall cb nil nil))))))
        (setq dsh-emacs--reference-requested "re")
        (dsh-emacs-reference--fetch-query "sess" "re"))
      (ert-info ((format "%s" "fetch-query-both-remotes-called"))
        (should (= 2 (length rpc-calls)))
        (should (cl-every (lambda (m) (member m '("fileReferences/list"
                                                  "sessionReferenceResolver/candidates")))
                          (mapcar #'car rpc-calls))))
      (ert-info ((format "%s" "fetch-query-wire-args-flat"))
        (should (let ((params (cadr (assoc "fileReferences/list" rpc-calls))))
                  (and (null (assq 'args params))
                       (string= (cdr (assq 'agentId params)) "sess")
                       (string= (cdr (assq 'query params)) "re")))))
      (ert-info ((format "%s" "fetch-query-installs-cache"))
        (should (equal dsh-emacs--reference-query "re"))
        (should (null dsh-emacs--reference-inflight))
        (should (equal (mapcar #'car dsh-emacs--reference-candidates)
                       '("@README.md" "@[T](dsh-session:cyJpZCI6InMxIn0)")))))))

;; --- require-cache: first sync fetch; a stale cache keeps answering and does not
;; fetch again ---
(ert-deftest dsh-emacs-test-reference-require-cache-first-trigger-sync ()
  :tags '(dsh-unit)
  (let ((rpc-requests nil))
    (with-temp-buffer
      (dsh-test-reference-reset)
      (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                 (lambda (method params)
                   (push (list method params) rpc-requests)
                   (cond
                    ((string= method "fileReferences/list")
                     (cons t [((path . "F") (kind . "file"))]))
                    ((string= method "sessionReferenceResolver/candidates")
                     (cons t []))
                    (t (cons nil nil))))))
        (let ((ok (dsh-emacs-reference--require-cache "sess" "")))
          (ert-info ((format "%s" "require-cache-first-trigger-sync"))
            (should ok)
            (should (= 2 (length rpc-requests)))
            (should (equal dsh-emacs--reference-query ""))
            (should (equal (mapcar #'car dsh-emacs--reference-candidates) '("@F")))
            (should (equal (cadr (assoc "fileReferences/list" rpc-requests))
                           '((agentId . "sess") (query . ""))))))
        (setq dsh-emacs--reference-requested "F2")
        (let ((stale-len (length rpc-requests)))
          (ert-info ((format "%s" "require-cache-stale-answers-without-fetch"))
            (should (dsh-emacs-reference--require-cache "sess" "F2"))
            (should (= (length rpc-requests) stale-len))))))))

;; --- after finishing a reference (fetch state already reset), typing @ again: no
;; longer eats the narrowed cache, re-fetches the full set. Otherwise the next @
;; would only see the single candidate left by the previous query.
(ert-deftest dsh-emacs-test-reference-post-completion-reopen-refetches-full-list ()
  :tags '(dsh-unit)
  (let ((rpc-requests nil))
    (with-temp-buffer
      (dsh-test-reference-reset)
      ;; Simulate "just finished a reference": query/requested have been cleared by the
      ;; reset, but the cache still holds the result of the previous narrowed query
      ;; (just one freshly selected candidate).
      (setq-local dsh-emacs--reference-query nil
                  dsh-emacs--reference-requested nil
                  dsh-emacs--reference-candidates
                  (list (cons "@just-picked.ts"
                              '(:kind file :path "just-picked.ts"))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                 (lambda (method _params)
                   (push method rpc-requests)
                   (cond
                    ((string= method "fileReferences/list")
                     (cons t [((path . "a.ts") (kind . "file"))
                              ((path . "b.ts") (kind . "file"))]))
                    ((string= method "sessionReferenceResolver/candidates")
                     (cons t []))
                    (t (cons nil nil))))))
        (ert-info ((format "%s" "post-completion-reopen-refetches-full-list"))
          (should (dsh-emacs-reference--require-cache "sess" ""))
          (should (equal (mapcar #'car dsh-emacs--reference-candidates)
                         '("@a.ts" "@b.ts"))))))))

;; --- require-cache: a stale cache keeps answering while in-flight (the popup does
;; not disappear) ---
(ert-deftest dsh-emacs-test-reference-require-cache-stale-answers-while-inflight ()
  :tags '(dsh-unit)
  (let ((rpc-requests nil))
    (with-temp-buffer
      (dsh-test-reference-reset)
      (setq dsh-emacs--reference-query "re"
            dsh-emacs--reference-candidates
            (list (cons "@README.md" '(:kind file :path "README.md"))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                 (lambda (method _params)
                   (push method rpc-requests)
                   (cons nil nil))))
        (ert-info ((format "%s" "require-cache-stale-answers-while-inflight"))
          (should (let ((dsh-emacs--reference-inflight t))
                    (and (dsh-emacs-reference--require-cache "sess" "re2")
                         ;; Stale cache retained, no new fetch started
                         (null rpc-requests)))))
        (ert-info ((format "%s" "require-cache-no-cache-while-inflight-nil"))
          (should (let ((dsh-emacs--reference-inflight t)
                        (dsh-emacs--reference-query nil)
                        (dsh-emacs--reference-candidates nil))
                    (null (dsh-emacs-reference--require-cache "sess" "re2")))))))))

;; --- session-rows: session row short label + duplicate-name disambiguation
;; (mention stays in the cache) ---
(ert-deftest dsh-emacs-test-reference-session-rows-short-and-unique ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--reference-candidates
         (list (cons "@README.md" '(:kind file :path "README.md"))
               (cons "@[My Talk](dsh-session:cyJpZCI6InMxIn0)"
                     '(:kind session :label "My Talk" :session-id "s1"))
               (cons "@[My Talk](dsh-session:cyJpZCI6InMyIn0)"
                     '(:kind session :label "My Talk" :session-id "s2")))))
    (ert-info ((format "%s" "session-rows-short-and-unique"))
      (should (equal (dsh-emacs-reference--session-rows)
                     '(("@My Talk" . "@[My Talk](dsh-session:cyJpZCI6InMxIn0)")
                       ("@My Talk #2" . "@[My Talk](dsh-session:cyJpZCI6InMyIn0)")))))))

;; --- affixate: file/directory rows get a leading type-icon column (consult-buffer
;; style) ---
(ert-deftest dsh-emacs-test-reference-affixate-icon-column-shape ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--reference-candidates
         (list (cons "@a.ts" '(:kind file :path "src/a.ts"))
               (cons "@sub/" '(:kind directory :path "sub"))
               (cons "@[T](dsh-session:x)"
                     '(:kind session :label "T" :cwd "/w"
                             :same-workspace t)))))
    (cl-letf (((symbol-function 'dsh-emacs-reference--row-icon)
               (lambda (path kind)
                 (pcase kind
                   ('file "F")
                   ('directory "D")
                   ('session "R")
                   (_ nil)))))
      (ert-info ((format "%s" "affixate-icon-column-shape"))
        (should (equal (dsh-emacs-reference--affixate
                        '("@a.ts" "@sub/" "@[T](dsh-session:x)"))
                       '(("@a.ts" "F " "")
                         ("@sub/" "D " "")
                         ("@[T](dsh-session:x)" "R " ""))))))
    (ert-info ((format "%s" "affixate-without-provider-text-only"))
      (should (cl-letf (((symbol-function 'dsh-emacs-reference--row-icon)
                         (lambda (_path _kind) nil)))
                (equal (dsh-emacs-reference--affixate '("@a.ts" "@sub/"))
                       '(("@a.ts" "" "")
                         ("@sub/" "" ""))))))
    (ert-info ((format "%s" "affixate-inline-icons-off"))
      (should (let ((dsh-emacs-reference-inline-icons nil))
                (equal (dsh-emacs-reference--affixate '("@a.ts"))
                       '(("@a.ts" "" ""))))))
    ;; --row-icon: a non-graphical frame outputs no nerd-font PUA glyphs (terminal
    ;; tofu blocks); a graphical frame with the provider available returns the
    ;; file/directory/session icon by kind
    (ert-info ((format "%s" "row-icon-gated-off-on-non-graphic"))
      (should (cl-letf (((symbol-function 'display-graphic-p) (lambda () nil))
                        ((symbol-function 'featurep)
                         (lambda (f &optional _sub) (eq f 'nerd-icons)))
                        ((symbol-function 'fboundp)
                         (lambda (s)
                           (memq s '(nerd-icons-icon-for-file nerd-icons-icon-for-dir)))))
                (and (null (dsh-emacs-reference--row-icon "src/a.ts" 'file))
                     (null (dsh-emacs-reference--row-icon nil 'session))))))
    (ert-info ((format "%s" "row-icon-graphic-uses-provider"))
      (should (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
                        ((symbol-function 'featurep)
                         (lambda (f &optional _sub) (eq f 'nerd-icons)))
                        ((symbol-function 'fboundp)
                         (lambda (s)
                           (memq s '(nerd-icons-icon-for-file nerd-icons-icon-for-dir))))
                        ((symbol-function 'nerd-icons-icon-for-file) (lambda (_f) "F"))
                        ((symbol-function 'nerd-icons-icon-for-dir) (lambda (_d) "D"))
                        ((symbol-function 'nerd-icons-codicon) (lambda (_n) "R")))
                (and (string= (dsh-emacs-reference--row-icon "src/a.ts" 'file) "F")
                     (string= (dsh-emacs-reference--row-icon "src" 'directory) "D")
                     ;; Session rows use codicon references glyphs (path ignored)
                     (string= (dsh-emacs-reference--row-icon nil 'session) "R")))))))

;; --- icon data is snapshotted when the completion table is built: a background
;; fetch then replaces `dsh-emacs--reference-candidates' with the results of a
;; new query, and the still-open corfu popup (holding the old snapshot table)
;; re-affixes with the snapshot map instead of the mutable cache → icons are not
;; pulled away (regression: after a new fetch some rows had no icon when
;; filtering)
(ert-deftest dsh-emacs-test-reference-affix-snapshot-survives-cache-swap ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs--reference-candidates
          (list (cons "@a.ts" '(:kind file :path "src/a.ts"))
                (cons "@sub/" '(:kind directory :path "sub"))))
         (rows (dsh-emacs-reference--session-rows))
         (map (dsh-emacs-reference--snapshot-affix '("@a.ts" "@sub/") rows)))
    ;; A narrower fetch lands, replacing the global cache
    (setq dsh-emacs--reference-candidates
          (list (cons "@fresh.md" '(:kind file :path "fresh.md"))))
    (ert-info ((format "%s" "affix-snapshot-survives-cache-swap"))
      (should (cl-letf (((symbol-function 'dsh-emacs-reference--row-icon)
                         (lambda (_path kind) (symbol-name kind))))
                (equal (dsh-emacs-reference--affixate-with map '("@a.ts" "@sub/"))
                       '(("@a.ts" "file " "")
                         ("@sub/" "directory " ""))))))))

;; --- rendering: a completed @ reference → colored clickable link (session
;; collapsed to @label) ---
(ert-deftest dsh-emacs-test-reference-link-spans-file-and-session ()
  :tags '(dsh-unit)
  (let* ((sid "session-ab1-2")
         (spans (dsh-emacs-reference--link-spans
                 (concat "see @src/a.ts and @[My Talk]("
                         (dsh-test-reference--session-uri sid) ") done"))))
    (ert-info ((format "%s" "link-spans-file-and-session"))
      (should (equal (mapcar (lambda (s) (list (nth 2 s) (nth 3 s)))
                             spans)
                     `((file "src/a.ts") (session ,sid)))))
    ;; The URI payload is base64url: it stays a session span (so the file matcher
    ;; cannot eat its `@[label' prefix) even when no id decodes.
    (ert-info ((format "%s" "link-spans-base64url-charset-claimed"))
      (should (equal (mapcar (lambda (s) (list (nth 2 s) (nth 3 s)))
                             (dsh-emacs-reference--link-spans
                              "@[T](dsh-session:ab1_-2)"))
                     '((session nil)))))
    (ert-info ((format "%s" "link-spans-not-email"))
      (should (null (dsh-emacs-reference--link-spans "contact mail@example.com now"))))
    ;; A bare @word (including extensionless files such as @LICENSE) is always a file
    ;; reference link; only emails and a lone @ are excluded
    (ert-info ((format "%s" "link-spans-bare-atword-is-file"))
      (should (equal (mapcar (lambda (s) (nth 3 s))
                             (dsh-emacs-reference--link-spans
                              "note @LICENSE and @src/a.ts and @README.md"))
                     '("LICENSE" "src/a.ts" "README.md"))))
    (ert-info ((format "%s" "link-spans-lone-at-not-file"))
      (should (null (dsh-emacs-reference--link-spans "an @ alone and @ here"))))))

;; Regression: opening a rendered session mention sent the URI payload itself as
;; the session id, so the host answered `session/not-found' — the id must be the
;; JSON string the payload encodes.
(ert-deftest dsh-emacs-test-reference-decode-session-uri-restores-session-id ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "decode-session-uri-restores-session-id"))
    (should (equal (dsh-emacs-reference--decode-session-uri
                    "InNlc3Npb24tZTMyYTE1MGUtMTk1Ny00MDU3LTg2ZjMtNmM0YTNmOTM1YTYxIg")
                   "session-e32a150e-1957-4057-86f3-6c4a3f935a61"))
    (should (null (dsh-emacs-reference--decode-session-uri "cyJpZCI6InMxIn0")))))

;; JSON numbers and Unicode escapes alter match data, including before a parse
;; error.  Decoding must not rewind the scanner to the same mention forever.
(ert-deftest dsh-emacs-test-reference-fontify-session-scan-progress ()
  :tags '(dsh-unit)
  (dolist (case `(("number" "MTIz" nil)
                  ("unicode-escape" "InNlc3Npb24tXHUwMDAxIg"
                   ,(concat "session-" (string 1)))
                  ("parse-error" "WzEs" nil)))
    (pcase-let* ((`(,name ,payload ,id) case)
                 (prefix "a sufficiently long prefix ")
                 (decode (symbol-function
                          'dsh-emacs-reference--decode-session-uri))
                 (calls 0)
                 (out
                  (catch 'repeated-mention
                    (cl-letf (((symbol-function
                                'dsh-emacs-reference--decode-session-uri)
                               (lambda (value)
                                 ;; Bound the repro so a regression fails instead
                                 ;; of hanging the entire test suite.
                                 (when (> (cl-incf calls) 2)
                                   (throw 'repeated-mention nil))
                                 (funcall decode value))))
                      (dsh-emacs-reference-fontify
                       (concat prefix "@[T](dsh-session:" payload ")"
                               " then @[Next](dsh-session:InMyIg) @tail.md"))))))
      (ert-info ((format "%s" (concat "fontify-session-scan-progress-" name)))
        (should (= calls 2))
        (should (and (stringp out)
                     (string= (substring-no-properties out)
                              (concat prefix "@T then @Next @tail.md"))
                     (equal (get-text-property (length prefix)
                                               'dsh-emacs-reference-ref out)
                            (cons 'session id))
                     (equal (get-text-property (string-match "@Next" out)
                                               'dsh-emacs-reference-ref out)
                            '(session . "s2"))
                     (equal (get-text-property (string-match "@tail.md" out)
                                               'dsh-emacs-reference-ref out)
                            '(file . "tail.md"))))))))

(ert-deftest dsh-emacs-test-reference-fontify-session-collapses-to-label ()
  :tags '(dsh-unit)
  (let* ((sid "session-ab1-2")
         (out (dsh-emacs-reference-fontify
               (concat "see @src/ui/button.tsx then @[My Talk]("
                       (dsh-test-reference--session-uri sid)
                       "), mail@example ok"))))
    (ert-info ((format "%s" "fontify-session-collapses-to-label"))
      (should (string= (substring-no-properties out)
                       "see @src/ui/button.tsx then @My Talk, mail@example ok")))
    (ert-info ((format "%s" "fontify-spans-carry-session-id"))
      (should (equal (get-text-property (string-match "@My Talk" out)
                                        'dsh-emacs-reference-ref out)
                     `(session . ,sid))))))

(ert-deftest dsh-emacs-test-reference-fontify-quoted-file-path-linked ()
  :tags '(dsh-unit)
  (let ((out (dsh-emacs-reference-fontify "note @\"my dir/a.ts\" here")))
    (ert-info ((format "%s" "fontify-quoted-file-path-linked"))
      (should (let ((i (string-match "@\"my dir/a.ts\"" out)))
                (equal (get-text-property i 'dsh-emacs-reference-ref out)
                       '(file . "my dir/a.ts")))))))

;; The `@[label' prefix of a session mention is not treated as a file link
(ert-deftest dsh-emacs-test-reference-fontify-two-sessions-and-no-file-prefix ()
  :tags '(dsh-unit)
  (let ((out (dsh-emacs-reference-fontify
              "@[T](dsh-session:xyz) @[Q](dsh-session:uvw)")))
    (ert-info ((format "%s" "fontify-two-sessions-and-no-file-prefix"))
      (should (string= (substring-no-properties out) "@T @Q")))))

;; RET/mouse open: a session reference jumps via `dsh-emacs-open-session'
(ert-deftest dsh-emacs-test-reference-open-at-point-jumps-to-session ()
  :tags '(dsh-unit)
  (let* ((sid "session-target-1")
         (opened nil) (buf (generate-new-buffer " *t-ref-open*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (dsh-emacs-reference-fontify
                   (concat "@[Sess](" (dsh-test-reference--session-uri sid) ")")))
          (goto-char (point-min))
          (cl-letf (((symbol-function 'dsh-emacs-open-session)
                     (lambda (id) (setq opened id))))
            (dsh-emacs-reference-open-at-point))
          (ert-info ((format "%s" "open-at-point-jumps-to-session"))
            (should (equal opened sid))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- reseed/reopen: when the server persists a reference message it collapses the
;; canonical mention into a readable @label (the id is stripped), and the real
;; sessionId+label appears only in the immediately following session-reference
;; recall event — rendering with REFERENCES ((LABEL . SESSION-ID)) is what
;; restores the readable @label into a session chip with the real id, while plain
;; @file still links as usual.
(ert-deftest dsh-emacs-test-reference-reseed-readable-label-links-as-session-with-real-id ()
  :tags '(dsh-unit)
  (let ((out (dsh-emacs-reference-fontify
              "see @dsh-emacs如何通过转发接入Codex与Claude 和 @src/a.ts"
              '(("dsh-emacs如何通过转发接入Codex与Claude" . "session-abc-123")))))
    (let ((label-pos (string-match "@dsh-emacs如何通过转发接入Codex与Claude" out))
          (file-pos (string-match "@src/a.ts" out)))
      (ert-info ((format "%s" "reseed-readable-label-links-as-session-with-real-id"))
        (should (and label-pos file-pos
                     (equal (get-text-property label-pos 'dsh-emacs-reference-ref out)
                            '(session . "session-abc-123"))
                     (equal (get-text-property file-pos 'dsh-emacs-reference-ref out)
                            '(file . "src/a.ts"))))))
    (ert-info ((format "%s" "reseed-readable-label-text-preserved"))
      (should (string= (substring-no-properties out)
                       "see @dsh-emacs如何通过转发接入Codex与Claude 和 @src/a.ts")))))

;; After the readable @label is restored to a chip it can still jump to the real
;; session
(ert-deftest dsh-emacs-test-reference-reseed-label-open-jumps-to-real-session ()
  :tags '(dsh-unit)
  (let ((opened nil) (buf (generate-new-buffer " *t-reseed-open*")))
    (unwind-protect
        (with-current-buffer buf
          (insert (dsh-emacs-reference-fontify
                   "关于 @dsh-emacs如何通过转发接入Codex与Claude 的事"
                   '(("dsh-emacs如何通过转发接入Codex与Claude" . "session-abc-123"))))
          (goto-char (1+ (string-match "@dsh-emacs" (buffer-string))))
          (cl-letf (((symbol-function 'dsh-emacs-open-session)
                     (lambda (id) (setq opened id))))
            (dsh-emacs-reference-open-at-point))
          (ert-info ((format "%s" "reseed-label-open-jumps-to-real-session"))
            (should (equal opened "session-abc-123"))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; A readable @word that matches no reference still goes through the file link
;; (not polluted)
(ert-deftest dsh-emacs-test-reference-reseed-nonmatching-label-stays-file ()
  :tags '(dsh-unit)
  (let ((out (dsh-emacs-reference-fontify
              "mention @unrelated now"
              '(("known-label" . "session-k")))))
    (ert-info ((format "%s" "reseed-nonmatching-label-stays-file"))
      (should (equal (get-text-property (string-match "@unrelated" out)
                                        'dsh-emacs-reference-ref out)
                     '(file . "unrelated"))))))

;; --- reseed/reopen: reference message + the immediately following
;; session-reference recall event ---
;; The server stores the reference message as a readable @label (id stripped),
;; and the real sessionId+label appears only in the immediately following
;; session-reference recall event. When history reseed renders these two
;; user/message entries in one batch, render-history-events should associate the
;; recall's references back to the preceding message's seq and render @label as a
;; jumpable session chip.
(ert-deftest dsh-emacs-test-reference-reseed-render-links-readable-label-to-session ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-reseed-session-ref*"))
        (opened nil))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-modeline-setup)
          (setq dsh-emacs--buffer-session "sess-reseed")
          (let* ((label "实现dsh web的@指令")
                 (sid "session-ae44fea5-bf67-4ba9-b3da-599903832933")
                 (ref-msg
                  (json-read-from-string
                   (concat "{\"type\":\"user/message\",\"seq\":40,"
                           "\"data\":{\"source\":{\"kind\":\"user\"},"
                           "\"content\":[{\"type\":\"text\","
                           "\"text\":\"from @实现dsh web的@指令 please look\"}]}}")))
                 (recall
                  (json-read-from-string
                   (concat "{\"type\":\"user/message\",\"seq\":41,"
                           "\"data\":{\"source\":{\"kind\":\"session-reference\","
                           "\"form\":\"recall\","
                           "\"references\":[{\"sessionId\":\"session-ae44fea5-bf67-4ba9-b3da-599903832933\","
                           "\"label\":\"实现dsh web的@指令\"}]},"
                           "\"content\":[{\"type\":\"text\",\"text\":\"# refs\"}]}}")))
                 (label-token (concat "@" label)))
            (dsh-emacs-render-history-events
             (list (list (cons "event" ref-msg))
                   (list (cons "event" recall)))
             nil)
            (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
                   (pos (string-match label-token text))
                   (prop (buffer-substring (point-min) (point-max)))
                   (ref (and pos (get-text-property pos 'dsh-emacs-reference-ref prop))))
              (ert-info ((format "%s" "reseed-render-links-readable-label-to-session"))
                (should (and pos (equal ref (cons 'session sid))))))))
      (kill-buffer buf))))

;; --- composer atomic chip: the buffer stores a short @label + canonical text
;; properties, and sending expands it back to the full mention
(ert-deftest dsh-emacs-test-reference-chip-keeps-short-label-and-canonical ()
  :tags '(dsh-unit)
  (let* ((sid "session-ab12-cd")
         (canon (concat "@[My Talk](" (dsh-test-reference--session-uri sid) ")")))
    (with-temp-buffer
      (setq-local dsh-emacs--input-marker (point-min-marker))
      (insert "@My Talk")
      (ert-info ((format "%s" "chip-keeps-short-label-and-canonical"))
        (should (and (dsh-emacs-reference--session-chip (point-min) (point) canon)
                     (string= (buffer-substring-no-properties (point-min) (point))
                              "@My Talk")
                     (string= (get-text-property (point-min)
                                                 'dsh-emacs-reference-canonical)
                              canon)
                     (equal (get-text-property (point-min) 'dsh-emacs-reference-ref)
                            `(session . ,sid))
                     (get-text-property (point-min) 'dsh-emacs-reference-chip))))
      ;; no `display' folding: visible text is exactly the short label in the buffer
      (ert-info ((format "%s" "chip-has-no-display-folding"))
        (should (null (get-text-property (point-min) 'display))))
      ;; expansion back to the full mention, via both the raw span reader and
      ;; `dsh-emacs--get-input' (the send / history path)
      (ert-info ((format "%s" "chip-expands-to-full-mention"))
        (should (string= (dsh-emacs-reference--expanded-text (point-min) (point-max))
                         canon))
        (should (string= (dsh-emacs--get-input) canon)))
      ;; self-insert while point sits on the chip hops to its end first
      (goto-char (+ (point-min) 5))
      (let ((this-command 'self-insert-command))
        (dsh-emacs-reference--chip-guard-before))
      (ert-info ((format "%s" "chip-guard-hops-out-of-interior"))
        (should (= (point) (point-max))))
      ;; backspace at the trailing edge deletes the whole chip (atomic unit)
      (goto-char (point-max))
      (delete-backward-char 1)
      (ert-info ((format "%s" "chip-backspace-deletes-whole-span"))
        (should (string= (buffer-substring-no-properties (point-min) (point-max)) "")))
      ;; typing after the chip must not inherit its link/face style
      (insert "@My Talk")
      (dsh-emacs-reference--session-chip (point-min) (point) canon)
      (insert " tail")
      (ert-info ((format "%s" "chip-typed-after-stays-plain"))
        (should (let ((p (- (point) 5)))
                  (and (null (get-text-property p 'face))
                       (null (get-text-property p 'dsh-emacs-reference-chip)))))))))

;; --- C-k on a chip deletes the whole chip atomically (not just its tail) ---
;; Regression: the chip guard used to hop every edit that started on a chip
;; character to the chip's end, so C-k starting on the chip's leading edge or
;; interior only killed what followed it and the chip itself could never be
;; deleted.  Now kill-line on a chip pulls the cursor back to the chip's start
;; so C-k removes the whole chip as one atomic unit.
(ert-deftest dsh-emacs-test-reference-kill-line-on-chip-removes-whole-chip ()
  :tags '(dsh-unit)
  (let ((canon "@[My Talk](dsh-session:ab12_CD)"))
    (with-temp-buffer
      (setq-local dsh-emacs--input-marker (point-min-marker))
      (insert "@My Talk tail")
      (dsh-emacs-reference--session-chip (point-min) (+ (point-min) 8) canon)
      ;; cursor on the chip's leading edge -> C-k deletes the whole chip + tail
      (goto-char (point-min))
      (let ((this-command 'kill-line))
        (dsh-emacs-reference--chip-guard-before))
      (kill-line)
      (ert-info ((format "%s" "kill-line-on-chip-removes-whole-chip"))
        (should (string-empty-p
                 (buffer-substring-no-properties (point-min) (point-max)))))
      ;; cursor on plain text AFTER the chip -> only the tail is killed, chip kept
      (insert "@My Talk tail")
      (dsh-emacs-reference--session-chip (point-min) (+ (point-min) 8) canon)
      (goto-char (+ (point-min) 9))
      (let ((this-command 'kill-line))
        (dsh-emacs-reference--chip-guard-before))
      (kill-line)
      (ert-info ((format "%s" "kill-line-after-chip-keeps-chip"))
        (should (string= (buffer-substring-no-properties (point-min) (point-max))
                         "@My Talk "))))))

;; A completed file reference is a chip: with the cursor at its end it must not be
;; treated as a new active @ token (otherwise the data watcher re-fetches along
;; that path and re-narrows the candidate cache — the next @ would only hold the
;; previous one's candidates). Only after the cursor moves away, then space + @,
;; is it a new token.
(ert-deftest dsh-emacs-test-reference-active-token-ignores-completed-file-chip ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-active-chip*")))
    (unwind-protect
        (with-current-buffer buf
          (setq-local dsh-emacs--input-marker (point-min-marker))
          (insert "@src/a.ts")
          (dsh-emacs-reference--composer-file-chip
           (- (point) (length "@src/a.ts")) (point) "src/a.ts")
          (ert-info ((format "%s" "active-token-ignores-completed-file-chip"))
            (should (null (dsh-emacs-reference--active-token))))
          (insert " @x")
          (ert-info ((format "%s" "active-token-after-space-and-at-is-new"))
            (should (equal (dsh-emacs-reference--active-token)
                           '("@x" "x" nil)))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- active-token / capf: input-area token → completion region and candidates ---
(ert-deftest dsh-emacs-test-reference-active-token-at-point ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-capf*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "hi @re")
          (setq-local dsh-emacs--input-marker (point-min-marker))
          (goto-char (point-max))
          ;; The token ends exactly before point → completion returns (start end candidates)
          (let ((dsh-emacs--reference-query "re")
                (dsh-emacs--reference-candidates
                 (list (cons "@README.md"
                             '(:kind file :path "README.md")))))
            (cl-letf (((symbol-function 'dsh-emacs--active-session-id)
                       (lambda () "sess")))
              (ert-info ((format "%s" "active-token-at-point"))
                (should (equal (dsh-emacs-reference--active-token)
                               '("@re" "re" nil))))
              (let* ((res (dsh-emacs-reference-completion-at-point))
                     (start (nth 0 res))
                     (end (nth 1 res))
                     (cands (nth 2 res))
                     (props (nthcdr 3 res)))
                (ert-info ((format "%s" "capf-region-and-candidates"))
                  (should (= start (- (point-max) 3)))
                  (should (= end (point-max)))
                  (should (equal (dsh-test-completion-items cands)
                                 '("@README.md"))))
                ;; The icon column is always drawn by :affixation-function itself, and the
                ;; capf
                ;; result never provides :company-kind (the :fn-style file/folder glyphs of
                ;; nerd-icons-corfu / kind-icon strip the nerd-font font family → garbled
                ;; symbols)
                (ert-info ((format "%s" "capf-plist-no-company-kind"))
                  (should (functionp (plist-get props :affixation-function)))
                  (should (functionp (plist-get props :exit-function)))
                  (should (null (plist-get props :company-kind))))
                (ert-info ((format "%s" "capf-reopens-bare-at-after-backspace"))
                  (should (eq (plist-get props :company-prefix-length) t)))
                (ert-info ((format "%s" "capf-preserves-reference-order"))
                  (should (eq (plist-get props :display-sort-function) #'identity))
                  (should (eq (completion-metadata-get
                               (completion-metadata "" cands nil)
                               'display-sort-function)
                              #'identity))
                  (should (eq (completion-metadata-get
                               (completion-metadata "" cands nil)
                               'cycle-sort-function)
                              #'identity))))
              ;; Point outside the input area (read-only region) → nil
              (goto-char (point-min))
              (ert-info ((format "%s" "capf-outside-input-nil"))
                (should (null (dsh-emacs-reference-completion-at-point)))))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- capf session rows: short-label candidates + exit-function rewrites to the
;; canonical mention ---
(ert-deftest dsh-emacs-test-reference-capf-session-row-short ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-exit*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "hi @M")
          (setq-local dsh-emacs--input-marker (point-min-marker))
          (goto-char (point-max))
          (let ((dsh-emacs--reference-query "")
                (dsh-emacs--reference-candidates
                 (list (cons "@[My Talk](dsh-session:cyJpZCI6InMxIn0)"
                             '(:kind session :label "My Talk"
                                     :session-id "s1")))))
            (cl-letf (((symbol-function 'dsh-emacs--active-session-id)
                       (lambda () "sess")))
              (let* ((res (dsh-emacs-reference-completion-at-point))
                     (cands (nth 2 res))
                     (exit (plist-get (nthcdr 3 res) :exit-function)))
                (ert-info ((format "%s" "capf-session-row-short"))
                  (should (equal (dsh-test-completion-items cands)
                                 '("@My Talk"))))
                ;; Simulate the frontend inserting the row text then calling exit: short
                ;; @label
                ;; text kept + canonical properties
                (delete-region (- (point) 2) (point))
                (insert "@My Talk")
                (ert-info ((format "%s" "capf-exit-keeps-short-label-chip"))
                  (should (progn
                            (funcall exit "@My Talk" 'finished)
                            (string= (buffer-substring-no-properties
                                      (point-min) (point-max))
                                     "hi @My Talk")
                            (string= (get-text-property
                                      (- (point) (length "@My Talk"))
                                      'dsh-emacs-reference-canonical)
                                     "@[My Talk](dsh-session:cyJpZCI6InMxIn0)")
                            ;; Send/history input reads expand back to the full mention
                            (string= (dsh-emacs--get-input)
                                     "hi @[My Talk](dsh-session:cyJpZCI6InMxIn0)"))))
                ;; Completion consumes that @ token: clear the narrowed fetch state so the
                ;; next @
                ;; restores the full set
                (ert-info ((format "%s" "capf-exit-resets-fetch-state"))
                  (should (and (null dsh-emacs--reference-query)
                               (null dsh-emacs--reference-requested))))))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- directory candidates: after selection immediately request the next level so
;; Corfu can keep expanding ---
(ert-deftest dsh-emacs-test-reference-directory-pick-fetches-next-level ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-directory-drill*"))
        (requested nil))
    (unwind-protect
        (with-current-buffer buf
          (insert "hi @src/")
          (setq-local dsh-emacs--reference-query "src/"
                      dsh-emacs--reference-candidates
                      (list (cons "@src/" '(:kind directory :path "src"))))
          (cl-letf (((symbol-function 'dsh-emacs--active-session-id)
                     (lambda () "sess"))
                    ((symbol-function 'dsh-emacs-reference--fetch-query)
                     (lambda (session-id query)
                       (setq requested (list session-id query))))
                    ((symbol-function 'dsh-emacs-reference--schedule-popup-refresh)
                     #'ignore))
            (dsh-emacs-reference--exit "@src/" 'finished nil))
          (ert-info ((format "%s" "directory-pick-fetches-next-level"))
            (should (equal requested '("sess" "src/")))
            (should (null dsh-emacs--reference-query))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- insert: the active token before point is replaced; with no token, insert at
;; point ---
(ert-deftest dsh-emacs-test-reference-insert-replaces-token-keeps-short-label ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-insert*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "see @old")
          (setq-local dsh-emacs--input-marker (point-min-marker))
          (goto-char (point-max))
          (dsh-emacs-reference--insert-at-point
           "@[New](dsh-session:cyJpZCI6InMxIn0)")
          ;; Session mention: the buffer stores a short @label, canonical goes on text
          ;; properties
          (ert-info ((format "%s" "insert-replaces-token-keeps-short-label"))
            (should (string= (buffer-substring-no-properties (point-min) (point-max))
                             "see @New"))
            (should (string= (get-text-property
                              (- (point-max) (length "@New"))
                              'dsh-emacs-reference-canonical)
                             "@[New](dsh-session:cyJpZCI6InMxIn0)")))
          (goto-char (point-max))
          (dsh-emacs-reference--insert-at-point "@tail.md")
          (ert-info ((format "%s" "insert-no-token-inserts-at-point"))
            (should (string= (buffer-substring-no-properties (point-min) (point-max))
                             "see @New@tail.md")))
          ;; Reading the input expands the short chip back to the full mention (file @path
          ;; is identical)
          (ert-info ((format "%s" "insert-expands-to-full-mention"))
            (should (string= (dsh-emacs--get-input)
                             "see @[New](dsh-session:cyJpZCI6InMxIn0)@tail.md"))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- active-token: a completed canonical mention (with label escapes) no longer
;; triggers completion ---
(ert-deftest dsh-emacs-test-reference-active-token-completed-plain-nil ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-ref-done*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "@[My Talk](dsh-session:cyJpZCI6InMxIn0)")
          (setq-local dsh-emacs--input-marker (point-min-marker))
          (goto-char (point-max))
          (ert-info ((format "%s" "active-token-completed-plain-nil"))
            (should (null (dsh-emacs-reference--active-token))))
          ;; The host escapes `\` and `]` in the label as `\\` / `\]` (see the harness's
          ;; formatSessionReferenceMention), so the completion check must keep up
          (erase-buffer)
          (insert "@[My\\]Talk](dsh-session:cyJpZCI6InMxIn0)")
          (goto-char (point-max))
          (ert-info ((format "%s" "active-token-completed-escaped-bracket-nil"))
            (should (null (dsh-emacs-reference--active-token))))
          (erase-buffer)
          (insert "@[a\\\\b](dsh-session:cyJpZCI6InMxIn0)")
          (goto-char (point-max))
          (ert-info ((format "%s" "active-token-completed-escaped-backslash-nil"))
            (should (null (dsh-emacs-reference--active-token))))
          (erase-buffer)
          (insert "hi @re")
          (goto-char (point-max))
          (ert-info ((format "%s" "active-token-in-progress-still-triggers"))
            (should (equal (dsh-emacs-reference--active-token) '("@re" "re" nil)))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(provide 'dsh-test-reference)
;;; dsh-test-reference.el ends here

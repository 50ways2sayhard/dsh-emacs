;;; dsh-test-command.el --- Command tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

;; --- Test 94: slash command parsing (admission syntax matching the dsh
;; registry) ---
(ert-deftest dsh-emacs-test-command-command-parse-admits-slash-lines ()
  :tags '(dsh-unit)
  (let ((cases '(("/compact" "compact" "")
                 ("/goal set x" "goal" " set x")
                 ("/plan\toff" "plan" "\toff")       ; TAB boundaries are separators too
                 ("  /compact  " "compact" "")
                 ("/goal-set_x run" "goal-set_x" " run")
                 ("/compactx" "compactx" "")))
        (ok t))
    (dolist (c cases)
      (let ((parsed (dsh-emacs-command-parse (car c))))
        (unless (and (string= (car parsed) (nth 1 c))
                     (string= (cdr parsed) (nth 2 c)))
          (setq ok nil))))
    (ert-info ((format "%s" "command-parse-admits-slash-lines"))
      (should ok))))

(ert-deftest dsh-emacs-test-command-command-parse-rejects-non-commands ()
  :tags '(dsh-unit)
  (let ((not-commands '("/" "" "hello" "/usr/local" "/Compact" "//" "/2025"
                        "http://x" nil)))
    (ert-info ((format "%s" "command-parse-rejects-non-commands"))
      (should (cl-every (lambda (s) (null (dsh-emacs-command-parse s)))
                        not-commands)))))

;; --- Test 95: commands.execute payload and on-done semantics ---
(ert-deftest dsh-emacs-test-command-command-execute-wire-and-on-done ()
  :tags '(dsh-unit)
  (let ((calls nil)
        (done nil))
    (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method params cb)
                 (push (list method params) calls)
                 (funcall cb t '((commandId . "c1")
                                 (result . ((kind . "success")
                                            (text . "ok"))))))))
      (dsh-emacs-command-execute
       "sess-exec" "/compact" nil
       (lambda (ok ex _err) (setq done (list ok ex))))
      (let* ((call (car calls))
             (params (cadr call))
             (submitted (cdr (assq 'submittedAttachments params))))
        (ert-info ((format "%s" "command-execute-wire-and-on-done"))
          (should (and (string= "commands/execute" (car call))
                       (string= "/compact" (cdr (assq 'line params)))
                       (string= "sess-exec" (cdr (assq 'agentId params)))
                       ;; 0.1.5 host field: `images' is rejected as an unexpected
                       ;; argument, and the value must be the tagged array.
                       (null (assq 'images params))
                       (vectorp submitted) (zerop (length submitted))
                       (equal done
                              (list t (dsh-protocol-command-execution--from-alist
                                       '((commandId . "c1")
                                         (result . ((kind . "success")
                                                    (text . "ok"))))))))))))))

(ert-deftest dsh-emacs-test-command-command-execute-miss-reports-nil ()
  :tags '(dsh-unit)
  (let ((missed nil))
    (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
               (lambda (_m _p cb) (funcall cb t nil))))
      (dsh-emacs-command-execute "s" "/nope" nil
                                 (lambda (ok ex _err)
                                   (setq missed (list ok ex)))))
    (ert-info ((format "%s" "command-execute-miss-reports-nil"))
      (should (equal missed '(t nil))))))

(ert-deftest dsh-emacs-test-command-command-execute-passes-attachments ()
  :tags '(dsh-unit)
  (let* ((image-part '((type . "image") (mediaType . "image/png") (data . "x")))
         (file-part '((type . "file") (receiptId . "r1")))
         (calls nil))
    ;; The resolved part list rides `submittedAttachments' unchanged: images and
    ;; file receipts are one tagged union, and the field is required (empty
    ;; array for a text-only command).
    (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
               (lambda (m p cb)
                 (push (list m p) calls)
                 (funcall cb t nil))))
      (dsh-emacs-command-execute "s" "/goal" (list image-part file-part) nil)
      (dsh-emacs-command-execute "s" "/goal" nil nil))
    (let ((params (cadr (nth 1 calls)))
          (empty-params (cadr (car calls))))
      (ert-info ((format "%s" "command-execute-passes-attachments"))
        (should (null (assq 'images params)))
        (should (equal (append (cdr (assq 'submittedAttachments params)) nil)
                       (list image-part file-part)))
        (should (equal (cdr (assq 'submittedAttachments empty-params)) []))))))

(ert-deftest dsh-emacs-test-command-command-from-alist-bare ()
  :tags '(dsh-unit)
  (let* ((cmd (dsh-protocol-command--from-alist
               '((name . "compact") (description . "Compact history")))))
    (ert-info ((format "%s" "command-from-alist-bare"))
      (should (and (string= "compact" (dsh-protocol-command-name cmd))
                   (string= "Compact history"
                            (dsh-protocol-command-description cmd))
                   (null (dsh-protocol-command-input cmd)))))))

(ert-deftest dsh-emacs-test-command-command-from-alist-with-input ()
  :tags '(dsh-unit)
  (let* ((cmd (dsh-protocol-command--from-alist
               '((name . "goal") (description . "goal ops")
                 (input . ((hint . "[<objective>]") (attachments . t))))))
         (input (dsh-protocol-command-input cmd)))
    (ert-info ((format "%s" "command-from-alist-with-input"))
      (should (and (string= "[<objective>]" (dsh-protocol-command-input-hint input))
                   (dsh-protocol-command-input-attachments input))))))

(ert-deftest dsh-emacs-test-command-command-catalog-sync-caches ()
  :tags '(dsh-unit)
  (let ((sid "sess-cat")
        (rpc-calls 0)
        (old dsh-emacs--command-catalogs))
    (unwind-protect
        (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                   (lambda (method params)
                     (should (equal method "commands/list"))
                     (should (equal params '((agentId . "sess-cat"))))
                     (setq rpc-calls (1+ rpc-calls))
                     (cons t [((name . "compact") (description . "c"))
                              ((name . "goal") (description . "g"))]))))
          (let ((items (dsh-emacs-command-catalog-sync sid))
                (again (dsh-emacs-command-catalog-sync sid)))
            (ert-info ((format "%s" "command-catalog-sync-caches"))
              (should (and (= (length items) 2)
                           (string= "goal"
                                    (dsh-protocol-command-name (cadr items)))
                           (= rpc-calls 1)
                           (equal again items))))))
      (setq dsh-emacs--command-catalogs old))))

(ert-deftest dsh-emacs-test-command-command-catalog-fetch-async ()
  :tags '(dsh-unit)
  (let ((sid "sess-async")
        (fetched nil)
        (old dsh-emacs--command-catalogs))
    (unwind-protect
        (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                   (lambda (method params cb)
                     (should (equal method "commands/list"))
                     (should (equal params '((agentId . "sess-async"))))
                     (funcall cb t [((name . "plan") (description . "p"))]))))
          (dsh-emacs-command-catalog-fetch sid
                                           (lambda (items)
                                             (setq fetched items)))
          (ert-info ((format "%s" "command-catalog-fetch-async"))
            (should (and fetched
                         (string= "plan"
                                  (dsh-protocol-command-name (car fetched)))))))
      (setq dsh-emacs--command-catalogs old))))

;; After several fetches for the same session, the cache may hold only one entry
;; for that session (assoc-delete-all fix: with assq-delete-all the string keys
;; compare by eq, so old entries are never deleted and the alist grows without
;; bound)
(ert-deftest dsh-emacs-test-command-command-catalog-single-entry-per-session ()
  :tags '(dsh-unit)
  (let ((sid "sess-dedup")
        (old dsh-emacs--command-catalogs))
    (unwind-protect
        (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                   (lambda (_m _p cb)
                     (funcall cb t [((name . "a") (description . "A"))]))))
          ;; Two independent fetches (the previous one already finished, inflight cleared)
          (dsh-emacs-command-catalog-fetch sid)
          (dsh-emacs-command-catalog-fetch sid)
          (let* ((entries (cl-remove-if-not
                           (lambda (e) (string= sid (car e)))
                           dsh-emacs--command-catalogs)))
            (ert-info ((format "%s" "command-catalog-single-entry-per-session"))
              (should (= (length entries) 1)))))
      (setq dsh-emacs--command-catalogs old))))

;; Idle prefetch when a session is opened: schedule an idle timer; do not
;; schedule again when the directory is already cached
(ert-deftest dsh-emacs-test-command-command-catalog-prefetch-schedules-idle ()
  :tags '(dsh-unit)
  (let ((sid "sess-prefetch")
        (old dsh-emacs--command-catalogs)
        (old-pref dsh-emacs-command-prefetch)
        (old-delay dsh-emacs-command-prefetch-delay)
        (timers nil))
    (unwind-protect
        (progn
          (setq dsh-emacs-command-prefetch t
                dsh-emacs-command-prefetch-delay 0.05)
          (let ((timer (dsh-emacs-command-catalog-prefetch sid)))
            (when timer (push timer timers))
            (ert-info ((format "%s" "command-catalog-prefetch-schedules-idle"))
              (should (timerp timer))))
          ;; Already cached → the guard refuses to schedule again
          (dsh-emacs-command--cache-catalog
           sid (list (dsh-protocol-command--from-alist '((name . "x")))))
          (let ((before (length timer-list)))
            (dsh-emacs-command-catalog-prefetch sid)
            (ert-info ((format "%s" "command-catalog-prefetch-skips-when-cached"))
              (should (= (length timer-list) before)))))
      (mapc #'cancel-timer timers)
      (setq dsh-emacs--command-catalogs old
            dsh-emacs-command-prefetch old-pref
            dsh-emacs-command-prefetch-delay old-delay))))

;; Manual refresh: drop the stale cache and refetch from the server
(ert-deftest dsh-emacs-test-command-command-catalog-refresh-replaces-cache ()
  :tags '(dsh-unit)
  (let ((sid "sess-refresh")
        (calls 0)
        (old dsh-emacs--command-catalogs)
        (old-inflight dsh-emacs--command-fetch-inflight))
    (unwind-protect
        (progn
          ;; Pre-seed one stale cache entry
          (dsh-emacs-command--cache-catalog
           sid (list (dsh-protocol-command--from-alist '((name . "old")))))
          (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                     (lambda (_m _p cb)
                       (setq calls (1+ calls))
                       (funcall cb t [((name . "new") (description . "N"))]))))
            (dsh-emacs-command-catalog-refresh sid)
            (let ((items (dsh-emacs-command-catalog sid)))
              (ert-info ((format "%s" "command-catalog-refresh-replaces-cache"))
                (should (and (= calls 1)
                             items
                             (string= "new" (dsh-protocol-command-name (car items)))))))))
      (setq dsh-emacs--command-catalogs old
            dsh-emacs--command-fetch-inflight old-inflight))))

;; A response from a fetch that a refresh superseded must not repopulate the
;; cache: the older request can land after the newer one (manual refresh, or
;; a refresh racing the open-session prefetch)
(ert-deftest dsh-emacs-test-command-command-catalog-drops-superseded-response ()
  :tags '(dsh-unit)
  (let ((sid "sess-cmd-stale")
        (old-catalogs dsh-emacs--command-catalogs)
        (old-inflight dsh-emacs--command-fetch-inflight)
        (old-stamps dsh-emacs--command-fetch-stamps)
        (callbacks nil))
    (unwind-protect
        (progn
          ;; fetch A starts; its callback is captured, not run
          (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                     (lambda (_m _p cb) (push cb callbacks))))
            (dsh-emacs-command-catalog-fetch sid))
          ;; a refresh invalidates and starts fetch B (also captured)
          (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                     (lambda (_m _p cb) (push cb callbacks))))
            (dsh-emacs-command-catalog-refresh sid))
          ;; B answers first, then the superseded A
          (funcall (nth 0 callbacks) t [((name . "new") (description . "N"))])
          (funcall (nth 1 callbacks) t [((name . "old") (description . "O"))])
          (let ((items (dsh-emacs-command-catalog sid)))
            (ert-info ((format "%s" "command-catalog-drops-superseded-response"))
              (should (consp items))
              (should (string= "new" (dsh-protocol-command-name (car items)))))))
      (setq dsh-emacs--command-catalogs old-catalogs
            dsh-emacs--command-fetch-inflight old-inflight
            dsh-emacs--command-fetch-stamps old-stamps))))

;; --- Test 98: command/run + command/done rendering ---
(ert-deftest dsh-emacs-test-command-command-render-run-and-done ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-render*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (let* ((run-seq (dsh-emacs-render-event
                           '((type . "command/run") (seq . 10)
                             (data . ((commandId . "c1") (name . "goal")
                                      (args . " set x"))))))
                 (done-seq (dsh-emacs-render-event
                            '((type . "command/done") (seq . 11)
                              (data . ((commandId . "c1")
                                       (kind . "success")
                                       (text . "goal snapshot"))))))
                 (txt (buffer-string))
                 (above-input (buffer-substring (point-min)
                                                dsh-emacs--input-marker)))
            (let* ((ns (dsh-emacs-render--make-namespace))
                   (block-id "cmd-c1")
                   (blk (dsh-emacs-ui-find-block ns block-id))
                   (state (and blk (get-text-property (car blk) 'dsh-emacs-ui-state))))
              (ert-info ((format "%s" "command-render-run-and-done"))
                (should (and (= run-seq 10) (= done-seq 11)
                             ;; label = "goal" (args stripped, no / prefix) + short status
                             (string-match-p "goal" txt)
                             (string-match-p "done" txt)
                             ;; The result is folded into the body: not shown in the buffer, but
                             ;; kept in the
                             ;; fragment state
                             (not (string-match-p "goal snapshot" txt))
                             state
                             (equal (map-elt state :body) "goal snapshot")
                             (map-elt state :collapsed)
                             ;; The node must be inserted above the input area (the ❯ line), not
                             ;; at the end of
                             ;; the buffer
                             (string-match-p "goal" above-input)
                             (string-match-p "done" above-input))))))
          ;; The error kind renders too (● prefix + ✗ failed + body)
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 12)
             (data . ((commandId . "c2") (name . "permission")
                      (args . "")))))
          (dsh-emacs-render-event
           '((type . "command/done") (seq . 13)
             (data . ((commandId . "c2") (kind . "error")
                      (text . "unknown preset")))))
          (let* ((txt (buffer-string))
                 (ns (dsh-emacs-render--make-namespace))
                 (block-id "cmd-c2")
                 (blk (dsh-emacs-ui-find-block ns block-id))
                 (state (and blk (get-text-property (car blk) 'dsh-emacs-ui-state))))
            (ert-info ((format "%s" "command-render-error-kind"))
              (should (and (string-match-p "● permission" txt)
                           (string-match-p "failed" txt)
                           ;; Error results are likewise folded into the body
                           (not (string-match-p "unknown preset" txt))
                           state
                           (equal (map-elt state :body) "unknown preset")
                           (map-elt state :collapsed))))))
      (kill-buffer buf))))

(ert-deftest dsh-emacs-test-command-command-render-label ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "command-render-label"))
    (should (and (string= "compact" (dsh-emacs-render-command-label "compact" ""))
                 (string= "goal" (dsh-emacs-render-command-label
                                  "goal" " set x"))
                 (string= "goal" (dsh-emacs-render-command-label "goal" nil))))))

;; The result body of command/done must likewise not inherit success/error
;; coloring (after expanding, check the whole body; regression: the old
;; whole-block face turned the body green/red).
(ert-deftest dsh-emacs-test-command-command-done-body-not-tinted-case ()
  :tags '(dsh-unit)
  (dolist (case '(("ok1" "success" "compacted history" dsh-emacs-tool-success-face)
                  ("bad1" "error" "unknown preset" dsh-emacs-tool-error-face)))
    (let ((buf (generate-new-buffer " *dsh-cmd-body-face*")))
      (unwind-protect
          (with-current-buffer buf
            (dsh-emacs-mode)
            (dsh-emacs-render-event
             `((type . "command/run") (seq . 40)
               (data . ((commandId . ,(nth 0 case)) (name . "compact")))))
            (dsh-emacs-render-event
             `((type . "command/done") (seq . 41)
               (data . ((commandId . ,(nth 0 case))
                        (kind . ,(nth 1 case))
                        (text . ,(nth 2 case))))))
            (let* ((ns (dsh-emacs-render--make-namespace))
                   (block (dsh-emacs-ui-find-block
                           ns (format "cmd-%s" (nth 0 case)))))
              (when block
                (goto-char (car block))
                (dsh-emacs-ui-toggle-fragment))
              (setq block (dsh-emacs-ui-find-block
                           ns (format "cmd-%s" (nth 0 case))))
              (let ((body-start (and block
                                     (save-excursion
                                       (goto-char (car block))
                                       (forward-line 1)
                                       (point)))))
                ;; The body must actually be expanded and contain the result text; an empty
                ;; range
                ;; would make the assertion vacuous
                (ert-info ((format "%s" (format "command-done-body-not-tinted-%s"
                                                (nth 1 case))))
                  (should (and block body-start (< body-start (cdr block))
                               (string-match-p (regexp-quote (nth 2 case))
                                               (buffer-substring-no-properties
                                                body-start (cdr block)))
                               (seq-every-p
                                (lambda (pos)
                                  (not (memq (nth 3 case) (dsh-test--faces-at pos))))
                                (number-sequence body-start (1- (cdr block))))))))))
        (kill-buffer buf)))))

;; --- Test 98a: command row styling --- result prefix + spinner lifecycle ---
(ert-deftest dsh-emacs-test-command-command-result-prefix-and-spinner-stopped ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-prefix*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 20)
             (data . ((commandId . "pfx1") (name . "compact") (args . "")))))
          (dsh-emacs-render-event
           '((type . "command/done") (seq . 21)
             (data . ((commandId . "pfx1") (kind . "success")
                      (text . "Compacted 174 history items")))))
          (let* ((txt (buffer-string))
                 (ns (dsh-emacs-render--make-namespace))
                 (block-id "cmd-pfx1")
                 (blk (dsh-emacs-ui-find-block ns block-id))
                 (state (and blk (get-text-property (car blk) 'dsh-emacs-ui-state))))
            (ert-info ((format "%s" "command-result-prefix-and-spinner-stopped"))
              (should (and (string-match-p "compact" txt)
                           (string-match-p "done" txt)
                           ;; The result is folded into the body
                           (not (string-match-p "Compacted 174 history items" txt))
                           state
                           (equal (map-elt state :body) "Compacted 174 history items")
                           (map-elt state :collapsed)
                           ;; done stopped the spinner (hash cleared + no leftover timer)
                           (null (gethash "pfx1" dsh-emacs--command-spinners)))))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

(ert-deftest dsh-emacs-test-command-command-spinner-starts ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-spin*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 30)
             (data . ((commandId . "spin1") (name . "goal")))))
          ;; run started the animation: the timer is running
          (ert-info ((format "%s" "command-spinner-starts"))
            (should (and (gethash "spin1" dsh-emacs--command-spinners)
                         (timerp (nth 1 (gethash "spin1" dsh-emacs--command-spinners))))))
          ;; Push 2 frames manually: the index advances and the label changes frame (timers
          ;; do not fire automatically in batch)
          (dsh-emacs--command-spinner-tick (current-buffer) "spin1")
          (dsh-emacs--command-spinner-tick (current-buffer) "spin1")
          (ert-info ((format "%s" "command-spinner-advances"))
            (should (= 2 (nth 2 (gethash "spin1" dsh-emacs--command-spinners)))))
          ;; done stops the clock: hash cleared
          (dsh-emacs-render-event
           '((type . "command/done") (seq . 31)
             (data . ((commandId . "spin1") (kind . "success")
                      (text . "ok")))))
          (ert-info ((format "%s" "command-spinner-done-stops"))
            (should (null (gethash "spin1" dsh-emacs--command-spinners)))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

(ert-deftest dsh-emacs-test-command-command-spinner-clear-all ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-clear*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 40)
             (data . ((commandId . "clear1") (name . "goal") (args . "")))))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 41)
             (data . ((commandId . "clear2") (name . "goal") (args . "")))))
          (dsh-emacs--command-spinner-clear-all)
          (ert-info ((format "%s" "command-spinner-clear-all"))
            (should (= 0 (hash-table-count dsh-emacs--command-spinners)))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; --- Test 98c: a running command row matches a tool row --- header line pending
;; coloring ---
(ert-deftest dsh-emacs-test-command-command-running-tints-header ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-tint*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 60)
             (data . ((commandId . "tint1") (name . "goal")))))
          (let* ((ns (dsh-emacs-render--make-namespace))
                 (block-id "cmd-tint1")
                 (blk (dsh-emacs-ui-find-block ns block-id))
                 (tinted (and blk
                              (seq-every-p
                               (lambda (pos)
                                 (memq 'dsh-emacs-tool-pending-face
                                       (ensure-list (get-text-property pos 'face))))
                               (number-sequence (car blk) (1- (cdr blk)))))))
            (ert-info ((format "%s" "command-running-tints-header"))
              (should tinted)))
          ;; The spinner tick rebuilds the whole line on every frame; the coloring must not
          ;; be lost
          (dsh-emacs--command-spinner-tick (current-buffer) "tint1")
          (let* ((ns (dsh-emacs-render--make-namespace))
                 (block-id "cmd-tint1")
                 (blk (dsh-emacs-ui-find-block ns block-id)))
            (ert-info ((format "%s" "command-running-tint-survives-tick"))
              (should (and blk
                           (seq-every-p
                            (lambda (pos)
                              (memq 'dsh-emacs-tool-pending-face
                                    (ensure-list (get-text-property pos 'face))))
                            (number-sequence (car blk) (1- (cdr blk)))))))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; --- Test 98d: an optimistic command row also carries header line pending
;; coloring ---
(ert-deftest dsh-emacs-test-command-command-optimistic-tints-header ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-opt-tint*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (let ((dsh-emacs-show-commands t)
                (dsh-emacs--command-blocks (make-hash-table :test 'equal))
                (dsh-emacs--pending-command nil)
                (dsh-emacs--command-spinners (make-hash-table :test 'equal)))
            (dsh-emacs-render-command-optimistic "/compact")
            (let* ((entry (gethash "pending-compact" dsh-emacs--command-blocks))
                   (blk (and entry
                             (dsh-emacs-ui-find-block (nth 0 entry) (nth 1 entry)))))
              (ert-info ((format "%s" "command-optimistic-tints-header"))
                (should (and blk
                             (seq-every-p
                              (lambda (pos)
                                (memq 'dsh-emacs-tool-pending-face
                                      (ensure-list (get-text-property pos 'face))))
                              (number-sequence (car blk) (1- (cdr blk))))))))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; --- Test 98e: the leading icon of a command row is the bash terminal (same as
;; tool rows) ---
(ert-deftest dsh-emacs-test-command-command-leading-icon-is-bash ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-bash-icon*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 70)
             (data . ((commandId . "bash1") (name . "goal")))))
          (let ((txt (buffer-string)))
            (ert-info ((format "%s" "command-leading-icon-is-bash"))
              (should (string-match-p "💻" txt))))
          ;; The bash icon is still kept after done
          (dsh-emacs--command-spinner-tick (current-buffer) "bash1")
          (dsh-emacs-render-event
           '((type . "command/done") (seq . 71)
             (data . ((commandId . "bash1") (kind . "success")
                      (text . "ok")))))
          (let ((txt (buffer-string)))
            (ert-info ((format "%s" "command-done-keeps-bash-icon"))
              (should (string-match-p "💻" txt)))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; In batch (non-graphical) the icon table gives a bash emoji fallback; the SVG
;; template exists for GUI rendering
(ert-deftest dsh-emacs-test-command-command-bash-icon-emoji-fallback ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "command-bash-icon-emoji-fallback"))
    (should (equal (cdr (assoc "bash" dsh-emacs--variant-icons)) "💻"))))

(ert-deftest dsh-emacs-test-command-command-bash-icon-svg-template ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "command-bash-icon-svg-template"))
    (should (assoc "bash" dsh-emacs--tool-icon-svgs))))

;; --- Test 98f: after a stream reconnect (disconnect+connect) revive a command
;; spinner that is still running ---
(ert-deftest dsh-emacs-test-command-command-spinner-revive-clear-all ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-revive*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 50)
             (data . ((commandId . "rv1") (name . "goal")))))
          ;; Simulate disconnect (reconnect/switch session) clearing all animations
          (dsh-emacs--command-spinner-clear-all)
          (ert-info ((format "%s" "command-spinner-revive-clear-all"))
            (should (= 0 (hash-table-count dsh-emacs--command-spinners))))
          ;; connect revives it: the row is still there in the same chat buffer and the
          ;; status is still pending
          (dsh-emacs--command-spinner-revive)
          (ert-info ((format "%s" "command-spinner-revive-restarts"))
            (should (and (gethash "rv1" dsh-emacs--command-spinners)
                         (timerp (nth 1 (gethash "rv1" dsh-emacs--command-spinners))))))
          ;; After revival it advances frames as usual
          (dsh-emacs--command-spinner-tick (current-buffer) "rv1")
          (dsh-emacs--command-spinner-tick (current-buffer) "rv1")
          (ert-info ((format "%s" "command-spinner-revive-advances"))
            (should (= 2 (nth 2 (gethash "rv1" dsh-emacs--command-spinners))))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; done already replaced the row with the success color (status != tool-pending):
;; revival must not restart it
(ert-deftest dsh-emacs-test-command-command-spinner-revive-skips-settled ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-revive-done*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 52)
             (data . ((commandId . "rv2") (name . "goal")))))
          (dsh-emacs-render-event
           '((type . "command/done") (seq . 53)
             (data . ((commandId . "rv2") (kind . "success")
                      (text . "ok")))))
          (dsh-emacs--command-spinner-clear-all)
          (dsh-emacs--command-spinner-revive)
          (ert-info ((format "%s" "command-spinner-revive-skips-settled"))
            (should (null (gethash "rv2" dsh-emacs--command-spinners)))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; The row has already been deleted (the entry remains): revival must not restart
;; the animation
(ert-deftest dsh-emacs-test-command-command-spinner-revive-skips-missing-block ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-revive-gone*"))
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (dsh-emacs-render-event
           '((type . "command/run") (seq . 54)
             (data . ((commandId . "rv3") (name . "goal")))))
          (when-let* ((entry (gethash "rv3" dsh-emacs--command-blocks))
                      (ns (nth 0 entry))
                      (block-id (nth 1 entry))
                      (blk (dsh-emacs-ui-find-block ns block-id)))
            (let ((inhibit-read-only t))
              (delete-region (car blk) (cdr blk))))
          (dsh-emacs--command-spinner-clear-all)
          (dsh-emacs--command-spinner-revive)
          (ert-info ((format "%s" "command-spinner-revive-skips-missing-block"))
            (should (null (gethash "rv3" dsh-emacs--command-spinners)))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; 98f2: events-connect (which reconnects also go through) really calls revive
(ert-deftest dsh-emacs-test-command-command-spinner-revive-wired-in-connect ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-connect-revive*"))
        (revives 0)
        (old-spinners dsh-emacs--command-spinners))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--command-spinners (make-hash-table :test 'equal))
          (cl-letf (((symbol-function 'open-network-stream)
                     (lambda (&rest _) (prog1 :fake-proc)))
                    ((symbol-function 'set-process-query-on-exit-flag)
                     (lambda (&rest _) nil))
                    ((symbol-function 'set-process-coding-system)
                     (lambda (&rest _) nil))
                    ((symbol-function 'process-put)
                     (lambda (&rest _) nil))
                    ((symbol-function 'set-process-filter)
                     (lambda (&rest _) nil))
                    ((symbol-function 'set-process-sentinel)
                     (lambda (&rest _) nil))
                    ((symbol-function 'dsh-emacs--command-spinner-revive)
                     (lambda () (setq revives (1+ revives)))))
            (dsh-emacs-events-connect buf)
            (dsh-emacs-events--health-stop))
          (ert-info ((format "%s" "command-spinner-revive-wired-in-connect"))
            (should (> revives 0))))
      (setq dsh-emacs--command-spinners old-spinners)
      (kill-buffer buf))))

;; --- Test 98a: optimistic command row rendering ---
(ert-deftest dsh-emacs-test-command-command-optimistic-creates-temp-entry ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-cmd-opt*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (let ((dsh-emacs-show-commands t)
                (dsh-emacs--command-blocks (make-hash-table :test 'equal))
                (dsh-emacs--pending-command nil)
                (dsh-emacs--command-spinners (make-hash-table :test 'equal)))
            (dsh-emacs-render-command-optimistic "/compact")
            ;; temp entry stored in command-blocks
            (let ((entry (gethash "pending-compact"
                                  dsh-emacs--command-blocks)))
              (ert-info ((format "%s" "command-optimistic-creates-temp-entry"))
                (should (and entry
                             dsh-emacs--pending-command
                             (equal (car dsh-emacs--pending-command) "pending-compact")))))))
      (kill-buffer buf))))

;; --- Test 98b: command/run replaces the optimistic row ---
(ert-deftest dsh-emacs-test-command-command-run-replaces-optimistic ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-show-commands t)
    (unwind-protect
        (let ((ns (dsh-emacs-render--make-namespace)))
          (dsh-emacs-render-command-optimistic "/compact")
          (should (gethash "pending-compact" dsh-emacs--command-blocks))
          (should (gethash "pending-compact" dsh-emacs--command-spinners))
          (should (dsh-emacs-ui-find-block ns "cmd-pending-compact"))
          (should (= 10 (dsh-emacs-render-event
                         '((type . "command/run") (seq . 10)
                           (data . ((commandId . "real-123")
                                    (name . "/compact") (args . "")))))))
          (should-not (gethash "pending-compact" dsh-emacs--command-blocks))
          (should-not (gethash "pending-compact" dsh-emacs--command-spinners))
          (should-not (dsh-emacs-ui-find-block ns "cmd-pending-compact"))
          (should-not dsh-emacs--pending-command)
          (should (gethash "real-123" dsh-emacs--command-blocks))
          (should (gethash "real-123" dsh-emacs--command-spinners))
          ;; Settlement keeps the run's label, even if done carries another.
          (should (= 11 (dsh-emacs-render-event
                         '((type . "command/done") (seq . 11)
                           (data . ((commandId . "real-123")
                                    (name . "unrelated") (kind . "error")
                                    (text . "Command rejected")))))))
          (should-not (gethash "real-123" dsh-emacs--command-spinners))
          (let* ((block (dsh-emacs-ui-find-block ns "cmd-real-123"))
                 (state (get-text-property (car block) 'dsh-emacs-ui-state)))
            (should (string-match-p "compact" (map-elt state :label-left)))
            (should-not (string-match-p "unrelated" (buffer-string)))
            (should (eq 'tool-error (map-elt state :status)))
            (should (equal "Command rejected" (map-elt state :body)))
            (should (map-elt state :collapsed)))
          (should (= 11 dsh-emacs--anchor-seq)))
      (dsh-emacs--command-spinner-clear-all))))

(ert-deftest dsh-emacs-test-command-ignored-events-preserve-pending-row ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-show-commands t)
    (unwind-protect
        (progn
          (dsh-emacs-render-command-optimistic "/compact")
          (let ((before (buffer-string))
                (pending dsh-emacs--pending-command)
                (spinner (gethash "pending-compact"
                                  dsh-emacs--command-spinners)))
            (should pending)
            (should spinner)
            (let ((dsh-emacs-show-commands nil))
              (should (= 11 (dsh-emacs-render-event
                             '((type . "command/run") (seq . 11)
                               (data . ((commandId . "hidden")
                                        (name . "goal")))))))
              (should (= 12 (dsh-emacs-render-event
                             '((type . "command/done") (seq . 12)
                               (data . ((commandId . "pending-compact")
                                        (kind . "error") (text . "Hidden"))))))))
            ;; Missing ids and unmatched results are consumed without a row.
            (should (= 13 (dsh-emacs-render-event
                           '((type . "command/run") (seq . 13)
                             (data . ((name . "goal")))))))
            (should (= 14 (dsh-emacs-render-event
                           '((type . "command/done") (seq . 14)
                             (data . ((commandId . "missing")
                                      (kind . "error") (text . "Orphan")))))))
            (should (equal before (buffer-string)))
            (should (eq pending dsh-emacs--pending-command))
            (should (eq spinner (gethash "pending-compact"
                                        dsh-emacs--command-spinners)))
            (should (= 1 (hash-table-count dsh-emacs--command-blocks)))
            (should (= 1 (hash-table-count dsh-emacs--command-spinners)))
            (should (= 14 dsh-emacs--anchor-seq))))
      (dsh-emacs--command-spinner-clear-all))))

(ert-deftest dsh-emacs-test-command-command-menu-hint-prompts-args ()
  :tags '(dsh-unit)
  (let ((calls nil)
        (read-called nil)
        (dsh-emacs--current-session "sess-menu"))
    (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
               (lambda (_m _p)
                 (cons t [((name . "goal") (description . "goal ops")
                           (input . ((hint . "[<objective>]"))))
                          ((name . "compact") (description . "compact"))])))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "/goal"))
              ((symbol-function 'read-string)
               (lambda (&rest _) (setq read-called t) "set x"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method params cb)
                 (push (list method params) calls)
                 (funcall cb t '((commandId . "c3")
                                 (result . ((kind . "success")
                                            (text . "t"))))))))
      (dsh-emacs-command)
      (let* ((call (car calls))
             (params (cadr call)))
        (ert-info ((format "%s" "command-menu-hint-prompts-args"))
          (should (and (string= "commands/execute" (car call))
                       (string= "/goal set x" (cdr (assq 'line params)))
                       read-called)))))))

(ert-deftest dsh-emacs-test-command-command-menu-bare-no-args ()
  :tags '(dsh-unit)
  (let ((calls nil)
        (read-called nil)
        (dsh-emacs--current-session "sess-menu2"))
    (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
               (lambda (_m _p)
                 (cons t [((name . "compact") (description . "compact"))])))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "/compact"))
              ((symbol-function 'read-string)
               (lambda (&rest _) (setq read-called t) "x"))
              ((symbol-function 'dsh-emacs--rpc-async)
               (lambda (method params cb)
                 (push (list method params) calls)
                 (funcall cb t '((commandId . "c4")
                                 (result . ((kind . "success")
                                            (text . "t"))))))))
      (dsh-emacs-command)
      (let* ((call (car calls))
             (params (cadr call)))
        (ert-info ((format "%s" "command-menu-bare-no-args"))
          (should (and (string= "commands/execute" (car call))
                       (string= "/compact" (cdr (assq 'line params)))
                       (null read-called))))))))

(provide 'dsh-test-command)
;;; dsh-test-command.el ends here

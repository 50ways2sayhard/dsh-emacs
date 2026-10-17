;;; dsh-test-recall.el --- Recall tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)

;; --- Test 52: input history M-p / M-n ---
;; Pinned to cross-session mode on purpose: this test exercises the browse
;; mechanics over the shared list (the new default is per-session; see 52b).
(ert-deftest dsh-emacs-test-recall-input-history-back-shows-newest ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (dsh-emacs-input-history-cross-session t)
        (buf (generate-new-buffer " *dsh-hist-test*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs--push-input-history "first")
          (dsh-emacs--push-input-history "second")
          (dsh-emacs--replace-input "typed")
          (dsh-emacs-input-history-back)          ; newest "second"
          (ert-info ((format "%s" "input-history-back-shows-newest"))
            (should (string= "second" (dsh-emacs--get-input))))
          (dsh-emacs-input-history-back)          ; older "first"
          (ert-info ((format "%s" "input-history-back-older"))
            (should (string= "first" (dsh-emacs--get-input))))
          (dsh-emacs-input-history-forward)       ; back to "second"
          (ert-info ((format "%s" "input-history-forward-newer"))
            (should (string= "second" (dsh-emacs--get-input))))
          (dsh-emacs-input-history-forward)       ; restores pre-browse "typed" input
          (ert-info ((format "%s" "input-history-forward-restores-pending"))
            (should (string= "typed" (dsh-emacs--get-input)))))
      (kill-buffer buf))))

;; --- Test 53: enters history after submit (submit pushes back +
;; state resets) ---
(ert-deftest dsh-emacs-test-recall-submit-prompt-records-history-and-resets ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (buf (generate-new-buffer " *dsh-hist2-test*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--current-session "sess-h")
          (setq dsh-emacs--input-history-pos 0)   ; pretend to be in browsing state
          (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                     (lambda (method params cb) (funcall cb t '((accepted . t))))))
            (dsh-emacs--submit-prompt "submitted text"))
          (ert-info ((format "%s" "submit-prompt-records-history-and-resets"))
            (should (and (string= "submitted text" (car dsh-emacs--input-history))
                         (null dsh-emacs--input-history-pos)))))
      (kill-buffer buf))))

;; --- Test 52b: per-session history — with cross-session off, M-p/M-n only recall this session ---
;; Regression: history used to be a single global list, so M-p/M-n in any
;; session could surface other sessions' messages.  With
;; `dsh-emacs-input-history-cross-session' nil, recall is isolated per
;; session; every submit still lands in BOTH scopes (global + own session),
;; so toggling the option never loses history.
(ert-deftest dsh-emacs-test-recall-per-session-history-b-newest ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (dsh-emacs-input-history-cross-session nil)
        (buf-a (generate-new-buffer " *dsh-hist-a*"))
        (buf-b (generate-new-buffer " *dsh-hist-b*")))
    (unwind-protect
        (progn
          (setq dsh-emacs-input-history-cross-session nil)
          (with-current-buffer buf-a
            (dsh-emacs-mode)
            (setq-local dsh-emacs--buffer-session "sess-a")
            (dsh-emacs--push-input-history "a1")
            (dsh-emacs--push-input-history "a2"))
          (with-current-buffer buf-b
            (dsh-emacs-mode)
            (setq-local dsh-emacs--buffer-session "sess-b")
            (dsh-emacs--push-input-history "b1")
            ;; B sees only its own submissions: newest is b1, not the global a2
            (dsh-emacs-input-history-back)
            (ert-info ((format "%s" "per-session-history-b-newest"))
              (should (string= "b1" (dsh-emacs--get-input))))
            ;; Back again: B has nothing older — the input stays b1
            (dsh-emacs-input-history-back)
            (ert-info ((format "%s" "per-session-history-b-exhausted"))
              (should (string= "b1" (dsh-emacs--get-input)))))
          ;; A's recall is still its own: newest is a2 (browsing B never
          ;; shifted A's browse position)
          (with-current-buffer buf-a
            (dsh-emacs-input-history-back)
            (ert-info ((format "%s" "per-session-history-a-newest"))
              (should (string= "a2" (dsh-emacs--get-input)))))
          ;; Double-write: the shared global list still accumulates, so
          ;; switching back to cross-session mode recalls everything again.
          (ert-info ((format "%s" "per-session-records-global-too"))
            (should (string= "b1" (car dsh-emacs--input-history)))))


      (kill-buffer buf-a)
      (kill-buffer buf-b))))

;; --- Test 52c: cross-session mode recalls the shared history ---
(ert-deftest dsh-emacs-test-recall-cross-session-back-shows-shared-newest ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (dsh-emacs-input-history-cross-session nil)
        (buf (generate-new-buffer " *dsh-hist-cross*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq-local dsh-emacs--buffer-session "sess-c")
          (setq dsh-emacs-input-history-cross-session t)
          (dsh-emacs--push-input-history "global-1")
          (dsh-emacs-input-history-back)
          (ert-info ((format "%s" "cross-session-back-shows-shared-newest"))
            (should (string= "global-1" (dsh-emacs--get-input)))))
      (kill-buffer buf))))

;; --- Test 52d: first entry into a session recalls history (backfill) ---
;; Regression: per-session history only held prompts submitted in the
;; current Emacs run, so entering an existing session left M-p/M-n empty.
;; Fix: loading history backfills the session's recall list from the
;; user/message texts in the window (texts already present are skipped, so
;; reloading never duplicates; the shared cross-session list is untouched).
(ert-deftest dsh-emacs-test-recall-seed-fills-per-session-newest-first ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (dsh-emacs-input-history-cross-session nil)
        (buf (generate-new-buffer " *dsh-seed-test*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq-local dsh-emacs--buffer-session "sess-seed")
          (setq dsh-emacs-input-history-cross-session nil)
          ;; History window: old → assistant → newer (seq ascending, wire order)
          (dsh-emacs--seed-input-history
           '((("event" . ((type . "user/message") (seq . 1)
                          (data . ((content . [((type . "text") (text . "old"))]))))))
             (("event" . ((type . "assistant/message") (seq . 2)
                          (data . ((turn . 1))))))
             (("event" . ((type . "user/message") (seq . 3)
                          (data . ((content . [((type . "text") (text . "newer"))])))))))
           "sess-seed")
          (ert-info ((format "%s" "seed-fills-per-session-newest-first"))
            (should (equal '("newer" "old")
                           (gethash "sess-seed" dsh-emacs--input-history-by-session))))
          ;; Reloading the same window: texts already present are all skipped,
          ;; the list stays unchanged
          (dsh-emacs--seed-input-history
           '((("event" . ((type . "user/message") (seq . 1)
                          (data . ((content . [((type . "text") (text . "old"))]))))))
             (("event" . ((type . "user/message") (seq . 3)
                          (data . ((content . [((type . "text") (text . "newer"))])))))))
           "sess-seed")
          (ert-info ((format "%s" "seed-idempotent-on-reload"))
            (should (equal '("newer" "old")
                           (gethash "sess-seed" dsh-emacs--input-history-by-session))))
          ;; Seeding never touches the shared cross-session list
          (ert-info ((format "%s" "seed-untouches-global-list"))
            (should (null (member "old" dsh-emacs--input-history))))
          ;; Browsing: per-session M-p jumps straight to the newest recalled message
          (dsh-emacs-input-history-back)
          (ert-info ((format "%s" "seed-recallable-via-M-p"))
            (should (string= "newer" (dsh-emacs--get-input)))))

      (kill-buffer buf))))

;; --- Test 52d-2: recall backfill records text-only prompts only: a message
;; carrying an image — including the paste path's synthesized caption — is
;; not replayable as text, so it never enters M-p ---
(ert-deftest dsh-emacs-test-recall-seed-skips-attachment-prompts ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (dsh-emacs-input-history-cross-session nil)
        (buf (generate-new-buffer " *dsh-seed-image*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq-local dsh-emacs--buffer-session "sess-seed-image")
          (setq dsh-emacs-input-history-cross-session nil)
          (dsh-emacs--seed-input-history
           '((("event" . ((type . "user/message") (seq . 1)
                          (data . ((content .
                                            [((type . "text") (text . "words"))]))))))
             (("event" . ((type . "user/message") (seq . 2)
                          (data . ((content .
                                            [((type . "text") (text . "shot.png"))
                                             ((type . "image")
                                              (mediaType . "image/png")
                                              (name . "shot.png"))]))))))
             (("event" . ((type . "user/message") (seq . 3)
                          (data . ((content .
                                            [((type . "image")
                                              (mediaType . "image/png")
                                              (name . "bare.png"))])))))))
           "sess-seed-image")
          (ert-info ((format "%s" "seed-skips-attachment-prompts"))
            (should (equal '("words")
                           (gethash "sess-seed-image"
                                    dsh-emacs--input-history-by-session)))))

      (kill-buffer buf))))

;; --- Test 52e: opening a session (follow snapshot) seeds recall for M-p/M-n ---
(ert-deftest dsh-emacs-test-recall-follow-snapshot-seeds-recall ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (dsh-emacs-input-history-cross-session nil)
        (buf (generate-new-buffer " *dsh-seed-load*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq-local dsh-emacs--buffer-session "sess-load")
          (setq dsh-emacs-input-history-cross-session nil)
          ;; The `session/follow' snapshot is the opening history seed now: it
          ;; renders the records and backfills the per-session M-p/M-n recall.
          (dsh-emacs-events--follow-snapshot
           (current-buffer)
           '((type . "snapshot")
             (cursor . 10)
             (records .
                      [((type . "event")
                        (event . ((type . "user/message") (seq . 10)
                                  (data . ((content .
                                                    [((type . "text")
                                                      (text . "hist-1"))]))))))])))
          (dsh-emacs-input-history-back)
          (ert-info ((format "%s" "follow-snapshot-seeds-recall"))
            (should (and (string= "hist-1" (dsh-emacs--get-input))
                         (equal '("hist-1")
                                (gethash "sess-load" dsh-emacs--input-history-by-session))))))

      (kill-buffer buf))))

;; --- Test 52f: host-injected user messages never enter M-p recall ---
;; Regression: the host appends its own model-facing `user/message' copies
;; (workspace instructions, runtime-context snapshots, goal/subagent
;; notices) to the same surface, naming their origin in `data.source.kind'.
;; The transcript already hides them, but the history seeder took every
;; user/message, so M-p recalled a `<system-reminder>' wall of text the
;; user never typed.
(ert-deftest dsh-emacs-test-recall-seed-skips-host-injected-user-messages ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--input-history nil)
        (dsh-emacs--input-history-by-session (make-hash-table :test #'equal))
        (dsh-emacs--current-session nil)
        (dsh-emacs-input-history-cross-session nil)
        (buf (generate-new-buffer " *dsh-seed-injected*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq-local dsh-emacs--buffer-session "sess-injected")
          (setq dsh-emacs-input-history-cross-session nil)
          (dsh-emacs--seed-input-history
           '((("event" . ((type . "user/message") (seq . 1)
                          (data . ((content . [((type . "text")
                                                (text . "real prompt"))]))))))
             (("event" . ((type . "user/message") (seq . 2)
                          (data . ((content .
                                            [((type . "text")
                                              (text . "<system-reminder>AGENTS.md</system-reminder>"))])
                                   (source . ((kind . "agent-instructions"))))))))
             (("event" . ((type . "user/message") (seq . 3)
                          (data . ((content .
                                            [((type . "text")
                                              (text . "Current runtime context."))])
                                   (source . ((kind . "plugin"))))))))
             (("event" . ((type . "user/message") (seq . 4)
                          (data . ((content . [((type . "text")
                                                (text . "legacy no-source"))])))))))
           "sess-injected")
          (ert-info ((format "%s" "seed-skips-host-injected-user-messages"))
            (should (equal '("legacy no-source" "real prompt")
                           (gethash "sess-injected" dsh-emacs--input-history-by-session))))
          ;; The reported symptom: M-p lands on the recalled prompt, never on
          ;; an injected reminder
          (dsh-emacs-input-history-back)
          (ert-info ((format "%s" "seed-recall-never-offers-a-system-reminder"))
            (should (and (string= "legacy no-source" (dsh-emacs--get-input))
                         (null (cl-find-if
                                (lambda (entry)
                                  (string-match-p "\\`<system-reminder>" entry))
                                (gethash "sess-injected"
                                         dsh-emacs--input-history-by-session)))))))

      (kill-buffer buf))))

(provide 'dsh-test-recall)
;;; dsh-test-recall.el ends here

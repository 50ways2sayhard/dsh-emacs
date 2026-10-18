;;; dsh-test-protocol.el --- Protocol tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)

(ert-deftest dsh-emacs-test-protocol-session-title-event ()
  :tags '(dsh-unit)
  (dolist (wire '(((type . "session/title") (data (title . "Renamed")))
                  (("type" . "session/title")
                   ("data" ("title" . "Renamed")))))
    (should (equal "Renamed"
                   (dsh-protocol-session-title-title
                    (dsh-protocol-session-title--from-alist wire)))))
  ;; Absence is distinct from an unrelated event: callers still record it.
  (let ((view (dsh-protocol-session-title--from-alist
               '((type . "session/title")))))
    (should (dsh-protocol-session-title-p view))
    (should-not (dsh-protocol-session-title-title view)))
  (should-not (dsh-protocol-session-title--from-alist
               '((type . "assistant/message") (data (title . "Ignore"))))))

(ert-deftest dsh-emacs-test-protocol-deliverables-event ()
  :tags '(dsh-unit)
  (dolist (wire
           '(((seq . 17) (data (turn . 4)
                               (files . [((path . "a.md") (description . "old"))
                                         ((path . "a.md") (description . "new"))
                                         ((path . "b.txt") (description . ""))
                                         ((path . "c.txt") (description . 42))
                                         ((path . "") (description . "drop"))
                                         ((path . 42)) nil "invalid"])))
             (("seq" . 17) ("data" ("turn" . 4)
                            ("files" . [(("path" . "a.md") ("description" . "old"))
                                        (("path" . "a.md") ("description" . "new"))
                                        (("path" . "b.txt"))
                                        (("path" . "c.txt"))])))))
    (let ((view (dsh-protocol-deliverables--from-alist wire)))
      (should (= 17 (dsh-protocol-deliverables-seq view)))
      (should (= 4 (dsh-protocol-deliverables-turn view)))
      (should (equal '(("a.md" . "old") ("a.md" . "new")
                       ("b.txt") ("c.txt"))
                     (dsh-protocol-deliverables-files view)))))
  (let ((view (dsh-protocol-deliverables--from-alist '((seq . 19)))))
    (should (= 19 (dsh-protocol-deliverables-seq view)))
    (should-not (dsh-protocol-deliverables-turn view))
    (should-not (dsh-protocol-deliverables-files view))))

(ert-deftest dsh-emacs-test-protocol-command-event-fields ()
  :tags '(dsh-unit)
  (dolist (keys '((type data commandId name kind text)
                  ("type" "data" "commandId" "name" "kind" "text")))
    (dolist (type '("command/run" "command/done"))
      (pcase-let* ((`(,type-key ,data-key ,id-key ,name-key ,kind-key ,text-key)
                    keys)
                   (text "First line\nSecond line")
                   (decoded
                    (dsh-protocol-command-event--from-alist
                     (list (cons type-key type)
                           (cons data-key
                                 (list (cons id-key "cmd-7")
                                       (cons name-key "/compact")
                                       (cons kind-key "future-outcome")
                                       (cons text-key text)))))))
        (should (equal type (dsh-protocol-command-event-type decoded)))
        (should (equal "cmd-7" (dsh-protocol-command-event-command-id decoded)))
        (should (equal "/compact" (dsh-protocol-command-event-name decoded)))
        (should (equal "future-outcome" (dsh-protocol-command-event-kind decoded)))
        (should (eq text (dsh-protocol-command-event-text decoded))))))
  (let ((decoded (dsh-protocol-command-event--from-alist
                  '((type . "command/done")))))
    (should (equal "command/done" (dsh-protocol-command-event-type decoded)))
    (should-not (dsh-protocol-command-event-command-id decoded))
    (should-not (dsh-protocol-command-event-name decoded))
    (should-not (dsh-protocol-command-event-kind decoded))
    (should-not (dsh-protocol-command-event-text decoded))))

(ert-deftest dsh-emacs-test-protocol-tool-call-retains-opaque-arguments ()
  :tags '(dsh-unit)
  (dolist (keys '((name callId arguments) ("name" "callId" "arguments")))
    (dolist (args '("{\"command\":\"printf protocol\"}" "invalid JSON"
                    ((unexpected . t)) nil))
      (pcase-let* ((`(,name-key ,id-key ,args-key) keys)
                   (call (dsh-protocol-tool-call--from-alist
                          (list (cons name-key "bash") (cons id-key "call-7")
                                (cons args-key args)))))
        (should (equal "bash" (dsh-protocol-tool-call-name call)))
        (should (equal "call-7" (dsh-protocol-tool-call-call-id call)))
        (should (eq args (dsh-protocol-tool-call-arguments call))))))
  (let ((call (dsh-protocol-tool-call--from-alist nil)))
    (should-not (dsh-protocol-tool-call-name call))
    (should-not (dsh-protocol-tool-call-call-id call))
    (should-not (dsh-protocol-tool-call-arguments call))))

(ert-deftest dsh-emacs-test-protocol-mux-frame-preserves-logical-payloads ()
  :tags '(dsh-unit)
  (let* ((payload '((type . "event") (records . [((seq . 3))])))
         (failure '((code . "unavailable") (message . "Retry later")))
         (item (dsh-protocol-mux-frame--from-alist
                `((type . "item") (streamId . "follow-1") (value . ,payload))))
         (err (dsh-protocol-mux-frame--from-alist
               `(("type" . "error") ("streamId" . "jobs-1")
                 ("error" . ,failure))))
         (end (dsh-protocol-mux-frame--from-alist
               '((type . "end") (streamId . "follow-1")))))
    (should (equal "item" (dsh-protocol-mux-frame-type item)))
    (should (equal "follow-1" (dsh-protocol-mux-frame-stream-id item)))
    (should (eq payload (dsh-protocol-mux-frame-value item)))
    (should-not (dsh-protocol-mux-frame-error item))
    (should (equal "error" (dsh-protocol-mux-frame-type err)))
    (should (equal "jobs-1" (dsh-protocol-mux-frame-stream-id err)))
    (should (eq failure (dsh-protocol-mux-frame-error err)))
    (should-not (dsh-protocol-mux-frame-value err))
    (should (equal "end" (dsh-protocol-mux-frame-type end)))
    (should (equal "follow-1" (dsh-protocol-mux-frame-stream-id end)))
    (should-not (dsh-protocol-mux-frame-value end))
    (should-not (dsh-protocol-mux-frame-error end))))

(ert-deftest dsh-emacs-test-protocol-follow-snapshot-normalizes-the-whole-window ()
  :tags '(dsh-unit)
  (dolist (key-type '(symbol string))
    (dolist (array-type '(vector list))
      (let* ((json-key-type key-type)
             (json-array-type array-type)
             (json-object-type 'alist)
             (json-false :json-false)
             (wire
              (json-read-from-string
               (json-encode
                '((cursor . -1) (hasMore . t)
                  (records . [9
                              ((type . "event")
                               (event . ((type . "compaction/start") (seq . 8)
                                         (data . ((compactionId . "whole"))))))
                              ((type . "other")
                               (event . ((type . "llm/retry") (seq . 7)
                                         (data . ((retryId . "retry"))))))
                              ((type . "event")
                               (event . ((type . "user/message") (seq . 8))))
                              ((type . "event")
                               (event . ((type . "turn/end") (seq . 3))))])
                  (projections . ((asOfSeq . 31)
                                  (values . ((plan . ((active . :json-false)
                                                      (pending . t)))))))
                  (assistantStream
                   . ((revision . 9)
                      (activeAttempt
                       . ((attemptId . "attempt") (turn . 2) (step . 3)
                          (nextIndex . 2)
                          (stream . [((type . "text-chunks") (index . 0)
                                      (texts . ["Hello" " world"]))])))))))))
             (raw-records (append (dsh-protocol--field 'records wire) nil))
             (snapshot (dsh-protocol-follow-snapshot--from-alist wire))
             (records (dsh-protocol-follow-snapshot-records snapshot))
             (execution (dsh-protocol-follow-snapshot-execution snapshot))
             (plan (dsh-protocol-follow-snapshot-plan snapshot))
             (assistant (dsh-protocol-follow-snapshot-assistant snapshot)))
        (ert-info ((format "keys=%s arrays=%s" key-type array-type))
          ;; Follow snapshots retain duplicates and non-increasing sequence
          ;; numbers; strict page validation belongs to history pagination.
          (should (= -1 (dsh-protocol-follow-snapshot-cursor snapshot)))
          (should (eq t (dsh-protocol-follow-snapshot-has-more snapshot)))
          (should (= 3 (length records)))
          (should (eq (nth 0 records) (nth 1 raw-records)))
          (should (eq (nth 1 records) (nth 3 raw-records)))
          (should (eq (nth 2 records) (nth 4 raw-records)))
          ;; Execution consumes the entire object window, including records
          ;; not selected as transcript entries and those below an anchor.
          (should (equal (mapcar #'dsh-protocol-execution-event-type execution)
                         '("compaction/start" "llm/retry" "turn/end")))
          (should (equal (mapcar #'dsh-protocol-execution-event-seq execution)
                         '(8 7 3)))
          (should (eq (dsh-protocol-follow-snapshot-projections snapshot)
                      (dsh-protocol--field 'projections wire)))
          (should-not (dsh-protocol-plan-active plan))
          (should (dsh-protocol-plan-pending plan))
          (should (= 31 (dsh-protocol-plan-seq plan)))
          (should (= 9 (dsh-protocol-assistant-baseline-revision assistant)))
          (should (equal "attempt"
                         (dsh-protocol-assistant-baseline-attempt-id assistant)))
          (should (= 2 (dsh-protocol-assistant-baseline-next-index assistant)))
          (should (equal '("Hello" " world")
                         (dsh-protocol-assistant-record-texts
                          (car (dsh-protocol-assistant-baseline-stream
                                assistant))))))))))

(ert-deftest dsh-emacs-test-protocol-follow-snapshot-retains-absence-watermark ()
  :tags '(dsh-unit)
  (dolist (case '((nil nil nil)
                  (((cursor . -1) (records . []) (hasMore . :json-false)
                    (projections . ((asOfSeq . 17) (values))))
                   -1 17)))
    (pcase-let* ((`(,wire ,cursor ,seq) case)
                 (snapshot (dsh-protocol-follow-snapshot--from-alist wire))
                 (plan (dsh-protocol-follow-snapshot-plan snapshot))
                 (assistant (dsh-protocol-follow-snapshot-assistant snapshot)))
      (should (equal cursor (dsh-protocol-follow-snapshot-cursor snapshot)))
      (should-not (dsh-protocol-follow-snapshot-records snapshot))
      (should-not (dsh-protocol-follow-snapshot-has-more snapshot))
      (should-not (dsh-protocol-follow-snapshot-execution snapshot))
      (should (dsh-protocol-plan-p plan))
      (should (equal seq (dsh-protocol-plan-seq plan)))
      (should-not (dsh-protocol-plan-available plan))
      (should (dsh-protocol-assistant-baseline-p assistant))
      (should-not (dsh-protocol-assistant-baseline-revision assistant))
      (should-not (dsh-protocol-assistant-baseline-attempt-id assistant))
      (should-not (dsh-protocol-assistant-baseline-stream assistant)))))

(ert-deftest dsh-emacs-test-protocol-follow-item-selects-typed-payloads ()
  :tags '(dsh-unit)
  (let* ((event '((type . "assistant/message") (seq . 8)))
         (chunk '((type . "text-delta") (index . 0) (text . "live")))
         (durable (dsh-protocol-follow-item--from-alist
                   `((type . "event") (event . ,event))))
         (snapshot (dsh-protocol-follow-item--from-alist
                    '((type . "snapshot") (cursor . -1) (records . []))))
         (stream (dsh-protocol-follow-item--from-alist
                  `(("type" . "assistant-stream")
                    ("frame" . (("type" . "chunk") ("revision" . 9)
                                ("attemptId" . "attempt") ("index" . 2)
                                ("chunk" . ,chunk))))))
         (frame (dsh-protocol-follow-item-payload stream)))
    (should (equal "event" (dsh-protocol-follow-item-type durable)))
    (should (eq event (dsh-protocol-follow-item-payload durable)))
    (should (dsh-protocol-follow-snapshot-p
             (dsh-protocol-follow-item-payload snapshot)))
    (should (= -1 (dsh-protocol-follow-snapshot-cursor
                   (dsh-protocol-follow-item-payload snapshot))))
    (should (equal "assistant-stream" (dsh-protocol-follow-item-type stream)))
    (should (dsh-protocol-assistant-frame-p frame))
    (should (equal "chunk" (dsh-protocol-assistant-frame-type frame)))
    (should (= 9 (dsh-protocol-assistant-frame-revision frame)))
    (should (equal "attempt" (dsh-protocol-assistant-frame-attempt-id frame)))
    (should (= 2 (dsh-protocol-assistant-frame-index frame)))
    (should (eq chunk (dsh-protocol-assistant-frame-chunk frame)))
    (should-not (dsh-protocol-follow-item-payload
                 (dsh-protocol-follow-item--from-alist
                  `(("type" . "future-item") ("event" . ,event))))))
  (dolist (invalid '(nil 7 "bad" ["bad"]))
    (let ((frame (dsh-protocol-follow-item-payload
                  (dsh-protocol-follow-item--from-alist
                   `((type . "assistant-stream") (frame . ,invalid))))))
      (should (dsh-protocol-assistant-frame-p frame))
      (should-not (dsh-protocol-assistant-frame-type frame))
      (should-not (dsh-protocol-assistant-frame-revision frame))
      (should-not (dsh-protocol-assistant-frame-chunk frame)))))

(ert-deftest dsh-emacs-test-protocol-follow-projections-decode-known-values ()
  :tags '(dsh-unit)
  (let* ((baseline
          '((asOfSeq . 23)
            (values . ((userQuestions
                        . ((active . [((callId . "pending")
                                        (state . "continued")
                                        (questions . []))])
                           (settled . [])))
                       (goal . ((goal . ((objective . "Continue work")
                                         (phase . "active")))
                                (roundsStarted . 3)))
                       (permissions . ((currentValue . " host ")))
                       (contextPressure . ((pressureTokens . 20)
                                           (projectedTokens . 25)
                                           (contextWindow . 100)))
                       (title . "Snapshot title")
                       (subagentCatalog . [])
                       (tokenUsage . ((outputTokens . 5)))
                       (plan . ((active . t)))
                       (inbox . ((next-turn . [])))
                       (futureCell . ((nested . [1 2])))))))
         (view (dsh-protocol-follow-projections--from-alist baseline))
         (subagents (dsh-protocol-follow-projections-subagents view))
         (context (dsh-protocol-follow-projections-context view))
         (goal (dsh-protocol-follow-projections-goal view))
         (questions (dsh-protocol-follow-projections-questions view)))
    (should (equal "Snapshot title" (dsh-protocol-follow-projections-title view)))
    (should (equal '(20 25 100)
                   (list (dsh-protocol-context-pressure-pressure context)
                         (dsh-protocol-context-pressure-projected context)
                         (dsh-protocol-context-pressure-window context))))
    (should (equal " host " (dsh-protocol-follow-projections-permission view)))
    (should (dsh-protocol-follow-projections-goal-update-p view))
    (should (equal "Continue work" (dsh-protocol-goal-objective goal)))
    (should (= 3 (dsh-protocol-goal-rounds-started goal)))
    (should (= 23 (dsh-protocol-user-questions-seq questions)))
    (should (equal '("pending")
                   (mapcar #'dsh-protocol-pending-question-call-id
                           (dsh-protocol-user-questions-active questions))))
    (should (equal '(subagentCatalog subagent subagentTiming tokenUsage)
                   (mapcar #'dsh-protocol-subagent-cell-key subagents)))
    (should (equal '(23 23 23 23)
                   (mapcar #'dsh-protocol-subagent-cell-seq subagents)))
    (should (equal '(t nil nil t)
                   (mapcar #'dsh-protocol-subagent-cell-present subagents)))
    (should (= 5 (dsh-protocol-token-usage-output
                  (dsh-protocol-subagent-cell-value (car (last subagents))))))))

(ert-deftest dsh-emacs-test-protocol-follow-projections-distinguish-goal-clear ()
  :tags '(dsh-unit)
  (dolist (case
           '((nil t nil)
             (((asOfSeq . 17)) t 17)
             (((asOfSeq . 17) (values)) t 17)
             (((asOfSeq . 17) (values (goal . nil))) t 17)
             (((asOfSeq . 17) (values (goal . :json-false))) nil 17)
             (((asOfSeq . 17) (values (goal . "invalid"))) nil 17)
             (((asOfSeq . 17) (values (goal . 42))) nil 17)
             (((asOfSeq . 17) (values (goal . []))) nil 17)))
    (pcase-let* ((`(,baseline ,clear-p ,seq) case)
                 (view (dsh-protocol-follow-projections--from-alist baseline))
                 (questions (dsh-protocol-follow-projections-questions view)))
      (ert-info ((format "baseline=%S" baseline))
        ;; A nil decoded goal alone cannot distinguish a clear from a skip.
        (should (eq clear-p (dsh-protocol-follow-projections-goal-update-p view)))
        (should-not (dsh-protocol-follow-projections-goal view))
        (should (dsh-protocol-user-questions-p questions))
        (should (equal seq (dsh-protocol-user-questions-seq questions)))
        (should-not (dsh-protocol-user-questions-active questions))
        (should-not (dsh-protocol-user-questions-settled questions))))))

(ert-deftest dsh-emacs-test-protocol-follow-projections-retain-catalog-presence ()
  :tags '(dsh-unit)
  (dolist (case
           '((nil -1 nil)
             (((asOfSeq . 31) (values)) 31 nil)
             (((asOfSeq . 31) (values (subagentCatalog . []))) 31 t)
             (((asOfSeq . 31) (values (subagentCatalog . nil))) 31 t)))
    (pcase-let* ((`(,baseline ,seq ,present) case)
                 (view (dsh-protocol-follow-projections--from-alist baseline))
                 (cells (dsh-protocol-follow-projections-subagents view)))
      (ert-info ((format "baseline=%S" baseline))
        (should (equal '(subagentCatalog subagent subagentTiming tokenUsage)
                       (mapcar #'dsh-protocol-subagent-cell-key cells)))
        (should (equal (make-list 4 seq)
                       (mapcar #'dsh-protocol-subagent-cell-seq cells)))
        (should (equal (list present nil nil nil)
                       (mapcar #'dsh-protocol-subagent-cell-present cells)))
        (should (equal '(nil nil nil nil)
                       (mapcar #'dsh-protocol-subagent-cell-value cells)))))))

(ert-deftest dsh-emacs-test-protocol-follow-snapshot-defers-migration-error ()
  :tags '(dsh-unit)
  (let* ((baseline '((kind . "migration-required")
                     (values (subagentCatalog . []))))
         (snapshot (dsh-protocol-follow-snapshot--from-alist
                    `((cursor . 9) (records . [])
                      (projections . ,baseline)))))
    ;; Opening views are decoded before history; this boundary must stay late.
    (should (dsh-protocol-follow-snapshot-p snapshot))
    (should (= 9 (dsh-protocol-follow-snapshot-cursor snapshot)))
    (should (eq baseline (dsh-protocol-follow-snapshot-projections snapshot)))
    (should-error (dsh-protocol-follow-projections--from-alist baseline)
                  :type 'dsh-protocol-migration-required)))

(ert-deftest dsh-emacs-test-protocol-context-pressure-preserves-raw-sample ()
  :tags '(dsh-unit)
  (dolist (keys '((pressureTokens projectedTokens contextWindow)
                  ("pressureTokens" "projectedTokens" "contextWindow")))
    (dolist (sample '((0 321 1000) (:json-false "raw" -1)))
      (pcase-let* ((`(,pressure-key ,projected-key ,window-key) keys)
                   (`(,pressure ,projected ,window) sample)
                   (view (dsh-protocol-context-pressure--from-alist
                          (list (cons pressure-key pressure)
                                (cons projected-key projected)
                                (cons window-key window)))))
        ;; Decoding must not choose a display estimate or discard a sample;
        ;; the consumer owns the raw-pressure trust guard.
        (should (equal pressure (dsh-protocol-context-pressure-pressure view)))
        (should (equal projected (dsh-protocol-context-pressure-projected view)))
        (should (equal window (dsh-protocol-context-pressure-window view))))))
  (let ((session
         (dsh-protocol-session--from-alist
          '((sessionId . "context")
            (projections
             . ((values . ((contextPressure
                            . ((pressureTokens . 7) (projectedTokens . 11)
                               (contextWindow . 97)))))))))))
    (should (equal '(7 11 97)
                   (list (dsh-protocol-session-context-pressure session)
                         (dsh-protocol-session-context-projected session)
                         (dsh-protocol-session-context-window session)))))
  (dolist (wire '(nil :json-false 7 "not-an-object" []))
    (let ((view (dsh-protocol-context-pressure--from-alist wire)))
      (should (dsh-protocol-context-pressure-p view))
      (should-not (dsh-protocol-context-pressure-pressure view))
      (should-not (dsh-protocol-context-pressure-projected view))
      (should-not (dsh-protocol-context-pressure-window view)))))

(ert-deftest dsh-emacs-test-protocol-permission-value-keeps-host-defined-names ()
  :tags '(dsh-unit)
  (dolist (key '(currentValue "currentValue"))
    (dolist (value '("workspace-write" "auto" "custom" " host-defined " " "))
      (should (equal value
                     (dsh-protocol-permission-value--from-alist
                      (list (cons key value))))))
    (dolist (value '(nil "" :json-false 7 []))
      (should-not (dsh-protocol-permission-value--from-alist
                   (list (cons key value))))))
  (dolist (wire '(nil :json-false 7 "bare-preset" [] ((other . "custom"))))
    (should-not (dsh-protocol-permission-value--from-alist wire))))

(ert-deftest dsh-emacs-test-protocol-control-baseline-keeps-raw-session-records ()
  :tags '(dsh-unit)
  (let* ((first '(first . ((asOfSeq . 7) (values))))
         (migration '("migration" . ((kind . "migration-required"))))
         (entries (list first '(empty) migration)))
    (dolist (key '(projections "projections"))
      (dolist (records (list entries (vconcat entries)))
        ;; A later migration hint must not prevent the caller from applying
        ;; an earlier session; only the per-session decoder may signal it.
        (let ((decoded (dsh-protocol-control-baseline--from-alist
                        (list (cons key records)))))
          (should (= 2 (length decoded)))
          (should (eq first (car decoded)))
          (should (eq migration (cadr decoded)))))))
  (should-not (dsh-protocol-control-baseline--from-alist nil)))

(ert-deftest dsh-emacs-test-protocol-control-session-keeps-cuts-and-cell-presence ()
  :tags '(dsh-unit)
  (dolist (session-id '(control-a "control-a"))
    (let* ((baseline
            '((asOfSeq . 17)
              (values . ((goal . nil)
                         (futureCell . ((nested . [1 2])))
                         (contextPressure . ((pressureTokens . 20)
                                             (projectedTokens . 22)
                                             (contextWindow . 100)))
                         (permissions . ((currentValue . " host ")))
                         (inbox . nil) (subagentCatalog . [])))))
           (session (dsh-protocol-control-session--from-alist
                     (cons session-id baseline)))
           (projections (dsh-protocol-control-session-projections session))
           (subagents (dsh-protocol-control-session-subagents session)))
      (should (equal "control-a" (dsh-protocol-control-session-session-id session)))
      (should (equal (mapcar #'dsh-protocol-projection-key projections)
                     '("plan" "userQuestions" "goal" "futureCell"
                       "contextPressure" "permissions" "inbox")))
      (should (equal (mapcar #'dsh-protocol-projection-session-id projections)
                     (make-list 7 "control-a")))
      (pcase-let ((`(,plan ,questions ,goal ,unknown ,context ,permission ,inbox)
                   (mapcar #'dsh-protocol-projection-value projections)))
        (should (= 17 (dsh-protocol-plan-seq plan)))
        (should-not (dsh-protocol-plan-available plan))
        (should (= 17 (dsh-protocol-user-questions-seq questions)))
        (should-not (dsh-protocol-user-questions-active questions))
        (should-not goal)
        (should (eq unknown (dsh-protocol--field
                             'futureCell (dsh-protocol--field 'values baseline))))
        (should (= 22 (dsh-protocol-context-pressure-projected context)))
        (should (equal " host " permission))
        (should-not inbox))
      (should (equal '(17 17 17 17)
                     (mapcar #'dsh-protocol-subagent-cell-seq subagents)))
      (should (equal '(t nil nil nil)
                     (mapcar #'dsh-protocol-subagent-cell-present subagents)))))
  (let ((projections
         (dsh-protocol-control-session-projections
          (dsh-protocol-control-session--from-alist '(empty . ((asOfSeq . 4)))))))
    (should (equal (mapcar #'dsh-protocol-projection-key projections)
                   '("plan" "userQuestions")))))

(ert-deftest dsh-emacs-test-protocol-projection-decodes-known-values ()
  :tags '(dsh-unit)
  (dolist (case
           (list
            (list 'contextPressure '((pressureTokens . 30) (projectedTokens . 33)
                                     (contextWindow . 100))
                  #'dsh-protocol-context-pressure-projected 33)
            (list "permissions" '((currentValue . " custom ")) #'identity " custom ")
            (list 'goal '((goal . ((objective . "Keep going") (phase . "active"))))
                  #'dsh-protocol-goal-objective "Keep going")
            (list "inbox"
                  (list (cons 'next-turn
                              (vector (dsh-emacs-test--inbox-message "i1" "queued body"))))
                  (lambda (items) (mapcar #'dsh-protocol-queue-item-text items))
                  '("queued body"))
            (list 'plan '((active . t) (pending . :json-false))
                  #'dsh-protocol-plan-seq 23)
            (list "userQuestions" '((active . []) (settled . []))
                  #'dsh-protocol-user-questions-seq 23)
            (list 'tokenUsage '((outputTokens . 5))
                  (lambda (cell)
                    (list (dsh-protocol-subagent-cell-key cell)
                          (dsh-protocol-subagent-cell-seq cell)
                          (dsh-protocol-token-usage-output
                           (dsh-protocol-subagent-cell-value cell))))
                  '(tokenUsage 23 5))))
    (pcase-let* ((`(,key ,wire ,read-value ,expected) case)
                 (projection
                  (dsh-protocol-projection--from-alist
                   `((sessionId . "control-a") (key . ,key)
                     (seq . 23) (value . ,wire)))))
      (ert-info ((format "projection key=%s" key))
        (should (equal "control-a" (dsh-protocol-projection-session-id projection)))
        (should (equal (format "%s" key) (dsh-protocol-projection-key projection)))
        (should (equal expected
                       (funcall read-value (dsh-protocol-projection-value projection)))))))
  (let* ((raw '((nested . [1 2])))
         (projection (dsh-protocol-projection--from-alist
                      `((sessionId . "control-a") (key . futureCell) (value . ,raw)))))
    (should (equal "futureCell" (dsh-protocol-projection-key projection)))
    (should (eq raw (dsh-protocol-projection-value projection)))))

(ert-deftest dsh-emacs-test-protocol-core-item-decodes-workspace-payloads ()
  :tags '(dsh-unit)
  (dolist (array (list #'identity #'vconcat))
    (let* ((row '((workspaceId . "w") (title . "Workspace")
                  (sessionIds . ["s"])))
           (baseline
            (dsh-protocol-core-item--from-alist
             `(("type" . "baseline")
               ("value" . (("items" . ,(funcall array (list row)))
                           ("archivedSessionIds"
                            . ,(funcall array '("archived"))))))))
           (upsert (dsh-protocol-core-item--from-alist
                    `((type . "upsert") (workspace . ,row))))
           (remove (dsh-protocol-core-item--from-alist
                    '(("type" . "remove") ("workspaceId" . "gone"))))
           (order (dsh-protocol-core-item--from-alist
                   `((type . "order")
                     (workspaceIds . ,(funcall array '("b" "a" "b"))))))
           (archived (dsh-protocol-core-item--from-alist
                      `((type . "archived")
                        (archivedSessionIds . ,(funcall array nil)))))
           (view (dsh-protocol-core-item-payload baseline)))
      (should (equal '("baseline" "upsert" "remove" "order" "archived")
                     (mapcar #'dsh-protocol-core-item-type
                             (list baseline upsert remove order archived))))
      (should (equal '("archived")
                     (dsh-protocol-workspace-list-archived-session-ids view)))
      (should (= 1 (length (dsh-protocol-workspace-list-items view))))
      (let ((workspace (car (dsh-protocol-workspace-list-items view))))
        (should (equal "w" (dsh-protocol-workspace-workspace-id workspace)))
        (should (equal "Workspace" (dsh-protocol-workspace-title workspace)))
        (should (equal '("s") (dsh-protocol-workspace-session-ids workspace)))
        (should (equal workspace (dsh-protocol-core-item-payload upsert))))
      (should (equal "gone" (dsh-protocol-core-item-payload remove)))
      (should (equal '("b" "a" "b") (dsh-protocol-core-item-payload order)))
      (should-not (dsh-protocol-core-item-payload archived))))
  (should-not (dsh-protocol-core-item-payload
               (dsh-protocol-core-item--from-alist '((type . "upsert"))))))

(ert-deftest dsh-emacs-test-protocol-core-item-retains-control-boundaries ()
  :tags '(dsh-unit)
  (dolist (value '(nil
                   ((items . nil) (projections))
                   ((projections
                     (first . ((values (title . "Applied first"))))
                     (later . ((kind . "migration-required")))))))
    (let ((item (dsh-protocol-core-item--from-alist
                 `((type . "baseline") (value . ,value)))))
      ;; The consumer must still decode/apply one session before the next.
      (should (equal "baseline" (dsh-protocol-core-item-type item)))
      (should (eq value (dsh-protocol-core-item-payload item)))))
  (let* ((item (dsh-protocol-core-item--from-alist
                '((type . "projection") (sessionId . "session")
                  (key . "plan") (seq . 19)
                  (value . ((active . t) (pending . :json-false))))))
         (projection (dsh-protocol-core-item-payload item))
         (plan (dsh-protocol-projection-value projection)))
    (should (equal "projection" (dsh-protocol-core-item-type item)))
    (should (equal "session" (dsh-protocol-projection-session-id projection)))
    (should (equal "plan" (dsh-protocol-projection-key projection)))
    (should (dsh-protocol-plan-active plan))
    (should-not (dsh-protocol-plan-pending plan))
    (should (= 19 (dsh-protocol-plan-seq plan))))
  (let* ((wire '((type . "future-item") (value . ((nested . [1 2])))))
         (item (dsh-protocol-core-item--from-alist wire)))
    (should (equal "future-item" (dsh-protocol-core-item-type item)))
    (should (eq wire (dsh-protocol-core-item-payload item)))))

(ert-deftest dsh-emacs-test-protocol-core-session-notices-name-their-arguments ()
  :tags '(dsh-unit)
  (dolist (array (list #'identity #'vconcat))
    (dolist (case '(("api-session/added" (((sessionId . "new"))) nil)
                    ("api-session/removed" ("gone") "gone")
                    ("api-session/status" ("busy" t) "busy" t)
                    ("api-session/status" ("idle" :json-false) "idle")
                    ("api-session/status" ("absent") "absent")
                    ("api-session/activity" ("recent" 123) "recent")
                    ("future-event" ("ignored" 456) nil)))
      (pcase-let* ((`(,name ,args ,id . ,rest) case)
                   (item (dsh-protocol-core-item--from-alist
                          `(("type" . "emit") ("event" . ,name)
                            ("args" . ,(funcall array args)))))
                   (notice (dsh-protocol-core-item-payload item)))
        (should (equal "emit" (dsh-protocol-core-item-type item)))
        (should (equal name (dsh-protocol-session-notice-name notice)))
        (should (equal id (dsh-protocol-session-notice-session-id notice)))
        (if (equal name "api-session/added")
            (should (eq (car args) (dsh-protocol-session-notice-value notice)))
          (should (equal (car rest)
                         (dsh-protocol-session-notice-value notice)))))))
  (dolist (case '(("ready" clientId "client") ("cancel" eventId "event")
                  ("ready" clientId nil) ("cancel" eventId nil)))
    (pcase-let* ((`(,type ,key ,id) case)
                 (item (dsh-protocol-core-item--from-alist
                        `((type . ,type) (,key . ,id)))))
      (should (equal type (dsh-protocol-core-item-type item)))
      (should (equal id (dsh-protocol-core-item-payload item))))))

(ert-deftest dsh-emacs-test-protocol-waterfall-keeps-request-decoding-late ()
  :tags '(dsh-unit)
  (dolist (name '("user-questions/request" "approval/request" "future-request"))
    (let* ((raw '((wait . ((callId . "call") . bad))))
           (item (dsh-protocol-core-item--from-alist
                  `(("type" . "waterfall") ("event" . ,name)
                    ("eventId" . "event") ("agentId" . "agent")
                    ("request" . ,raw))))
           (waterfall (dsh-protocol-core-item-payload item)))
      (should (equal "waterfall" (dsh-protocol-core-item-type item)))
      (should (equal name (dsh-protocol-waterfall-name waterfall)))
      (should (equal "event" (dsh-protocol-waterfall-event-id waterfall)))
      (should (equal "agent" (dsh-protocol-waterfall-agent-id waterfall)))
      (should (eq raw (dsh-protocol-waterfall-request waterfall)))))
  (dolist (array (list #'identity #'vconcat))
    (let* ((questions '(((id . "q") (question . "First?")) malformed-later-item))
           (request (dsh-protocol-question-request--from-alist
                     `(("questions" . ,(funcall array questions))
                       ("wait" . (("callId" . "call") ("timed" . t))))))
           (wait (dsh-protocol-question-request-wait request)))
      ;; Preserve question objects and their order for the existing readers.
      (should (equal questions (dsh-protocol-question-request-questions request)))
      (should (eq (car questions)
                  (car (dsh-protocol-question-request-questions request))))
      (should (equal "call" (dsh-protocol-question-wait-call-id wait)))
      (should (dsh-protocol-question-wait-timed wait))))
  (dolist (wait '(nil [] :json-false "invalid"))
    (let ((request (dsh-protocol-question-request--from-alist
                    `((questions . []) (wait . ,wait)))))
      (should-not (dsh-protocol-question-request-questions request))
      (should-not (dsh-protocol-question-request-wait request)))))

;; --- Test 57: protocol layer workspace baseline / workspace-result
;; / model-selection-result ---
;; workspace/follow baseline top-level values: items array->list,
;; archivedSessionIds array->list
(ert-deftest dsh-emacs-test-protocol-protocol-workspace-list-conversion ()
  :tags '(dsh-unit)
  (let* ((value '((items . [((workspaceId . "w1") (title . "WS A")
                             (path . "/tmp/a") (sessionIds . ["s1" "s2"])
                             (createdAt . "2026-08-25T00:00:00Z")
                             (updatedAt . "2026-08-25T01:00:00Z"))
                            ((workspaceId . "w2") (title . "WS B")
                             (path . "/tmp/b") (sessionIds . []))])
                  (archivedSessionIds . ["s9"])))
         (wl (dsh-protocol-workspace-list--from-alist value))
         (items (dsh-protocol-workspace-list-items wl))
         (w1 (car items)))
    (ert-info ((format "%s" "protocol-workspace-list-conversion"))
      (should (and (= (length items) 2)
                   (equal (dsh-protocol-workspace-list-archived-session-ids wl)
                          '("s9"))
                   ;; items converted inline + arrays normalized to lists
                   (dsh-protocol-workspace-p w1)
                   (equal (dsh-protocol-workspace-session-ids w1) '("s1" "s2"))
                   ;; WorkspaceView official fields complete
                   (string= (dsh-protocol-workspace-title w1) "WS A")
                   (string= (dsh-protocol-workspace-created-at w1)
                            "2026-08-25T00:00:00Z")
                   (string= (dsh-protocol-workspace-updated-at w1)
                            "2026-08-25T01:00:00Z")
                   (string= (dsh-protocol-workspace-path w1) "/tmp/a")
                   (string= (dsh-protocol-workspace-workspace-id
                             (car (dsh-protocol-workspace-list-items
                                   (dsh-protocol-workspace-list--from-alist
                                    '((items . [((workspaceId . "w2"))]))))))
                            "w2"))))))

;; workspace/create response: {workspace, created}
(ert-deftest dsh-emacs-test-protocol-protocol-workspace-create-result ()
  :tags '(dsh-unit)
  (let* ((value '((workspace . ((workspaceId . "w3") (title . "New")
                                (path . "/tmp/new") (sessionIds . [])
                                (createdAt . "x") (updatedAt . "y")))
                  (created . t)))
         (r (dsh-protocol-workspace-result--from-alist value)))
    (ert-info ((format "%s" "protocol-workspace-create-result"))
      (should (and (dsh-protocol-workspace-p (dsh-protocol-workspace-result-workspace r))
                   (eq (dsh-protocol-workspace-result-created r) t)
                   (string= (dsh-protocol-workspace-title
                             (dsh-protocol-workspace-result-workspace r))
                            "New"))))))

;; workspace/rename / insertSessionBefore response: only {workspace},
;; created is nil
(ert-deftest dsh-emacs-test-protocol-protocol-workspace-rename-result ()
  :tags '(dsh-unit)
  (let* ((r (dsh-protocol-workspace-result--from-alist
             '((workspace . ((workspaceId . "w1") (title . "Renamed"))))))
         (d (dsh-protocol-workspace-result-created r)))
    (ert-info ((format "%s" "protocol-workspace-rename-result"))
      (should (and (string= (dsh-protocol-workspace-title
                             (dsh-protocol-workspace-result-workspace r))
                            "Renamed")
                   (null d))))))

;; session/selectModel response: {selected}
(ert-deftest dsh-emacs-test-protocol-protocol-model-selection-result ()
  :tags '(dsh-unit)
  (let* ((r (dsh-protocol-model-selection-result--from-alist
             '((selected . ((provider . "deepseek")
                            (model . "deepseek-chat")
                            (reasoningEffort . "high"))))))
         (sel (dsh-protocol-model-selection-result-selected r)))
    (ert-info ((format "%s" "protocol-model-selection-result"))
      (should (and (dsh-protocol-model-selection-p sel)
                   (string= (dsh-protocol-model-selection-provider sel) "deepseek")
                   (string= (dsh-protocol-model-selection-model sel) "deepseek-chat")
                   (string= (dsh-protocol-model-selection-reasoning-effort sel)
                            "high"))))))

(ert-deftest dsh-emacs-test-protocol-message-envelope-and-attachments ()
  :tags '(dsh-unit)
  (let* ((event '((data . ((content . [((type . "text") (text . "user"))])
                           (message . ((content . [((type . "text") (text . "assistant"))])))
                           (source . ((kind . "session-reference")
                                      (references . [((sessionId . "s1") (label . "one"))])))))))
         (user (dsh-protocol-message--from-alist event))
         (assistant (dsh-protocol-message--from-alist event :assistant t))
         (image (dsh-protocol-content-block--from-alist
                 '((type . "image") (name . "inline")
                   (attachment . ((name . "nested") (attachmentId . "img")
                                  (mediaType . "image/png")))))))
    (should (equal (dsh-protocol-content-block-text
                    (car (dsh-protocol-message-content user))) "user"))
    (should (equal (dsh-protocol-content-block-text
                    (car (dsh-protocol-message-content assistant))) "assistant"))
    (should (equal (dsh-protocol-message-references user) '(("one" . "s1"))))
    (should (equal (dsh-protocol-content-block-name image) "inline"))
    (should (equal (dsh-protocol-content-block-attachment-id image) "img"))
    (should (equal (dsh-protocol-content-block-media-type image) "image/png"))))

(ert-deftest dsh-emacs-test-protocol-request-and-usage-envelopes ()
  :tags '(dsh-unit)
  (let ((config (dsh-protocol-request-model--from-alist
                 '(("data" . (("header" . (("config" . (("model" . "m")
                                                        ("provider" . "p")
                                                        ("reasoningEffort" . "high")))))))) t)))
    (should (equal (dsh-protocol-model-selection-model config) "m"))
    (should (equal (dsh-protocol-model-selection-provider config) "p"))
    (should (equal (dsh-protocol-model-selection-reasoning-effort config) "high")))
  (should-not (dsh-protocol-request-model--from-alist '((data . ((other . t)))) t))
  (should (equal (dsh-protocol-message-usage--from-alist
                  '((data . ((usage . ((inputTokens . "11") (input . 99)
                                       (output . 7) (cacheReadTokens . 3)
                                       (cacheWrite . "2") (cost . "0.25")))))) t)
                 '(11 7 3 2 0.25)))
  (should (equal (dsh-protocol-message-usage--from-alist nil t) '(0 0 0 0 0.0))))

(ert-deftest dsh-emacs-test-protocol-tool-arguments-precedence-and-fallback ()
  :tags '(dsh-unit)
  (let ((args (dsh-protocol-tool-arguments--from-alist
               "{\"description\":\"wrong\",\"job_id\":\"job-7\",\"command\":\"pwd\"}"
               "job_output" "bash")))
    (should (equal (dsh-protocol-tool-arguments-summary args) "job-7"))
    (should (equal (dsh-protocol-tool-arguments-command args) "pwd")))
  (let ((args (dsh-protocol-tool-arguments--from-alist
               "{\"files\":[{\"path\":\"a\"},{\"path\":\"\"},{\"path\":\"b\"}]}" "present")))
    (should (equal (dsh-protocol-tool-arguments-paths args) '("a" "b"))))
  (should-not (dsh-protocol-tool-arguments-object
               (dsh-protocol-tool-arguments--from-alist "{broken"))))

(ert-deftest dsh-emacs-test-protocol-rpc-and-upload-envelopes ()
  :tags '(dsh-unit)
  (should (equal (dsh-protocol-rpc-result--from-alist
                  '((result . ((ok . t) (value . 42))))) '(t . 42)))
  (should (equal (dsh-protocol-rpc-result--from-alist
                  '((result . ((ok . :json-false) (error . "inner")))
                    (message . "outer"))) '(nil . "inner")))
  (should (equal (dsh-protocol-rpc-result--from-alist
                  '((message . "provider message") (error . "provider error")))
                 '(nil . "provider message")))
  (should (equal (dsh-protocol-rpc-result--from-alist
                  '((ok . t) (value . "receipt")) t) '(t . "receipt")))
  (should (equal (dsh-protocol-rpc-result--from-alist
                  '((ok . :json-false) (error . "upload error")) t)
                 '(nil . "upload error")))
  (should (equal (dsh-protocol-rpc-result--from-alist
                  '((message . "not an upload error")) t) '(nil))))

(ert-deftest dsh-emacs-test-protocol-plan-json-boundary ()
  :tags '(dsh-unit)
  (let ((json-object-type 'hash-table)
        (json-key-type 'string))
    (should (equal (dsh-protocol-plan-document-text
                    (dsh-protocol-plan-document--from-alist
                     "{\"plan\":\"# Next\\nDo work\"}" t))
                   "# Next\nDo work")))
  (should-not (dsh-protocol-plan-document-text
               (dsh-protocol-plan-document--from-alist "42" t)))
  (should-error (dsh-protocol-plan-document--from-alist "{broken" t)
                :type 'json-error))

(provide 'dsh-test-protocol)
;;; dsh-test-protocol.el ends here

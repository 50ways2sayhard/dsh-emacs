;;; dsh-test-questions.el --- Questions tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

(defvar vertico-preselect)

;; --- Test 31f: an ask row renders dsh web's question card — the questions
;; and their numbered options with descriptions replace the argument JSON, and
;; the settled answers check the chosen options and carry free-text answers ---
(defconst dsh-emacs-test--ask-args
  (json-encode
   '((questions . [((id . "q1") (header . "Layout")
                    (question . "Which layout?")
                    (options . [((label . "Stacked")
                                 (description . "Classic rhythm."))
                                ((label . "Compact"))])
                    (multi_select . :json-false))
                   ((id . "q2") (question . "Which details?")
                    (options . [((label . "Chip"))])
                    (multi_select . t))])))
  "Wire arguments of a two-question `ask_user_question' call.")

(ert-deftest dsh-emacs-test-questions-ask-tool-uses-question-variant ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "ask-tool-uses-question-variant"))
    (should (equal "question" (car (dsh-emacs-render--tool-variant "ask_user_question"))))
    (should (equal "❓" (cdr (assoc "question" dsh-emacs--variant-icons))))
    (should (stringp (cdr (assoc "question" dsh-emacs--tool-icon-svgs))))))

(ert-deftest dsh-emacs-test-questions-ask-pending-card-shows-questionnaire ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "k1" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k1")))
      (ert-info ((format "%s" "ask-pending-card-shows-questionnaire"))
        (should (string-match-p "Ask question · waiting" block))
        (should (string-match-p "^  Q1 · Layout — Which layout\\?$" block))
        (should (string-match-p "^  Q2 · Which details\\?$" block))
        (should (string-match-p "^   1\\.   Stacked$" block))
        (should (string-match-p "^        Classic rhythm\\.$" block))
        (should (string-match-p "^   1\\.   Chip$" block))
        (should (not (string-match-p "^  IN" block)))
        (should (not (string-match-p "^  OUT" block)))))))

(ert-deftest dsh-emacs-test-questions-ask-answered-card-marks-choices-and-free-text ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "k2" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "k2" nil 0
      (json-encode '((answers . [((id . "q1") (selected . ["Stacked"]))
                                 ((id . "q2") (selected . [])
                                  (custom . "and a summary"))])))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k2")))
      (ert-info ((format "%s" "ask-answered-card-marks-choices-and-free-text"))
        (should (string-match-p "Ask question · 2/2 answered" block))
        (should (string-match-p "^   1\\. ✓ Stacked$" block))
        (should (string-match-p "^   2\\.   Compact$" block))
        (should (string-match-p "^  → and a summary$" block))))))

(ert-deftest dsh-emacs-test-questions-ask-settled-empty-question-reads-not-answered ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "k3" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "k3" nil 0
      (json-encode '((answers . [((id . "q1") (selected . []))])))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k3")))
      (ert-info ((format "%s" "ask-settled-empty-question-reads-not-answered"))
        (should (string-match-p "Ask question · 0/1 answered" block))
        (should (string-match-p "^  Not answered$" block))))))

;; An abandoned ask is the user's own decision: the row interrupts instead of
;; failing red, like dsh web's ASK_ABORTED state.
(ert-deftest dsh-emacs-test-questions-ask-aborted-row-interrupts-instead-of-failing ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "k4" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "k4" t nil "Error: ask_user_question was aborted before the user answered"
      '((name . "UserQuestionError") (code . "ASK_ABORTED")
        (reason . "User abandoned the questions"))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k4")))
      (ert-info ((format "%s" "ask-aborted-row-interrupts-instead-of-failing"))
        (should (string-match-p "◐ Ask question · interrupted" block))
        (should (string-match-p
                 (regexp-quote
                  "This question set was interrupted before answers were submitted.")
                 block))
        (should (not (string-match-p (regexp-quote "✗ failed") block)))))))

;; A dismissed ask (ASK_CANCELLED) is the user's own decision too: the row
;; settles green with the outcome, and the questionnaire stays as the record.
(ert-deftest dsh-emacs-test-questions-ask-cancelled-row-settles-instead-of-failing ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "k8" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "k8" t nil "the user cancelled ask_user_question"
      '((name . "UserQuestionError") (code . "ASK_CANCELLED")
        (reason . "the user cancelled ask_user_question"))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k8")))
      (ert-info ((format "%s" "ask-cancelled-row-settles-instead-of-failing"))
        (should (string-match-p "Ask question · cancelled" block))
        (should (string-match-p "^  Q1 · Layout — Which layout\\?$" block))
        (should (string-match-p
                 (regexp-quote
                  "This question set was cancelled before answers were submitted.")
                 block))
        (should (not (string-match-p (regexp-quote "✗ failed") block)))))))

;; A malformed option element (a string or a number where the wire promised
;; an object) is dropped at the protocol boundary: the question still renders
;; and nothing signals out of the event stream.
(ert-deftest dsh-emacs-test-questions-ask-malformed-option-elements-are-dropped ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "k7" "ask_user_question"
      "{\"questions\":[{\"id\":\"q1\",\"header\":\"Layout\",\"question\":\"Which?\",\"options\":[\"Yes\",42,{\"label\":\"Stacked\"}]}]}"))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k7")))
      (ert-info ((format "%s" "ask-malformed-option-elements-are-dropped"))
        (should (string-match-p "Ask question · waiting" block))
        (should (string-match-p "^  Layout — Which\\?$" block))
        (should (string-match-p "^   1\\.   Stacked$" block))
        (should (not (string-match-p "Yes" block)))))))

;; A call the ask card cannot describe (no usable questions) keeps the ioCard.
(ert-deftest dsh-emacs-test-questions-ask-unusable-arguments-keep-the-iocard ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "k5" "ask_user_question" "{}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "k5" nil 0 "no questions given"))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k5")))
      (ert-info ((format "%s" "ask-unusable-arguments-keep-the-iocard"))
        (should (string-match-p "^  OUT no questions given$" block))))))

;; A malformed question element (a string or a number where the wire promised
;; an object) must decline instead of signalling out of the event stream.
(ert-deftest dsh-emacs-test-questions-ask-malformed-question-elements-keep-the-iocard ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "k6" "ask_user_question"
                                      "{\"questions\":[\"oops\",42,null]}"))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-k6")))
      (ert-info ((format "%s" "ask-malformed-question-elements-keep-the-iocard"))
        (should (string-match-p "Ask question" block))
        (should (string-match-p "oops" block))
        (should (not (string-match-p "Q1" block)))))))

;; the question protocol preserves the description text
;; and the raw option labels,
;; and treats only JSON true as multiple select.
(ert-deftest dsh-emacs-test-questions-question-protocol-keeps-details-and-option-order ()
  :tags '(dsh-unit)
  (let* ((wire '((id . "q-details") (question . "Which routes?")
                 (header . "Routes") (detail . "Choose every required route.")
                 (options . [((label . "A,B") (description . "Comma label."))
                             ((label . "C"))])
                 (multiSelect . t)))
         (question (dsh-protocol-question--from-alist wire)))
    (ert-info ((format "%s" "question-protocol-keeps-details-and-option-order"))
      (should (equal "q-details" (dsh-protocol-question-id question)))
      (should (equal "Which routes?" (dsh-protocol-question-text question)))
      (should (equal "Routes" (dsh-protocol-question-header question)))
      (should (equal "Choose every required route."
                     (dsh-protocol-question-detail question)))
      (should (listp (dsh-protocol-question-options question)))
      (should (equal '("A,B" "C")
                     (mapcar #'dsh-protocol-question-option-label
                             (dsh-protocol-question-options question))))
      (should (equal "Comma label."
                     (dsh-protocol-question-option-description
                      (car (dsh-protocol-question-options question)))))
      (should (null (dsh-protocol-question-option-description
                     (cadr (dsh-protocol-question-options question)))))
      (should (dsh-protocol-question-multi-select question))
      (should (eq question (dsh-protocol--struct #'dsh-protocol-question-p
                                                 #'dsh-protocol-question--from-alist
                                                 question))))
    (dolist (false-value '(nil :json-false))
      (ert-info ((format "%s" (format "question-protocol-single-for-%s" false-value)))
        (should (not (dsh-protocol-question-multi-select
                      (dsh-protocol-question--from-alist
                       `((multiSelect . ,false-value))))))))))

;; The ask tool's own arguments spell the flag `multi_select' where the ask
;; request spells it `multiSelect'; both decode to the same struct.
(ert-deftest dsh-emacs-test-questions-question-protocol-decodes-tool-argument-spelling ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "question-protocol-decodes-tool-argument-spelling"))
    (should (dsh-protocol-question-multi-select
             (dsh-protocol-question--from-alist '((id . "q") (multi_select . t)))))
    (should (not (dsh-protocol-question-multi-select
                  (dsh-protocol-question--from-alist
                   '((id . "q") (multi_select . :json-false))))))))

;; A malformed option element declines at the wire boundary instead of
;; signalling out of the constructor's `assq'.
(ert-deftest dsh-emacs-test-questions-question-protocol-drops-malformed-option-elements ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "question-protocol-drops-malformed-option-elements"))
    (should (equal '("Stacked")
                   (mapcar #'dsh-protocol-question-option-label
                           (dsh-protocol-question-options
                            (dsh-protocol-question--from-alist
                             '((id . "q") (question . "Which?")
                               (options . ["oops" ((label . "Stacked")) 42])))))))))

;; session identifier: prefer the active chat buffer's name; with no buffer
;; fall back to dsh: <id>, truncated; empty when there is no session-id (a
;; direct call in a test adds no prefix)
;; Minibuffer reader helpers (session-label / numbered candidates /
;; completing-read / skip-key / question-preview) were removed with
;; postmortem/142; Composer form coverage lives in
;; test/dsh-test-interaction.el.


;; ---------------------------------------------------------------------------
;; Waterfall routing smoke tests (Composer forms). Deep form/answer coverage
;; lives in test/dsh-test-interaction.el (postmortem/142).
;; ---------------------------------------------------------------------------

(defun dsh-emacs-test--questions-chat (name session)
  "Return a chat buffer named NAME registered as SESSION."
  (let ((chat (get-buffer-create name)))
    (with-current-buffer chat
      (dsh-emacs-mode)
      (setq-local dsh-emacs--buffer-session session)
      (dsh-emacs--setup-input-area))
    chat))

(ert-deftest dsh-emacs-test-questions-question-frame-answers-with-result-outcome ()
  :tags '(dsh-unit)
  (let* ((chat (dsh-emacs-test--questions-chat " *dsh-test-question*" "sess-q"))
         (responds nil))
    (unwind-protect
        (let ((dsh-emacs--chat-buffers (make-hash-table :test 'equal))
              (dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (puthash "sess-q" chat dsh-emacs--chat-buffers)
          (cl-letf (((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (client-id event-id outcome cb)
                       (push (list client-id event-id outcome) responds)
                       (funcall cb t nil))))
            (dsh-emacs-events--host-item
             'process
             '((type . "waterfall")
               (event . "user-questions/request")
               (eventId . "rpc-q")
               (agentId . "sess-q")
               (request . ((questions .
                                      (((id . "q1") (question . "Proceed?")
                                        (options . (((label . "Yes"))
                                                    ((label . "No")))))))))))
            (with-current-buffer chat
              (should (string-match-p "Proceed\?" (cdr (dsh-emacs-interaction--chrome))))
              (dsh-emacs--clear-input)
              (goto-char dsh-emacs--input-marker)
              (insert "1")
              (should (dsh-emacs-interaction--submit-pending)))
            (let ((r (car responds)))
              (ert-info ((format "%s" "question-frame-answers-with-result-outcome"))
                (should (and (equal "c1" (nth 0 r))
                             (equal "rpc-q" (nth 1 r))
                             (equal '((kind . "result")
                                      (value . ((answers .
                                                         (((id . "q1")
                                                           (selected "Yes")))))))
                                    (nth 2 r))))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-questions-question-frame-decline-waterfall ()
  :tags '(dsh-unit)
  (let* ((chat (dsh-emacs-test--questions-chat " *dsh-test-question-cg*" "sess-qc"))
         (responds nil))
    (unwind-protect
        (let ((dsh-emacs--chat-buffers (make-hash-table :test 'equal))
              (dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (puthash "sess-qc" chat dsh-emacs--chat-buffers)
          (cl-letf (((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (client-id event-id outcome cb)
                       (push (list client-id event-id outcome) responds)
                       (funcall cb t nil))))
            (dsh-emacs-events--host-item
             'process
             '((type . "waterfall")
               (event . "user-questions/request")
               (eventId . "rpc-qc")
               (agentId . "sess-qc")
               (request . ((questions .
                                      (((id . "q1") (question . "Proceed?")
                                        (options . (((label . "Yes")))))))))))
            (with-current-buffer chat (dsh-emacs-interaction-decline))
            (ert-info ((format "%s" "question-frame-decline-waterfall"))
              (should (equal (list (list "c1" "rpc-qc"
                                         '((kind . "rejected")
                                           (error . ((name . "cancelled")
                                                     (message . "User abandoned the questions"))))))
                             responds)))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-questions-foreign-no-chat-waterfalls-handed-on ()
  :tags '(dsh-unit)
  (let* ((chat (dsh-emacs-test--questions-chat " *dsh-test-question-other*" "mine"))
         (responds nil)
         (prompted nil))
    (unwind-protect
        (let ((dsh-emacs--chat-buffers (make-hash-table :test 'equal))
              (dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (puthash "mine" chat dsh-emacs--chat-buffers)
          (cl-letf (((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (client-id event-id outcome cb)
                       (push (list client-id event-id outcome) responds)
                       (funcall cb t nil)))
                    ((symbol-function 'dsh-emacs-interaction--question-requested)
                     (lambda (&rest _) (setq prompted t)))
                    ((symbol-function 'dsh-emacs-interaction--approval-requested)
                     (lambda (&rest _) (setq prompted t))))
            (dsh-emacs-events--host-item
             'process
             '((type . "waterfall")
               (event . "user-questions/request")
               (eventId . "rpc-o")
               (agentId . "other-session")
               (request . ((questions .
                                      (((id . "q1") (question . "Proceed?")
                                        (options . (((label . "Yes")))))))))))
            (dsh-emacs-events--host-item
             'process
             '((type . "waterfall")
               (event . "approval/request")
               (eventId . "rpc-ao")
               (agentId . "other-session")
               (request . ((toolName . "fs") (reason . "outside")))))
            (ert-info ((format "%s" "foreign-no-chat-waterfalls-handed-on"))
              (should (null prompted))
              (should (= 2 (length responds)))
              (should (cl-every (lambda (r)
                                  (and (equal "c1" (nth 0 r))
                                       (equal '((kind . "next")) (nth 2 r))))
                                responds)))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-questions-approval-frame-answered ()
  :tags '(dsh-unit)
  (let* ((chat (dsh-emacs-test--questions-chat " *dsh-test-approval*" "sess-ap"))
         (responds nil))
    (unwind-protect
        (let ((dsh-emacs--chat-buffers (make-hash-table :test 'equal))
              (dsh-emacs-events--client-id "c1")
              (dsh-emacs-enable-notifications nil))
          (puthash "sess-ap" chat dsh-emacs--chat-buffers)
          (cl-letf (((symbol-function 'dsh-emacs--events-result-async)
                     (lambda (client-id event-id outcome cb)
                       (push (list client-id event-id outcome) responds)
                       (funcall cb t nil))))
            (dsh-emacs-events--host-item
             'process
             '((type . "waterfall")
               (event . "approval/request")
               (eventId . "rpc-ap")
               (agentId . "sess-ap")
               (request . ((toolName . "Bash") (reason . "rm -rf /tmp/x")
                           (callId . "call-ap")))))
            (with-current-buffer chat (dsh-emacs-interaction-allow))
            (let ((r (car responds)))
              (ert-info ((format "%s" "approval-frame-answered"))
                (should (equal "c1" (nth 0 r)))
                (should (equal "rpc-ap" (nth 1 r)))
                (should (equal '((kind . "result") (value . "allowed-once"))
                               (nth 2 r)))))))
      (when (buffer-live-p chat) (kill-buffer chat)))))

(ert-deftest dsh-emacs-test-questions-userquestions-projection-stores-chat-state ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs--buffer-session "sess-uq")
    (let ((questions (dsh-protocol-user-questions--from-alist
                      '((active . [((callId . "c1")
                                    (questions . [((id . "q1")
                                                   (question . "Still?")
                                                   (options . [((label . "Yes"))]))])
                                    (state . "continued"))])
                        (settled . [])
                        (seq . 4)))))
      (dsh-emacs-interaction--questions-projected questions)
      (ert-info ((format "%s" "userquestions-projection-stores-chat-state"))
        (should (eq questions dsh-emacs-interaction--session-questions))
        (should (= 1 (length (dsh-emacs-interaction--continued-calls))))
        (should (dsh-emacs-interaction--find "call:c1"))))))





(ert-deftest dsh-emacs-test-questions-protocol-user-questions-decodes ()
  :tags '(dsh-unit)
  (let* ((view (dsh-protocol-user-questions--from-alist
                '((active . [((callId . "c1")
                              (state . "continued")
                              (questions . [((id . "q1")
                                             (question . "Which?"))
                                            "oops"
                                            ((id . "q2")
                                             (question . "And?")
                                             (options . [((label . "A"))]))]))])
                  (settled . [((callId . "c0")
                               (answers . [((id . "q1")
                                            (selected . ["A"])
                                            (custom . "note"))
                                           ((id . "q2")
                                            (selected . []))]))]))))
         (active (dsh-protocol-user-questions-active view))
         (settled (dsh-protocol-user-questions-settled view)))
    (ert-info ((format "%s" "protocol-user-questions-decodes"))
      (should (= 1 (length active)))
      (should (eq 'continued (dsh-protocol-pending-question-state (car active))))
      (should (equal "c1" (dsh-protocol-pending-question-call-id (car active))))
      (should (= 2 (length (dsh-protocol-pending-question-questions (car active)))))
      (should (= 1 (length settled)))
      (should (equal '("A")
                     (dsh-protocol-question-answer-selected
                      (car (dsh-protocol-settled-question-answers (car settled))))))
      (should (equal "note"
                     (dsh-protocol-question-answer-custom
                      (car (dsh-protocol-settled-question-answers (car settled)))))))
    (let ((open (dsh-protocol-pending-question--from-alist
                 '((callId . "c2") (state . "open") (questions . [])))))
      (ert-info ((format "%s" "protocol-pending-question-open-state"))
        (should (eq 'open (dsh-protocol-pending-question-state open)))))))

(ert-deftest dsh-emacs-test-questions-protocol-user-questions-empty-decodes ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "protocol-user-questions-empty-decodes"))
    (should (let ((empty (dsh-protocol-user-questions--from-alist nil)))
              (null (dsh-protocol-user-questions-active empty))
              (null (dsh-protocol-user-questions-settled empty))))))

(ert-deftest dsh-emacs-test-questions-protocol-question-wait-flags-timed ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "protocol-question-wait-flags-timed"))
    (should (let ((timed (dsh-protocol-question-wait--from-alist
                          '((callId . "c9") (timed . t))))
                  (untimed (dsh-protocol-question-wait--from-alist '((callId . "c9")))))
              (equal "c9" (dsh-protocol-question-wait-call-id timed))
              (dsh-protocol-question-wait-timed timed)
              (not (dsh-protocol-question-wait-timed untimed))))))

(ert-deftest dsh-emacs-test-questions-ask-live-wire-result-case ()
  :tags '(dsh-unit)
  (dolist (case '(("{\"answers\":[{\"id\":\"q1\",\"selected\":[\"Stacked\"]}]}"
                   nil success "1/1 answered")
                  ("{\"pending\":true,\"callId\":\"wire-call\"}"
                   nil success "pending")
                  ("The question failed" t error "The question failed")))
    ;; Captured dsh 0.2.0 shape: text and isError belong to the tool message,
    ;; not to a nested content block with type=tool-result.
    (pcase-let ((`(,text ,is-error ,state ,summary) case))
      (with-temp-buffer
        (dsh-emacs-mode)
        (dsh-emacs-modeline-setup)
        (dsh-emacs-render-tool-call
         (dsh-emacs-test--tool-call-event
          1 "wire-call" "ask_user_question" dsh-emacs-test--ask-args))
        (dsh-emacs-render-tool-result
         `((type . "tool/result") (seq . 2)
           (data . ((message . ((role . "tool")
                                (source . ((kind . "tool") (callId . "wire-call")))
                                (toolCallId . "wire-call")
                                (content . [((type . "text") (text . ,text))])
                                (isError . ,(if is-error t :json-false))))))))
        (let ((result (dsh-emacs-render--tool-state "wire-call"))
              (block (dsh-emacs-test--tool-block-text
                      (dsh-emacs-render--make-namespace) "tool-wire-call")))
          (ert-info ((format "%s" (format "ask-live-wire-result-%s" summary)))
            (should (equal (plist-get result :result) text))
            (should (eq (plist-get result :state) state))
            (should (string-match-p (regexp-quote summary) block))))))))

(ert-deftest dsh-emacs-test-questions-ask-pending-result-is-summarized-and-explained ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "kp" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "kp" nil 0
      (json-encode '((pending . t) (callId . "kp")
                     (message . "No answer batch arrived before the timeout.")))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-kp")))
      (ert-info ((format "%s" "ask-pending-result-is-summarized-and-explained"))
        (should (string-match-p "Ask question · pending" block))
        (should (string-match-p "Composer" block))))))

(ert-deftest dsh-emacs-test-questions-ask-settled-late-answer-completes-the-pending-card ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "ks" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "ks" nil 0 (json-encode '((pending . t) (callId . "ks")))))
    ;; The settled cell of the projection is what completes the pending row.
    (dsh-emacs-interaction--questions-projected
     (dsh-protocol-user-questions--from-alist
      '((active . [])
        (settled . [((callId . "ks")
                     (answers . [((id . "q1") (selected . ["Stacked"]))
                                 ((id . "q2") (selected . [])
                                  (custom . "late"))]))]))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-ks")))
      (ert-info ((format "%s" "ask-settled-late-answer-completes-the-pending-card"))
        (should (string-match-p "Ask question · 2/2 answered" block))
        (should (string-match-p "^   1\\. ✓ Stacked$" block))
        (should (string-match-p "^  → late$" block))
        (should (not (string-match-p "pending" block)))))))

(ert-deftest dsh-emacs-test-questions-ask-late-answer-respects-display-gate ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-show-tool-calls t)
    (setq-local dsh-emacs-tool-expand-by-default nil)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "hidden-ask" "ask_user_question" dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "hidden-ask" nil 0
      (json-encode '((pending . t) (callId . "hidden-ask")))))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (before (buffer-string))
           (state (copy-tree (dsh-emacs-render--tool-state "hidden-ask")))
           (answers (json-encode
                     '((answers . [((id . "q1") (selected . ["Stacked"]))])))))
      (should (string-match-p "Ask question · pending" before))
      (setq-local dsh-emacs-show-tool-calls nil)
      (should-not (dsh-emacs-render-question-settled "hidden-ask" answers))
      (should (equal before (buffer-string)))
      (should (equal state (dsh-emacs-render--tool-state "hidden-ask")))
      (setq-local dsh-emacs-show-tool-calls t)
      (dsh-emacs-render-question-settled "hidden-ask" answers)
      (should (equal answers
                     (plist-get (dsh-emacs-render--tool-state "hidden-ask")
                                :result)))
      (let ((block (dsh-emacs-test--tool-block-text ns "tool-hidden-ask")))
        (should (string-match-p "Ask question · 1/1 answered" block))
        ;; Completing the row preserves the user's collapsed presentation.
        (should-not (string-match-p "Which layout" block)))
      (goto-char (car (dsh-emacs-ui-find-block ns "tool-hidden-ask")))
      (dsh-emacs-ui-toggle-fragment)
      (should (string-match-p
               "^   1\\. ✓ Stacked$"
               (dsh-emacs-test--tool-block-text ns "tool-hidden-ask")))
      (let ((completed (buffer-string))
            (settled-state
             (copy-tree (dsh-emacs-render--tool-state "hidden-ask"))))
        (should-not
         (dsh-emacs-render-question-settled
          "hidden-ask"
          (json-encode
           '((answers . [((id . "q1") (selected . ["Compact"]))])))))
        (should (equal completed (buffer-string)))
        (should (equal settled-state
                       (dsh-emacs-render--tool-state "hidden-ask")))))))

(ert-deftest dsh-emacs-test-questions-ask-in-time-answer-is-not-overwritten-by-projection ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "ki" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "ki" nil 0
      (json-encode '((answers . [((id . "q1") (selected . ["Stacked"]))
                                 ((id . "q2") (selected . []))])))))
    (dsh-emacs-render-question-settled
     "ki"
     (dsh-protocol-question-answers-json
      (list (dsh-protocol-question-answer--from-alist
             '((id . "q1") (selected . ["Compact"]))))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-ki")))
      (ert-info ((format "%s" "ask-in-time-answer-is-not-overwritten-by-projection"))
        (should (string-match-p "Ask question · 1/2 answered" block))
        (should (string-match-p "^   1\\. ✓ Stacked$" block))
        (should (not (string-match-p "✓ Compact" block)))))))

(ert-deftest dsh-emacs-test-questions-ask-snapshot-settles-a-resumed-pending-card ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (setq-local dsh-emacs--buffer-session "sess-uq")
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "kr" "ask_user_question"
                                      dsh-emacs-test--ask-args))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "kr" nil 0 (json-encode '((pending . t) (callId . "kr")))))
    ;; A resumed transcript's snapshot carries the settled cell, applied after
    ;; the records have rendered.
    (dsh-emacs-events--apply-snapshot-projections
     "sess-uq"
     '((values . ((userQuestions
                   . ((active . [])
                      (settled . [((callId . "kr")
                                   (answers . [((id . "q1")
                                                (selected . ["Stacked"]))]))])))))))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-kr")))
      (ert-info ((format "%s" "ask-snapshot-settles-a-resumed-pending-card"))
        (should (string-match-p "Ask question · 1/1 answered" block))
        (should (string-match-p "^   1\\. ✓ Stacked$" block))
        (should (not (string-match-p "pending" block)))))))

;; Both asynchronous failure and synchronous exits release the wait claim.

;;; dsh-test-questions.el ends here

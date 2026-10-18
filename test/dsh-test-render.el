;;; dsh-test-render.el --- Render tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)

;; --- Test 9: event renderer functions exist ---
(ert-deftest dsh-emacs-test-render-render-event-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-event function exists"))
    (should (fboundp 'dsh-emacs-render-event))))

(ert-deftest dsh-emacs-test-render-render-history-events-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-history-events function exists"))
    (should (fboundp 'dsh-emacs-render-history-events))))

(ert-deftest dsh-emacs-test-render-render-user-message-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-user-message function exists"))
    (should (fboundp 'dsh-emacs-render-user-message))))

(ert-deftest dsh-emacs-test-render-render-assistant-message-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-assistant-message function exists"))
    (should (fboundp 'dsh-emacs-render-assistant-message))))

(ert-deftest dsh-emacs-test-render-render-tool-call-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-tool-call function exists"))
    (should (fboundp 'dsh-emacs-render-tool-call))))

(ert-deftest dsh-emacs-test-render-render-tool-result-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-tool-result function exists"))
    (should (fboundp 'dsh-emacs-render-tool-result))))

;; --- Test 19: assistant replies remain in history order ---
(ert-deftest dsh-emacs-test-render-assistant-replies-keep-order ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (let ((first (json-read-from-string
                  "{\"event\":{\"type\":\"assistant/message\",\"seq\":1,\"data\":{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"reply-1\"}]}}}}"))
          (second (json-read-from-string
                   "{\"event\":{\"type\":\"assistant/message\",\"seq\":2,\"data\":{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"reply-2\"}]}}}}")))
      (dsh-emacs-render-history-events (list first second))
      (let ((text (buffer-substring-no-properties (point-min) (point-max))))
        (ert-info ((format "%s" "assistant-replies-keep-order"))
          (should (and (< (string-match "reply-1" text)
                          (string-match "reply-2" text))
                       (string-match "reply-1\n" text)
                       (string-match "reply-2\n" text))))))))

;; --- Test 20: chat prefix and rendered Markdown ---
(ert-deftest dsh-emacs-test-render-chat-prefix-and-markdown-render ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (let ((user (json-read-from-string
                 "{\"type\":\"user/message\",\"seq\":1,\"data\":{\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}}"))
          (assistant (json-read-from-string
                      "{\"type\":\"assistant/message\",\"seq\":2,\"data\":{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"# title\\n**bold**\"}]}}}")))
      (dsh-emacs-render-event user)
      (dsh-emacs-render-event assistant)
      (let* ((text (buffer-substring (point-min) (point-max)))
             (title-pos (string-match "title" text))
             (bold-pos (string-match "bold" text))
             (title-face (and title-pos (get-text-property (1+ title-pos) 'face text)))
             (bold-face (and bold-pos (get-text-property (1+ bold-pos) 'face text))))
        (ert-info ((format "%s" "chat-prefix-and-markdown-render"))
          (should (and (string-match "❯ hello" text)
                       (member 'dsh-emacs-markdown-header-1
                               (if (listp title-face) title-face (list title-face)))
                       (member 'dsh-emacs-markdown-bold
                               (if (listp bold-face) bold-face (list bold-face))))))))))

;; Packed stream records reconstruct in order, tool calls included.
(ert-deftest dsh-emacs-test-render-attempt-stream-text-reconstructs ()
  :tags '(dsh-unit)
  (let ((records (dsh-protocol--assistant-records
                  '[((type . "reasoning-chunks") (texts . ["think"]))
                    ((type . "tool-call-chunks") (name . "bash")
                     (args . ["{\"command\":\"ls\"}"]))
                    ((type . "text-chunks") (texts . ["reply"]))])))
    (should (equal (dsh-emacs-render--assistant-stream-text records)
                   "think\n→ bash {\"command\":\"ls\"}\nreply"))))

(ert-deftest dsh-emacs-test-render-attempt-stream-text-respects-reasoning-option ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-show-reasoning nil)
        (records (dsh-protocol--assistant-records
                  '[((type . "reasoning-chunks") (texts . ["hidden think"]))])))
    (should (equal (dsh-emacs-render--assistant-stream-text records) ""))))

;; A live body the attempt settles is taken over, never painted twice.
(ert-deftest dsh-emacs-test-render-attempt-takes-over-live-body ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render--start-assistant-stream
     '((data . ((turn . 1) (step . 1)))) "live partial")
    (dsh-emacs-render-event
     (json-read-from-string
      "{\"type\":\"assistant/attempt\",\"seq\":5,\"time\":2000,\"data\":{\"turn\":1,\"step\":1,\"stream\":[{\"type\":\"text-chunks\",\"time0\":1,\"index\":0,\"dt\":[1],\"texts\":[\"live partial\"]}]}}"))
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (ert-info ((format "%s" "attempt-takes-over-live-body"))
        (should (null dsh-emacs--streaming-assistant))
        (should (string-match-p "Incomplete reply" text))
        (should (= 2 (length (split-string text "live partial" nil))))))))

;; Failed attempts own all their blocks, including folded/live reasoning.
(ert-deftest dsh-emacs-test-render-attempt-clears-all-live-blocks ()
  :tags '(dsh-unit)
  (dolist (types '(("reasoning") ("reasoning" "text" "reasoning" "text")))
    (with-temp-buffer
      (dsh-emacs-mode)
      (let ((dsh-emacs-thinking-expand-by-default t)
            (dsh-emacs-thinking-preview-max 0)
            records)
        (cl-loop for type in types for index from 0
                 for body = (format "failed-%s-%d" type index)
                 do (push `((type . ,(concat type "-chunks"))
                            (index . ,index) (texts . [,body])) records)
                 do (dsh-emacs-render-event
                     `((type . "assistant/chunk")
                       (data . ((turn . 1) (step . 1)
                                (chunk . ((type . ,(concat type "-delta"))
                                          (index . ,index) (text . ,body))))))))
        (goto-char (point-max))
        (insert "keep draft")
        (dsh-emacs-render-event
         `((type . "assistant/attempt") (seq . 5)
           (data . ((turn . 1) (step . 1)
                    (stream . ,(vconcat (nreverse records)))))))
        (ert-info ((format "%s" "attempt-clears-all-live-blocks"))
          (should (null dsh-emacs--streaming-assistant))
          (should (null dsh-emacs--streaming-thinking))
          (should (null dsh-emacs--streamed-step))
          (should (= (how-many "Think" (point-min) (point-max)) 0))
          (should (string-suffix-p "keep draft" (buffer-string))))
        (cl-loop for type in types for index from 0
                 do (ert-info ((format "%s" "attempt-owns-each-failed-block-once"))
                      (should (= (how-many (format "failed-%s-%d" type index)
                                           (point-min) (point-max)) 1))))
        ;; A retry may reuse turn/step and block index zero without any deltas.
        (dsh-emacs-render-event
         '((type . "assistant/chunk")
           (data . ((turn . 1) (step . 1)
                    (chunk . ((type . "block-end") (index . 0)
                              (block . ((type . "reasoning")
                                        (text . "retry-only")))))))))
        (ert-info ((format "%s" "attempt-retry-starts-fresh"))
          (should (= (how-many "retry-only" (point-min) (point-max)) 1))
          (should (equal (plist-get dsh-emacs--streaming-thinking :all) '("retry-only"))))))))

;; Seed boundaries advance the anchor without changing the transcript.
(ert-deftest dsh-emacs-test-render-seed-boundary-consumed-without-divider ()
  :tags '(dsh-unit)
  (dolist (data '("{\"inherited\":true}" "{}"))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (let ((before (buffer-string)))
        (ert-info ((format "%s" "seed-boundary-consumed-without-divider"))
          (should (= (dsh-emacs-render-event
                      (json-read-from-string
                       (format "{\"type\":\"session/end-seed\",\"seq\":7,\"data\":%s}"
                               data)))
                     7))
          (should (= dsh-emacs--anchor-seq 7))
          (should (equal (buffer-string) before)))))))

;; deliverables/presented: collected, rendered once at the turn's tail.
(ert-deftest dsh-emacs-test-render-deliverables-decoded-view ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (let ((view (dsh-protocol-deliverables--from-alist
                 '((seq . 71) (data (turn . 8)
                                    (files . [((path . "report.md")
                                               (description . "First"))]))))))
      (should (= 71 (dsh-emacs-render-deliverables view)))
      (should (equal '((8 ("report.md" . "First")))
                     dsh-emacs-render--turn-deliverables)))
    (should (= 72 (dsh-emacs-render-deliverables
                   '((seq . 72) (data (turn . 8) (files . []))))))
    (should (= 73 (dsh-emacs-render-deliverables
                   '((seq . 73) (data (turn . "invalid")
                                      (files . [((path . "ignore.md"))]))))))
    (should (equal '((8 ("report.md" . "First")))
                   dsh-emacs-render--turn-deliverables))))

(ert-deftest dsh-emacs-test-render-deliverables-deferred-until-turn-end ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render-event
     (json-read-from-string
      "{\"type\":\"assistant/message\",\"seq\":1,\"data\":{\"turn\":1,\"step\":1,\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"closing reply\"}]}}}"))
    (dsh-emacs-render-event
     (json-read-from-string
      "{\"type\":\"deliverables/presented\",\"seq\":2,\"data\":{\"turn\":1,\"callId\":\"c1\",\"files\":[{\"path\":\"report.md\",\"description\":\"Final report\"},{\"path\":\"notes.txt\"}]}}"))
    (ert-info ((format "%s" "deliverables-deferred-until-turn-end"))
      (should (not (string-match-p "Deliverables"
                                   (buffer-substring-no-properties (point-min) (point-max))))))
    (dsh-emacs-render-event
     (json-read-from-string
      "{\"type\":\"turn/end\",\"seq\":3,\"data\":{\"turn\":1,\"reason\":{\"kind\":\"completed\"}}}"))
    (let* ((full (buffer-string))
           (text (buffer-substring-no-properties (point-min) (point-max)))
           (reply (string-match "closing reply" full))
           (row (string-match "Deliverables" full)))
      (ert-info ((format "%s" "deliverables-row-at-turn-tail-collapsed"))
        (should (string-match-p "Deliverables · 2 files" text))
        (should (not (string-match-p "report.md" text)))
        (should (and reply row (< reply row))))
      (ert-info ((format "%s" "deliverables-row-leads-with-green-dot"))
        (should (let ((dot (string-match "●" full)))
                  (and dot
                       (memq 'dsh-emacs-deliverable-dot-face
                             (ensure-list (get-text-property dot 'face full)))))))
      (ert-info ((format "%s" "deliverables-title-uses-own-face"))
        (should (let ((title (string-match "Deliverables" full)))
                  (and title
                       (memq 'dsh-emacs-deliverable-text-face
                             (ensure-list (get-text-property title 'face full)))))))
      ;; Expanding shows the file lines in the bash-card panel surface.
      (goto-char (point-min))
      (search-forward "Deliverables")
      (dsh-emacs-ui-toggle-fragment)
      (setq full (buffer-string)
            text (buffer-substring-no-properties (point-min) (point-max)))
      (let ((path (string-match (regexp-quote "report.md") full)))
        (ert-info ((format "%s" "deliverables-expanded-shows-files"))
          (should (string-match-p "Final report" text))
          (should (string-match-p "notes.txt" text)))
        (ert-info ((format "%s" "deliverables-path-is-clickable"))
          (should (equal '(file . "report.md")
                         (get-text-property path 'dsh-emacs-reference-ref full)))
          (should (memq 'dsh-emacs-reference-face
                        (ensure-list (get-text-property path 'face full)))))))))

;; Repeated declaration of one path keeps one line, latest description.
(ert-deftest dsh-emacs-test-render-deliverables-merge-last-wins ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dolist (json '("{\"type\":\"deliverables/presented\",\"seq\":1,\"data\":{\"turn\":4,\"callId\":\"a\",\"files\":[{\"path\":\"out.md\",\"description\":\"old\"}]}}"
                    "{\"type\":\"deliverables/presented\",\"seq\":2,\"data\":{\"turn\":4,\"callId\":\"b\",\"files\":[{\"path\":\"out.md\",\"description\":\"new\"}]}}"
                    "{\"type\":\"turn/end\",\"seq\":3,\"data\":{\"turn\":4,\"reason\":{\"kind\":\"completed\"}}}"))
      (dsh-emacs-render-event (json-read-from-string json)))
    (goto-char (point-min))
    (dsh-emacs-ui-toggle-fragment)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (ert-info ((format "%s" "deliverables-merge-last-wins"))
        (should (string-match-p "Deliverables · 1 file" text))
        (should (string-match-p "new" text))
        (should (not (string-match-p "old" text)))
        (should (= 2 (length (split-string text "out.md" nil))))))))

;; A snapshot tail cut before turn/end still renders the row (batch end),
;; and the flush clears the state so a later turn/end cannot render twice.
(ert-deftest dsh-emacs-test-render-deliverables-flushed-at-batch-end ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render-history-events
     (list (list (cons "event"
                       (json-read-from-string
                        "{\"type\":\"deliverables/presented\",\"seq\":1,\"data\":{\"turn\":7,\"callId\":\"c\",\"files\":[{\"path\":\"out.txt\"}]}}"))))
     nil)
    (ert-info ((format "%s" "deliverables-flushed-at-batch-end"))
      (should (string-match-p "Deliverables · 1 file"
                              (buffer-substring-no-properties (point-min) (point-max)))))
    (goto-char (point-min))
    (dsh-emacs-ui-toggle-fragment)
    (ert-info ((format "%s" "deliverables-batch-row-expands"))
      (should (string-match-p "out.txt"
                              (buffer-substring-no-properties (point-min) (point-max)))))
    (dsh-emacs-render-event
     (json-read-from-string
      "{\"type\":\"turn/end\",\"seq\":2,\"data\":{\"turn\":7,\"reason\":{\"kind\":\"completed\"}}}"))
    (ert-info ((format "%s" "deliverables-flush-does-not-double-render"))
      (should (null dsh-emacs-render--turn-deliverables))
      (should (= 1 (cl-count ?● (buffer-substring-no-properties (point-min) (point-max))))))))

;; A newline inside a model-written description cannot fake a second file.
(ert-deftest dsh-emacs-test-render-deliverable-description-flattened ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dolist (json '("{\"type\":\"deliverables/presented\",\"seq\":1,\"data\":{\"turn\":1,\"callId\":\"c\",\"files\":[{\"path\":\"a.md\",\"description\":\"one\\ntwo\"}]}}"
                    "{\"type\":\"turn/end\",\"seq\":2,\"data\":{\"turn\":1,\"reason\":{\"kind\":\"completed\"}}}"))
      (dsh-emacs-render-event (json-read-from-string json)))
    (goto-char (point-min))
    (dsh-emacs-ui-toggle-fragment)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (ert-info ((format "%s" "deliverable-description-flattened"))
        (should (string-match-p "a.md — one two" text))))))

;; The reference module owns the clickable file-path presentation.
(ert-deftest dsh-emacs-test-render-reference-file-link-propertizes ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "reference-file-link-propertizes"))
    (should (let ((span (dsh-emacs-reference-file-link "a.md")))
              (and (equal '(file . "a.md")
                          (get-text-property 0 'dsh-emacs-reference-ref span))
                   (eq 'dsh-emacs-reference-face (get-text-property 0 'face span)))))
    (should (equal "" (dsh-emacs-reference-file-link "")))))

;; The row title carries its own hue: it must not blend into the green dot,
;; and must not read as a second link color next to the clickable paths.
(ert-deftest dsh-emacs-test-render-deliverables-title-color-differs-from-dot ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "deliverables-title-color-differs-from-dot"))
    (should (let ((title (face-foreground 'dsh-emacs-deliverable-text-face nil t))
                  (dot (face-foreground 'dsh-emacs-deliverable-dot-face nil t)))
              (and title dot (not (equal title dot)))))))

(ert-deftest dsh-emacs-test-render-deliverables-title-color-differs-from-link ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "deliverables-title-color-differs-from-link"))
    (should (let ((title (face-foreground 'dsh-emacs-deliverable-text-face nil t))
                  (link (face-foreground 'dsh-emacs-reference-face nil t)))
              (and title link (not (equal title link)))))))

;; --- Test 27g: one blank line around user messages; assistant messages still
;; stay tight ---
(ert-deftest dsh-emacs-test-render-user-message-spaced-above-and-below ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t27g-layout*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-modeline-setup)
          (dsh-emacs-render-event
           (json-read-from-string
            "{\"type\":\"assistant/message\",\"seq\":1,\"data\":{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"a1\"}]}}}"))
          (dsh-emacs-render-event
           (json-read-from-string
            "{\"type\":\"assistant/message\",\"seq\":2,\"data\":{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"a2\"}]}}}"))
          (dsh-emacs-render-event
           (json-read-from-string
            "{\"type\":\"user/message\",\"seq\":3,\"data\":{\"content\":[{\"type\":\"text\",\"text\":\"u1\"}]}}"))
          (dsh-emacs-render-event
           (json-read-from-string
            "{\"type\":\"assistant/message\",\"seq\":4,\"data\":{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"a3\"}]}}}"))
          (let* ((user-line
                  (save-excursion
                    (goto-char (point-min))
                    (when (search-forward "❯ u1" nil t)
                      (line-number-at-pos (line-beginning-position)))))
                 (above-blank
                  (and user-line
                       (save-excursion
                         (goto-char (point-min))
                         (forward-line (- user-line 2))
                         (looking-at-p "[ \t]*$"))))
                 (below-blank
                  (and user-line
                       (save-excursion
                         (goto-char (point-min))
                         (forward-line user-line)
                         (looking-at-p "[ \t]*$"))))
                 (a1-line (save-excursion
                            (goto-char (point-min))
                            (when (search-forward "a1" nil t)
                              (line-number-at-pos (line-beginning-position)))))
                 (a2-line (save-excursion
                            (goto-char (point-min))
                            (when (search-forward "a2" nil t)
                              (line-number-at-pos (line-beginning-position))))))
            (ert-info ((format "%s" "user-message-spaced-above-and-below"))
              (should (and above-blank below-blank)))
            ;; Adjacent assistant messages still stay tight (no blank line)
            (ert-info ((format "%s" "assistant-messages-remain-flush"))
              (should (and a1-line a2-line (= a2-line (1+ a1-line)))))))
      (kill-buffer buf))))

;; Reply footers summarize a turn, not the session or just its last step.
(ert-deftest dsh-emacs-test-render-footer-option-can-disable-row ()
  :tags '(dsh-unit)
  (let* ((start '((type . "turn/start") (seq . 100) (time . 1000)
                  (data . ((turn . 7)))))
         (first '((type . "assistant/message") (seq . 101)
                  (data . ((turn . 7) (step . 1)
                           (usage . ((inputTokens . 10) (outputTokens . 20)
                                     (cacheReadTokens . 30) (cacheWriteTokens . 40)))
                           (message . ((content . [((type . "text")
                                                    (text . "earlier reply"))])))))))
         (last '((type . "assistant/message") (seq . 102)
                 (data . ((turn . 7) (step . 2)
                          (usage . ((inputTokens . 1) (outputTokens . 2)
                                    (cacheReadTokens . 3) (cacheWriteTokens . 4)))
                          (message . ((content . [((type . "text")
                                                   (text . "**final reply**"))])))))))
         (end '((type . "turn/end") (seq . 103) (time . 3500)
                (data . ((turn . 7)))))
         (events (mapcar (lambda (event) (list (cons 'event event)))
                         (list start first last end))))
    (dolist (items '(nil (duration copy) (copy fork usage duration)))
      (with-temp-buffer
        (dsh-emacs-mode)
        (setq dsh-emacs--buffer-session "footer-parent")
        (let ((dsh-emacs-reply-footer-items items)
              (dsh-emacs-stream-markdown-limit 1)
              forked)
          (dsh-emacs-render-history-events events)
          (while dsh-emacs--markdown-pending
            (dsh-emacs-render--run-markdown (current-buffer)))
          (let ((row (dsh-emacs-ui-find-block "sess-global" "reply-footer-7")))
            (ert-info ((format "%s" "footer-option-can-disable-row"))
              (should (eq (null row) (null items))))
            (when row
              (let ((text (buffer-substring-no-properties (car row) (cdr row))))
                (ert-info ((format "%s" "footer-order-and-per-turn-statistics"))
                  (should (string-match-p
                           (if (eq (car items) 'duration) "Time 2.5s  ·  Copy"
                             "Copy  ·  Fork  ·  Tokens 110  ·  Time 2.5s") text))
                  (should (= (how-many "Copy" (point-min) (point-max)) 1))
                  (should (not (get-text-property (car row) 'dsh-emacs-assistant-message)))
                  (should (not (get-text-property (car row) 'dsh-emacs-message-seq))))
                (goto-char (car row))
                (search-forward "Copy")
                (button-activate (button-at (1- (point))))
                (ert-info ((format "%s" "footer-copy-keeps-markdown-and-excludes-chrome"))
                  (should (equal (current-kill 0) "**final reply**")))
                (when (memq 'fork items)
                  (goto-char (car row))
                  (search-forward "Fork")
                  (cl-letf (((symbol-function 'dsh-emacs-fork-session)
                             (lambda (session seq) (setq forked (list session seq)))))
                    (button-activate (button-at (1- (point)))))
                  (ert-info ((format "%s" "footer-fork-targets-the-final-reply"))
                    (should (equal forked '("footer-parent" 102)))))))))))
    ;; A tail with no turn/start must not claim to contain all turn usage.
    ;; Prepending the older page updates the existing footer in place.
    (with-temp-buffer
      (dsh-emacs-mode)
      (let ((dsh-emacs-reply-footer-items '(usage duration)))
        (dsh-emacs-render-history-events (nthcdr 2 events))
        (ert-info ((format "%s" "footer-partial-history-is-explicit"))
          (should (string-match-p "Tokens ≥10  ·  Time —" (buffer-string))))
        (let* ((dsh-emacs--history-insert-marker
                (dsh-emacs-render--history-prepend-marker))
               (position (marker-position dsh-emacs--history-insert-marker)))
          (dsh-emacs-render-history-events (cl-subseq events 0 2) nil 102
                                           :insert-before position :follow-p nil)
          (set-marker dsh-emacs--history-insert-marker nil))
        (ert-info ((format "%s" "footer-older-page-completes-stats-without-duplicates"))
          (should (string-match-p "Tokens 110  ·  Time 2.5s" (buffer-string)))
          (should (= (how-many "Tokens" (point-min) (point-max)) 1)))
        (dsh-emacs-render-history-events events)
        (ert-info ((format "%s" "footer-reconnect-does-not-double-count"))
          (should (string-match-p "Tokens 110  ·  Time 2.5s" (buffer-string)))
          (should (= (how-many "Tokens" (point-min) (point-max)) 1)))))
    (with-temp-buffer
      (dsh-emacs-mode)
      (setq dsh-emacs--buffer-subagent
            (dsh-protocol-subagent-address-create "parent" "child" "continuable"))
      (dsh-emacs-render-history-events events)
      (ert-info ((format "%s" "footer-subagent-hides-fork-but-keeps-copy"))
        (should (string-match-p "Copy" (buffer-string)))
        (should (not (string-match-p "Fork" (buffer-string))))))))

;; Consecutive replies without a rendered human message share one visible footer.
(ert-deftest dsh-emacs-test-render-footer-continuations-latest-only-case-case ()
  :tags '(dsh-unit)
  (dolist (delivery '(live history prepend reconnect))
    (dolist (items '((copy fork usage duration) (usage duration)))
      (with-temp-buffer
        (dsh-emacs-mode)
        (setq-local dsh-emacs--buffer-session "footer-continuations")
        (let* ((dsh-emacs-reply-footer-items items)
               (events
                '(((type . "turn/start") (seq . 1) (time . 0) (data . ((turn . 1))))
                  ((type . "user/message") (seq . 2)
                   (data . ((content . [((type . "text") (text . "Question"))]))))
                  ((type . "assistant/message") (seq . 3)
                   (data . ((turn . 1) (step . 1)
                            (usage . ((inputTokens . 100) (outputTokens . 2)))
                            (message . ((content . [((type . "text")
                                                     (text . "**Main answer**"))]))))))
                  ((type . "turn/end") (seq . 4) (time . 1000) (data . ((turn . 1))))
                  ((type . "turn/start") (seq . 5) (time . 2000) (data . ((turn . 2))))
                  ((type . "user/message") (seq . 6)
                   (data . ((source . ((kind . "subagent-settled")))
                            (content . [((type . "text") (text . "Hidden child notice"))]))))
                  ((type . "assistant/message") (seq . 7)
                   (data . ((turn . 2) (step . 1)
                            (usage . ((inputTokens . 10) (outputTokens . 2)))
                            (message . ((content . [((type . "text")
                                                     (text . "**Follow-up**"))]))))))
                  ((type . "turn/end") (seq . 8) (time . 4000) (data . ((turn . 2))))))
               (entries (mapcar (lambda (event) (list (cons 'event event))) events))
               (ns (dsh-emacs-render--make-namespace)))
          (pcase delivery
            ('live (dolist (event events) (dsh-emacs-render-event event)))
            ('prepend
             (dsh-emacs-render-history-events (nthcdr 4 entries))
             (let* ((dsh-emacs--history-insert-marker
                     (dsh-emacs-render--history-prepend-marker))
                    (position (marker-position dsh-emacs--history-insert-marker)))
               (dsh-emacs-render-history-events
                (cl-subseq entries 0 4) nil 5 :insert-before position :follow-p nil)
               (set-marker dsh-emacs--history-insert-marker nil)))
            (_ (dsh-emacs-render-history-events entries)
               (when (eq delivery 'reconnect)
                 (dsh-emacs-render-history-events entries))))
          (ert-info ((format "%s" (format "footer-continuations-latest-only-%s-%s" delivery items)))
            (should (null (dsh-emacs-ui-find-block ns "reply-footer-1")))
            (should (dsh-emacs-ui-find-block ns "reply-footer-2"))
            (should (= (how-many "Tokens" (point-min) (point-max)) 1))
            (should (string-match-p "Tokens 12  ·  Time 2.0s" (buffer-string)))
            (should (string-match-p "Main answer" (buffer-string)))
            (should (string-match-p "Follow-up" (buffer-string)))
            (should (not (string-match-p "Hidden child notice" (buffer-string)))))
          (when (memq 'copy items)
            (goto-char (point-min))
            (search-forward "Copy")
            (let ((button (button-at (1- (point)))))
              (button-activate button)
              (ert-info ((format "%s" "footer-continuations-copy-target-stays-last-reply"))
                (should (equal (current-kill 0) "**Follow-up**"))
                (should (= (button-get button 'dsh-emacs-reply-seq) 7))))
            (goto-char (point-min))
            (search-forward "Fork")
            (let (forked)
              (cl-letf (((symbol-function 'dsh-emacs-fork-session)
                         (lambda (session seq) (setq forked (list session seq)))))
                (button-activate (button-at (1- (point)))))
              (ert-info ((format "%s" "footer-continuations-fork-target-stays-last-reply"))
                (should (equal forked '("footer-continuations" 7))))))
          ;; No completed text in a subsequent turn must not steal the toolbar.
          (dsh-emacs-render-event
           '((type . "turn/start") (seq . 9) (data . ((turn . 3)))))
          (ert-info ((format "%s" "footer-continuations-pending-turn-keeps-last-footer"))
            (should (dsh-emacs-ui-find-block ns "reply-footer-2")))
          (dsh-emacs-render-event
           '((type . "assistant/message") (seq . 10)
             (data . ((turn . 3) (message . ((content . [])))))))
          (dsh-emacs-render-event
           '((type . "turn/end") (seq . 11) (data . ((turn . 3)))))
          (ert-info ((format "%s" "footer-continuations-empty-turn-keeps-last-footer"))
            (should (dsh-emacs-ui-find-block ns "reply-footer-2"))
            (should (null (dsh-emacs-ui-find-block ns "reply-footer-3"))))
          ;; A visible human message, including an optimistic echo, splits groups.
          (dsh-emacs-render-user-message
           '((type . "user/message") (seq . 12)
             (data . ((content . [((type . "text") (text . "New question"))])))))
          (dsh-emacs-render-event
           '((type . "assistant/message") (seq . 13)
             (data . ((turn . 4) (step . 1)
                      (message . ((content . [((type . "text") (text . "New answer"))])))))))
          (dsh-emacs-render-event
           '((type . "turn/end") (seq . 14) (data . ((turn . 4)))))
          ;; Repainting older facts must neither resurrect an obsolete toolbar
          ;; nor remove the toolbar on the far side of a human message.
          (dolist (turn '(1 2))
            (dsh-emacs-render--reply-footer turn (gethash turn dsh-emacs-render--reply-turns)))
          (ert-info ((format "%s" "footer-continuations-preserve-human-boundaries-on-repaint"))
            (should (null (dsh-emacs-ui-find-block ns "reply-footer-1")))
            (should (dsh-emacs-ui-find-block ns "reply-footer-2"))
            (should (dsh-emacs-ui-find-block ns "reply-footer-4"))
            (should (= (how-many "Tokens" (point-min) (point-max)) 2)))
          (dsh-emacs-render-event
           '((type . "user/message") (seq . 15)
             (data . ((source . ((kind . "goal")))
                      (content . [((type . "text") (text . "Automatic goal round"))])))))
          (dsh-emacs-render-event
           '((type . "assistant/message") (seq . 16)
             (data . ((turn . 5) (step . 1)
                      (message . ((content . [((type . "text") (text . "Goal follow-up"))])))))))
          (dsh-emacs-render-event
           '((type . "turn/end") (seq . 17) (data . ((turn . 5)))))
          (ert-info ((format "%s" "footer-continuations-goal-notice-is-not-human-boundary"))
            (should (string-match-p "Continuing goal" (buffer-string)))
            (should (dsh-emacs-ui-find-block ns "reply-footer-2"))
            (should (null (dsh-emacs-ui-find-block ns "reply-footer-4")))
            (should (dsh-emacs-ui-find-block ns "reply-footer-5"))
            (should (= (how-many "Tokens" (point-min) (point-max)) 2))))))))

;; A streamed reply can straddle a human message.  Its final segment owns
;; its group, even when an older turn is repainted after a history prepend.
(ert-deftest dsh-emacs-test-render-footer-split-reply-before-prepend ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs--buffer-session "footer-split-reply")
    (let ((dsh-emacs-reply-footer-items '(copy usage)))
      (dolist (event
               '(((type . "user/message") (seq . 2)
                  (data . ((content . [((type . "text") (text . "Question"))]))))
                 ((type . "assistant/message") (seq . 3)
                  (data . ((turn . 1) (step . 1)
                           (message . ((content . [((type . "text") (text . "Answer"))]))))))
                 ((type . "turn/end") (seq . 4) (data . ((turn . 1))))
                 ((type . "assistant/chunk") (seq . 5)
                  (data . ((turn . 2) (step . 1)
                           (chunk . ((type . "text-delta") (index . 0) (text . "Before\n"))))))
                 ((type . "assistant/chunk") (seq . 6)
                  (data . ((turn . 2) (step . 1)
                           (chunk . ((type . "reasoning-delta") (index . 1) (text . "Think\n"))))))
                 ((type . "user/message") (seq . 7)
                  (data . ((content . [((type . "text") (text . "New question"))]))))
                 ((type . "assistant/chunk") (seq . 8)
                  (data . ((turn . 2) (step . 1)
                           (chunk . ((type . "text-delta") (index . 2) (text . "After\n"))))))
                 ((type . "assistant/message") (seq . 9)
                  (data . ((turn . 2) (step . 1)
                           (message . ((content . [((type . "text") (text . "Before\n"))
                                                   ((type . "reasoning") (text . "Think\n"))
                                                   ((type . "text") (text . "After\n"))]))))))
                 ((type . "turn/end") (seq . 10) (data . ((turn . 2))))))
        (dsh-emacs-render-event event)
        (dsh-emacs-render--flush-stream)
        (dsh-emacs-render--flush-thinking))
      (let* ((ns (dsh-emacs-render--make-namespace))
             (dsh-emacs--history-insert-marker
              (dsh-emacs-render--history-prepend-marker))
             (position (marker-position dsh-emacs--history-insert-marker)))
        (ert-info ((format "%s" "footer-split-reply-before-prepend"))
          (should (dsh-emacs-ui-find-block ns "reply-footer-1"))
          (should (dsh-emacs-ui-find-block ns "reply-footer-2")))
        (dsh-emacs-render-history-events
         '(((event . ((type . "turn/start") (seq . 1) (data . ((turn . 1)))))))
         nil 2 :insert-before position :follow-p nil)
        (set-marker dsh-emacs--history-insert-marker nil)
        (ert-info ((format "%s" "footer-split-reply-prepend-preserves-both-groups"))
          (should (dsh-emacs-ui-find-block ns "reply-footer-1"))
          (should (dsh-emacs-ui-find-block ns "reply-footer-2"))
          (should (= (how-many "Tokens" (point-min) (point-max)) 2)))))))

;; Rejecting an optimistic input merges its neighboring groups.  A completed
;; background follow-up wins; an unfinished one must leave the old row alone.
(ert-deftest dsh-emacs-test-render-footer-before-rollback-case ()
  :tags '(dsh-unit)
  (dolist (completed '(nil t))
    (with-temp-buffer
      (dsh-emacs-mode)
      (setq-local dsh-emacs--buffer-session "footer-rollback")
      (let ((dsh-emacs-reply-footer-items '(copy usage))
            (ns (dsh-emacs-render--make-namespace)))
        (dsh-emacs-render-event
         '((type . "user/message") (seq . 1)
           (data . ((content . [((type . "text") (text . "Question"))])))))
        (dsh-emacs-render-event
         '((type . "assistant/message") (seq . 2)
           (data . ((turn . 1) (step . 1)
                    (message . ((content . [((type . "text") (text . "Answer"))])))))))
        (dsh-emacs-render-event
         '((type . "turn/end") (seq . 3) (data . ((turn . 1)))))
        (let ((echo (dsh-emacs--render-user-message-optimistic "Rejected question" nil)))
          (dsh-emacs-render-event
           '((type . "assistant/message") (seq . 4)
             (data . ((turn . 2) (step . 1)
                      (message . ((content . [((type . "text") (text . "Follow-up"))])))))))
          (when completed
            (dsh-emacs-render-event
             '((type . "turn/end") (seq . 5) (data . ((turn . 2))))))
          (ert-info ((format "%s" (format "footer-before-rollback-%s" completed)))
            (should (dsh-emacs-ui-find-block ns "reply-footer-1"))
            (should (= (how-many "Tokens" (point-min) (point-max)) (if completed 2 1))))
          (dsh-emacs--discard-user-message-echo echo)
          (ert-info ((format "%s" (format "footer-rollback-reconciles-merged-group-%s" completed)))
            (should (not (string-match-p "Rejected question" (buffer-string))))
            (should (string-match-p "Answer" (buffer-string)))
            (should (string-match-p "Follow-up" (buffer-string)))
            (should (= (how-many "Tokens" (point-min) (point-max)) 1))
            (should (dsh-emacs-ui-find-block ns (if completed "reply-footer-2" "reply-footer-1")))
            (should (null (dsh-emacs-ui-find-block ns (if completed "reply-footer-1" "reply-footer-2")))))
          (goto-char (point-min))
          (search-forward "Copy")
          (button-activate (button-at (1- (point))))
          (ert-info ((format "%s" (format "footer-rollback-copy-target-%s" completed)))
            (should (equal (current-kill 0) (if completed "Follow-up" "Answer")))))))))

;; Deliverables belong above the footer, including expanded file lists.
(ert-deftest dsh-emacs-test-render-footer-after-deliverables-case-case ()
  :tags '(dsh-unit)
  (dolist (history '(nil t))
    (with-temp-buffer
      (dsh-emacs-mode)
      (let ((dsh-emacs-stream-markdown-limit 1)
            (events
             '(((type . "turn/start") (seq . 1) (data . ((turn . 1))))
               ((type . "deliverables/presented") (seq . 2)
                (data . ((turn . 1) (callId . "present-1")
                         (files . [((path . "report.md"))]))))
               ((type . "assistant/message") (seq . 3)
                (data . ((turn . 1) (step . 1)
                         (message . ((content . [((type . "text")
                                                  (text . "**final answer**"))]))))))
               ((type . "turn/end") (seq . 4) (data . ((turn . 1))))
               ((type . "user/message") (seq . 5)
                (data . ((content . [((type . "text")
                                      (text . "next question"))])))))))
        (if history
            (dsh-emacs-render-history-events
             (mapcar (lambda (event) (list (cons 'event event))) events))
          (dolist (event events)
            (dsh-emacs-render-event event)))
        (while dsh-emacs--markdown-pending
          (dsh-emacs-render--run-markdown (current-buffer)))
        (dotimes (expanded 2)
          (when (= expanded 1)
            (goto-char (point-min))
            (search-forward "Deliverables")
            (dsh-emacs-ui-toggle-fragment)
            (dsh-emacs-render--reply-footer
             1 (gethash 1 dsh-emacs-render--reply-turns)))
          (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
                 (reply (string-match "final answer" text))
                 (delivery (string-match "Deliverables" text))
                 (footer (string-match "Copy" text))
                 (next (string-match "next question" text)))
            (ert-info ((format "%s" (format "footer-after-deliverables-%s-%s"
                                            (if history "history" "live")
                                            (if (= expanded 1) "expanded" "collapsed"))))
              (should (and reply delivery footer next (< reply delivery footer next)))
              (should (or (= expanded 0)
                          (let ((file (string-match "report.md" text)))
                            (and file (< delivery file footer)))))
              (should (= (how-many "Copy" (point-min) (point-max)) 1)))))))))

;; A turn may end after diagnostics or tools, without another text reply.
(ert-deftest dsh-emacs-test-render-footer-after-turn-tail-case-case ()
  :tags '(dsh-unit)
  (dolist (history '(nil t prepend reconnect))
    (dolist (case
             '(("tool" "tail.txt"
                ((type . "tool/call") (seq . 3)
                 (data . ((turn . 1) (step . 1) (callId . "tail-tool")
                          (name . "read") (arguments . "{\"path\":\"tail.txt\"}")))))
               ("attempt" "Incomplete reply"
                ((type . "assistant/attempt") (seq . 3)
                 (data . ((turn . 1) (step . 2) (stream . [])))))
               ("compaction" "Context compaction failed"
                ((type . "compaction/end") (seq . 3)
                 (data . ((turn . 1) (compactionId . "tail-compaction")
                          (error . "compression failed")))))
               ("thinking" "Think"
                ((type . "assistant/message") (seq . 3)
                 (data . ((turn . 1) (step . 2)
                          (message . ((content . [((type . "reasoning")
                                                   (text . "unfinished reasoning"))])))))))
               ("error" "Model error")))
      (with-temp-buffer
        (dsh-emacs-mode)
        (pcase-let* ((`(,name ,label . ,tail) case)
                     (dsh-emacs-stream-markdown-limit 1)
                     (events
                      (append
                       '(((type . "turn/start") (seq . 1) (data . ((turn . 1))))
                         ((type . "assistant/message") (seq . 2)
                          (data . ((turn . 1) (step . 1)
                                   (message . ((content . [((type . "text")
                                                            (text . "**last text**"))])))))))
                       tail
                       `(((type . "turn/end") (seq . 4)
                          (data . ((turn . 1)
                                   (reason . ,(if (equal name "error")
                                                  '((kind . "error") (error . "provider failed"))
                                                '((kind . "completed")))))))
                         ((type . "user/message") (seq . 5)
                          (data . ((content . [((type . "text")
                                                (text . "next question"))]))))))))
          (let ((entries (mapcar (lambda (event) (list (cons 'event event))) events)))
            (pcase history
              ('nil (dolist (event events) (dsh-emacs-render-event event)))
              ('prepend
               (dsh-emacs-render-history-events (nthcdr 2 entries))
               (let* ((dsh-emacs--history-insert-marker
                       (dsh-emacs-render--history-prepend-marker))
                      (position (marker-position dsh-emacs--history-insert-marker)))
                 (dsh-emacs-render-history-events
                  (cl-subseq entries 0 2) nil 3 :insert-before position :follow-p nil)
                 (set-marker dsh-emacs--history-insert-marker nil)))
              (_ (dsh-emacs-render-history-events entries)
                 (when (eq history 'reconnect)
                   (dsh-emacs-render-history-events entries)))))
          (while dsh-emacs--markdown-pending
            (dsh-emacs-render--run-markdown (current-buffer)))
          (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
                 (tail-pos (string-match (regexp-quote label) text))
                 (footer (string-match "Copy" text))
                 (next (string-match "next question" text)))
            (ert-info ((format "%s" (format "footer-after-turn-tail-%s-%s" name history)))
              (should (and tail-pos footer next (< tail-pos footer next)))
              (should (= (how-many "Copy" (point-min) (point-max)) 1)))
            (goto-char (point-min))
            (search-forward "Copy")
            (button-activate (button-at (1- (point))))
            (ert-info ((format "%s" "footer-tail-keeps-last-text-copy-target"))
              (should (equal (current-kill 0) "**last text**")))))))))

;; A live completed reply may still be waiting for idle Markdown. The footer
;; must survive that replacement and must not become part of the message.
(ert-deftest dsh-emacs-test-render-footer-absent-during-live-stream ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (let ((dsh-emacs-stream-markdown-limit 1))
      (dsh-emacs-render-event
       '((type . "turn/start") (seq . 1) (time . 5000) (data . ((turn . 1)))))
      (dsh-emacs-render--start-assistant-stream
       '((data . ((turn . 1) (step . 1)))) "**stream answer**\n")
      (ert-info ((format "%s" "footer-absent-during-live-stream"))
        (should (not (string-match-p "Tokens" (buffer-string)))))
      (dsh-emacs-render-event
       '((type . "assistant/message") (seq . 2)
         (data . ((turn . 1) (step . 1)
                  (message . ((content . [((type . "text")
                                           (text . "**stream answer**\n"))])))))))
      (dsh-emacs-render-event
       '((type . "turn/end") (seq . 3) (time . 67000) (data . ((turn . 1)))))
      (while dsh-emacs--markdown-pending
        (dsh-emacs-render--run-markdown (current-buffer)))
      (ert-info ((format "%s" "footer-live-idle-formatting-keeps-row-and-unknown-usage"))
        (should (string-match-p "stream answer" (buffer-string)))
        (should (string-match-p "Tokens —  ·  Time 1m02s" (buffer-string)))
        (should (= (how-many "Copy" (point-min) (point-max)) 1)))
      (dsh-emacs-copy-last-assistant-message)
      (ert-info ((format "%s" "footer-never-enters-copy-last-reply"))
        (should (equal (current-kill 0) "stream answer")))
      (dsh-emacs-render--reset-tool-tracking)
      (ert-info ((format "%s" "footer-state-clears-on-full-reload"))
        (should (null dsh-emacs-render--reply-turns))))))

;; Synthetic fork endings must not turn old timestamps into a huge duration.
(ert-deftest dsh-emacs-test-render-footer-fork-end-has-no-elapsed-endpoint ()
  :tags '(dsh-unit)
  (let ((event (dsh-protocol-reply-event--from-alist
                '((type . "turn/end") (seq . 9) (time . 999999)
                  (data . ((turn . 1) (reason . ((kind . "forked")))))))))
    (ert-info ((format "%s" "footer-fork-end-has-no-elapsed-endpoint"))
      (should (null (dsh-protocol-reply-event-time event))))))

;; --- Test 98o: a non-envelope failure response (vendor error body passed
;; through) unwraps into a message ---
(ert-deftest dsh-emacs-test-render-unwrap-leaked-error-body-surfaces-message ()
  :tags '(dsh-unit)
  (let* ((response (json-read-from-string
                    "{\"message\":\"Allocated quota exceeded, please increase your quota limit.\",\"code\":\"insufficient_quota\"}"))
         (unwrapped (dsh-protocol-rpc-result--from-alist response)))
    (ert-info ((format "%s" "unwrap-leaked-error-body-surfaces-message"))
      (should (and (null (car unwrapped))
                   (string-match-p "Allocated quota exceeded" (cdr unwrapped)))))))

;; --- Test 101: todo plan row --- parse / one row per event (like a tool
;; card) / collapse ---
;; 101a: full snapshot collapse: drop empty content, unknown status
;; defaults to pending, counts are correct
(ert-deftest dsh-emacs-test-render-todo-parse-drops-invalid-defaults-status ()
  :tags '(dsh-unit)
  (let ((l (dsh-protocol-todos--from-alist
            "{\"todos\":[{\"content\":\"a\",\"status\":\"pending\"},{\"content\":\"b\",\"status\":\"in_progress\"},{\"content\":\"c\",\"status\":\"completed\"},{\"content\":\"\",\"status\":\"completed\"},{\"content\":\"d\"}]}")))
    (ert-info ((format "%s" "todo-parse-drops-invalid-defaults-status"))
      (should (and (= (length l) 4)
                   (equal (dsh-emacs-render--todo-counts l) '(1 1 2))
                   (string-match-p "1/4 completed" (dsh-emacs-render--todo-summary l)))))))

;; 101b: the first todo_write renders **one** todo row (with
;; progress/pending glyphs), it does not create an ordinary tool card
(ert-deftest dsh-emacs-test-render-todo-row-renders-on-write-no-card ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-todo-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "t1" "todo_write"
                                      "{\"todos\":[{\"content\":\"A\",\"status\":\"in_progress\"},{\"content\":\"B\",\"status\":\"pending\"}]}"))
    (let ((txt (buffer-string)))
      (ert-info ((format "%s" "todo-row-renders-on-write-no-card"))
        (should (and (dsh-emacs-ui-find-block dsh-emacs--todo-namespace "t1")
                     ;; items are ☐ checkboxes (in_progress/pending) with status words
                     (string-match-p (regexp-quote "☐") txt)
                     (string-match-p "in progress" txt)
                     (string-match-p "pending" txt)
                     ;; Leading icon is the dsh-web checklist icon (fallback "▤" in
                     ;; non-graphical Emacs), not the old "☑".
                     (string-match-p (regexp-quote "▤") txt)
                     (not (string-match-p (regexp-quote "☑") txt))
                     (not (string-match-p "tool-t1" txt))))))))

;; 101c: every todo_write renders a new row (like a tool card),
;; accumulating with the conversation, no overwriting
(ert-deftest dsh-emacs-test-render-todo-each-write-renders-new-row ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-todo-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "t1" "todo_write"
                                      "{\"todos\":[{\"content\":\"A\",\"status\":\"in_progress\"},{\"content\":\"B\",\"status\":\"pending\"}]}"))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 2 "t2" "todo_write"
                                      "{\"todos\":[{\"content\":\"A\",\"status\":\"completed\"},{\"content\":\"B\",\"status\":\"in_progress\"},{\"content\":\"C\",\"status\":\"pending\"}]}"))
    (let ((txt (buffer-string)))
      (ert-info ((format "%s" "todo-each-write-renders-new-row"))
        (should (and (dsh-emacs-ui-find-block dsh-emacs--todo-namespace "t1")
                     (dsh-emacs-ui-find-block dsh-emacs--todo-namespace "t2")
                     (string-match-p "1/3 completed" txt)
                     (string-match-p (regexp-quote "C") txt)
                     (string-match-p (regexp-quote "☑") txt)))))))

;; 101d: resetting the session clears the latest todo snapshot state
(ert-deftest dsh-emacs-test-render-todo-reset-clears-list ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "t1" "todo_write"
                                      "{\"todos\":[{\"content\":\"A\",\"status\":\"pending\"}]}"))
    (dsh-emacs-render--reset-tool-tracking)
    (ert-info ((format "%s" "todo-reset-clears-list"))
      (should (null dsh-emacs--todo-list)))))

;; 101e: a todo row can be collapsed/expanded (default collapsed: header
;; only, checklist hidden)
(ert-deftest dsh-emacs-test-render-todo-row-collapsed-by-default ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-todo-expand-by-default nil)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "t1" "todo_write"
                                      "{\"todos\":[{\"content\":\"Alpha\",\"status\":\"in_progress\"},{\"content\":\"Beta\",\"status\":\"pending\"}]}"))
    (let* ((b (dsh-emacs-ui-find-block dsh-emacs--todo-namespace "t1"))
           (blk (and b (buffer-substring-no-properties (car b) (cdr b)))))
      (ert-info ((format "%s" "todo-row-collapsed-by-default"))
        (should (and b (string-match-p "Todo" blk)
                     (not (string-match-p (regexp-quote "Alpha") (buffer-string))))))
      ;; Expand: the checklist appears (with status glyphs)
      (goto-char (car b))
      (dsh-emacs-ui-toggle-fragment)
      (let ((txt (buffer-string)))
        (ert-info ((format "%s" "todo-row-expands-on-toggle"))
          (should (and (string-match-p (regexp-quote "Alpha") txt)
                       (string-match-p (regexp-quote "☐") txt)))))
      ;; Collapse again: the checklist is hidden again
      (goto-char (car b))
      (dsh-emacs-ui-toggle-fragment)
      (ert-info ((format "%s" "todo-row-recollapses-on-toggle"))
        (should (not (string-match-p (regexp-quote "Alpha") (buffer-string))))))))

;; 101f: summary-only mode: show only counts/progress, hide checklist
;; details and the collapse toggle
(ert-deftest dsh-emacs-test-render-todo-summary-only-hides-details ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-todo-summary-only t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "t1" "todo_write"
                                      "{\"todos\":[{\"content\":\"Alpha\",\"status\":\"in_progress\"},{\"content\":\"Beta\",\"status\":\"pending\"},{\"content\":\"Gamma\",\"status\":\"completed\"}]}"))
    (let* ((b (dsh-emacs-ui-find-block dsh-emacs--todo-namespace "t1"))
           (blk (and b (buffer-substring-no-properties (car b) (cdr b)))))
      (ert-info ((format "%s" "todo-summary-only-hides-details"))
        (should (and b
                     (string-match-p "1/3 completed" (buffer-string))
                     (not (string-match-p (regexp-quote "Alpha") (buffer-string)))
                     (not (string-match-p (regexp-quote "Beta") (buffer-string)))
                     (not (string-match-p (regexp-quote "Gamma") (buffer-string))))))
      ;; Text segment (title) in green `dsh-emacs-todo-text-face' (not italic)
      (ert-info ((format "%s" "todo-row-text-green"))
        (should (and b
                     (let ((m (string-match "Todo" blk)))
                       (and m
                            (let ((f (get-text-property (+ (car b) m) 'face)))
                              (or (eq f 'dsh-emacs-todo-text-face)
                                  (memq 'dsh-emacs-todo-text-face
                                        (if (listp f) f (list f))))))))))
      ;; Leading icon in tool purple `dsh-emacs-tool-icon-face'
      (ert-info ((format "%s" "todo-icon-purple-face"))
        (should (and b
                     (let ((f (get-text-property (car b) 'face)))
                       (or (eq f 'dsh-emacs-tool-icon-face)
                           (memq 'dsh-emacs-tool-icon-face
                                 (if (listp f) f (list f))))))))
      ;; The collapse toggle should have no effect: repeated toggling must not
      ;; reveal the checklist
      (goto-char (car b))
      (dsh-emacs-ui-toggle-fragment)
      (dsh-emacs-ui-toggle-fragment)
      (ert-info ((format "%s" "todo-summary-only-no-toggle"))
        (should (not (string-match-p (regexp-quote "Alpha") (buffer-string))))))))

;; --- Test 121: model-only surface replacement copies do not enter the human
;; record ---
;; A surface event is either `append' (entered the transcript at its own log
;; position) or `{op:"replace"}' (shadows an existing range so the MODEL sees
;; the newer copy). Replacements are the wrong source for a human transcript:
;; dsh compaction checkpoints are `user/message' copies already skipped by the
;; source-kind filter, but a pruned `tool/result' shares its `callId' with the
;; record it shadows and has no source filter, so without this check the same
;; tool card is painted twice.
(ert-deftest dsh-emacs-test-render-render-replacement-predicate ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-replacement-predicate"))
    (should (dsh-protocol-replacement--from-alist
             '((type . "tool/result")
               (surfaceOp . ((op . "replace") (startSeq . 2) (endSeq . 2))))))
    (should (not (dsh-protocol-replacement--from-alist
                  '((type . "tool/result") (surfaceOp . "append")))))
    (should (not (dsh-protocol-replacement--from-alist '((type . "tool/result")))))))

(ert-deftest dsh-emacs-test-render-render-skips-replacement-tool-result ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-replacement*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq-local dsh-emacs-tool-expand-by-default t)
          (dsh-emacs-render-tool-call
           '(("type" . "tool/call") ("seq" . 1)
             ("data" . (("turn" . 1) ("step" . 1) ("callId" . "c-rep")
                        ("name" . "bash")
                        ("arguments" . "{\"command\":\"echo original\"}")))))
          (dsh-emacs-events--dispatch-event
           (current-buffer)
           (list (cons "type" "tool/result") (cons "seq" 2)
                 (cons "surfaceOp" (list (cons "op" "replace")
                                         (cons "startSeq" 2) (cons "endSeq" 2)))
                 (cons "data"
                       (list (cons "message"
                                   (list (cons "source" (list (cons "callId" "c-rep")))
                                         (cons "content"
                                               (vector (list (cons "type" "tool-result")
                                                             (cons "isError" :json-false)
                                                             (cons "exitCode" 0)
                                                             (cons "content"
                                                                   (vector (list (cons "type" "text")
                                                                                 (cons "text" "PRUNED-COPY")))))))))))))
          (ert-info ((format "%s" "render-skips-replacement-tool-result"))
            (should (not (string-search "PRUNED-COPY" (buffer-string))))
            (should (string-search "echo original" (buffer-string)))
            (should (= dsh-emacs--anchor-seq 2)))
          ;; Control: an append-origin result on another call still paints.
          (dsh-emacs-render-tool-call
           '(("type" . "tool/call") ("seq" . 3)
             ("data" . (("turn" . 1) ("step" . 1) ("callId" . "c-app")
                        ("name" . "bash")
                        ("arguments" . "{\"command\":\"echo second\"}")))))
          (dsh-emacs-events--dispatch-event
           (current-buffer)
           (list (cons "type" "tool/result") (cons "seq" 4)
                 (cons "surfaceOp" "append")
                 (cons "data"
                       (list (cons "message"
                                   (list (cons "source" (list (cons "callId" "c-app")))
                                         (cons "content"
                                               (vector (list (cons "type" "tool-result")
                                                             (cons "isError" :json-false)
                                                             (cons "exitCode" 0)
                                                             (cons "content"
                                                                   (vector (list (cons "type" "text")
                                                                                 (cons "text" "APPEND-COPY")))))))))))))
          (ert-info ((format "%s" "render-keeps-append-tool-result"))
            (should (string-search "APPEND-COPY" (buffer-string)))
            (should (= dsh-emacs--anchor-seq 4))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(provide 'dsh-test-render)
;;; dsh-test-render.el ends here

;;; dsh-test-execution.el --- Execution tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)

(ert-deftest dsh-emacs-test-execution-execution-decodes-string-wire-keys ()
  :tags '(dsh-unit)
  (let ((event (dsh-protocol-execution-event--from-alist
                '(("type" . "llm/retry") ("seq" . 10)
                  ("data" . (("retryId" . "chain") ("turn" . 1)
                             ("step" . 2) ("retry" . 3) ("maxRetries" . 5)
                             ("delayMs" . 1234) ("provider" . "test-provider")
                             ("failure" . (("code" . "rate-limit")
                                           ("message" . "Try later")))))))))
    (ert-info ((format "%s" "execution-decodes-string-wire-keys"))
      (should (equal (dsh-protocol-execution-event-id event) "chain"))
      (should (= (dsh-protocol-execution-event-attempt event) 3))
      (should (= (dsh-protocol-execution-event-limit event) 5))
      (should (= (dsh-protocol-execution-event-delay event) 1234))
      (should (equal (dsh-protocol-execution-event-code event) "rate-limit"))
      (should (equal (dsh-protocol-execution-event-message event) "Try later")))))

(ert-deftest dsh-emacs-test-execution-execution-retry ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dolist
        (case
         '(("wait" "llm/retry" 10
            ((retryId . "r") (turn . 1) (step . 1) (retry . 1)
             (maxRetries . 3) (delayMs . 2500) (provider . "provider-a")
             (failure . ((code . "rate-limit") (message . "Slow down"))))
            "Retry 1/3")
           ("started" "llm/retry-started" 11
            ((retryId . "r") (turn . 1) (step . 1) (retry . 1)) "Retrying 1/3")
           ("next-wait" "llm/retry" 12
            ((retryId . "r") (turn . 1) (step . 1) (retry . 2)
             (maxRetries . 3)) "Retry 2/3")
           ("old-attempt-start" "llm/retry-started" 13
            ((retryId . "r") (turn . 1) (step . 1) (retry . 1)) "Retry 2/3")
           ("other-chain-start" "llm/retry-started" 14
            ((retryId . "other") (turn . 1) (step . 1) (retry . 2)) "Retry 2/3")
           ("old-sequence" "llm/retry" 9
            ((retryId . "old") (turn . 1) (step . 1) (retry . 1)) "Retry 2/3")
           ("other-step-end" "step/end" 15 ((turn . 1) (step . 2)) "Retry 2/3")
           ("current-start" "llm/retry-started" 16
            ((retryId . "r") (turn . 1) (step . 1) (retry . 2)) "Retrying 2/3")
           ("step-end" "step/end" 17 ((turn . 1) (step . 1)) "")
           ("unlimited" "llm/retry" 18
            ((retryId . "unlimited") (turn . 1) (step . 2) (retry . 7)) "Retry 7")
           ("turn-cancelled" "turn/end" 19
            ((turn . 1) (reason . ((kind . "interrupted")))) "")
           ("step-chain" "llm/retry" 20
            ((retryId . "step-chain") (turn . 2) (step . 1) (retry . 1)
             (maxRetries . 2)) "Retry 1/2")
           ("other-step-start" "step/start" 21 ((turn . 2) (step . 2)) "")
           ("turn-chain" "llm/retry" 22
            ((retryId . "turn-chain") (turn . 2) (step . 2) (retry . 1)
             (maxRetries . 2)) "Retry 1/2")
           ("other-turn-start" "turn/start" 23 ((turn . 3)) "")))
      (pcase-let ((`(,name ,type ,seq ,data ,expected) case))
        (dsh-emacs-events--dispatch-event
         (current-buffer) (dsh-test--execution-event type seq data))
        (ert-info ((format "%s" (concat "execution-retry-" name)))
          (should (equal (string-trim (or (dsh-emacs-modeline--execution-indicator) ""))
                         expected)))
        (when (equal name "wait")
          (ert-info ((format "%s" "execution-retry-tooltip-explains-wait"))
            (should (string-match-p "provider-a" (dsh-emacs-modeline--status-detail)))
            (should (string-match-p "2500 ms" (dsh-emacs-modeline--status-detail)))
            (should (string-match-p "Slow down" (dsh-emacs-modeline--status-detail))))
          (save-window-excursion
            (dsh-emacs-describe-status)
            (with-current-buffer "*dsh status*"
              (ert-info ((format "%s" "execution-keyboard-details"))
                (should (string-match-p "rate-limit" (buffer-string)))
                (should (string-match-p "Slow down" (buffer-string)))))))))))

(ert-deftest dsh-emacs-test-execution-execution-compaction-without-running-turn ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/start" 1
                                '((compactionId . "manual") (turn . nil))))
    (ert-info ((format "%s" "execution-compaction-without-running-turn"))
      (should (not dsh-emacs--ml-busy))
      (should (string-match-p "\\bCompacting\\b" (dsh-emacs-modeline--ml-indicator))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "turn/end" 2 '((turn . 9))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/end" 3
                                '((compactionId . "other") (turn . nil))))
    (ert-info ((format "%s" "execution-compaction-matches-identity"))
      (should (string-match-p "\\bCompacting\\b" (dsh-emacs-modeline--ml-indicator))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "llm/retry" 4
                                '((retryId . "r") (retry . 1) (turn . 10)
                                  (step . 1) (maxRetries . 2))))
    (ert-info ((format "%s" "execution-compaction-and-retry-coexist"))
      (should (string-match-p "Compacting.*Retry 1/2"
                              (dsh-emacs-modeline--ml-indicator))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/end" 5
                                '((compactionId . "manual") (turn . nil))))
    (ert-info ((format "%s" "execution-compaction-end-keeps-retry"))
      (should (null dsh-emacs--modeline-compaction))
      (should (null dsh-emacs--modeline-compaction-start))
      (should (string-empty-p (dsh-emacs--ml-busy-indicator)))
      (should (equal (string-trim (dsh-emacs-modeline--ml-indicator)) "Retry 1/2")))
    (dsh-emacs-render-event
     (dsh-test--execution-event "assistant/message" 6
                                '((turn . 10) (step . 1)
                                  (message . ((role . "assistant")
                                              (content . []))) (stream . []))))
    (ert-info ((format "%s" "execution-success-clears-retry"))
      (should (string-empty-p (dsh-emacs-modeline--ml-indicator))))))

(ert-deftest dsh-emacs-test-execution-execution-turn-scoped-compaction-shows ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/start" 1
                                '((compactionId . "turn-scoped") (turn . 4))))
    (ert-info ((format "%s" "execution-turn-scoped-compaction-shows"))
      (should (string-match-p "\\bCompacting\\b" (dsh-emacs-modeline--ml-indicator))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "turn/end" 2 '((turn . 4))))
    (ert-info ((format "%s" "execution-turn-end-clears-same-turn-compaction"))
      (should (null dsh-emacs--modeline-compaction))
      (should (null dsh-emacs--modeline-compaction-start))
      (should (string-empty-p (dsh-emacs--ml-busy-indicator)))
      (should (string-empty-p (dsh-emacs-modeline--ml-indicator))))))

(ert-deftest dsh-emacs-test-execution-execution-compaction-failure-stays-inspectable ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/start" 1
                                '((compactionId . "auto") (turn . 1))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/end" 2
                                '((compactionId . "auto") (turn . 1)
                                  (error . "Summary provider unavailable"))))
    (ert-info ((format "%s" "execution-compaction-failure-stays-inspectable"))
      (should (null dsh-emacs--modeline-compaction))
      (should (string-match-p "Context compaction failed" (buffer-string)))
      (should (string-match-p "Summary provider unavailable" (buffer-string))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "command/run" 3
                                '((commandId . "cmd") (name . "compact"))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/start" 4
                                '((compactionId . "manual")
                                  (sourceCommandId . "cmd") (turn . nil))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "compaction/end" 5
                                '((compactionId . "manual")
                                  (sourceCommandId . "cmd") (turn . nil)
                                  (error . "Manual failure reason"))))
    (dsh-emacs-render-event
     (dsh-test--execution-event "command/done" 6
                                '((commandId . "cmd") (kind . "error")
                                  (text . "Manual failure reason"))))
    (goto-char (car (dsh-emacs-ui-find-block
                     (dsh-emacs-render--make-namespace) "cmd-cmd")))
    (dsh-emacs-ui-toggle-fragment)
    (ert-info ((format "%s" "execution-manual-failure-uses-command-card"))
      (should (null dsh-emacs--modeline-compaction))
      (should (= (how-many "Manual failure reason" (point-min) (point-max)) 1))
      (should (= (how-many "Context compaction failed" (point-min) (point-max)) 1)))))

(ert-deftest dsh-emacs-test-execution-execution-snapshot-folds-below-transcript-anchor ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs--buffer-session "execution-snapshot")
    (let* ((retry (dsh-test--execution-event
                   "llm/retry" 10
                   '((retryId . "reconnect") (turn . 1) (step . 2)
                     (retry . 3) (maxRetries . 5))))
           (compact (dsh-test--execution-event
                     "compaction/start" 11
                     '((compactionId . "c") (turn . 1))))
           (snapshot `((cursor . 11)
                       (records . [((type . "event") (event . ,retry))
                                   ((type . "event") (event . ,compact))]))))
      (setq dsh-emacs--anchor-seq 11)
      (dsh-emacs-events--follow-snapshot (current-buffer) snapshot)
      (ert-info ((format "%s" "execution-snapshot-folds-below-transcript-anchor"))
        (should (string-match-p "Compacting.*Retry 3/5"
                                (dsh-emacs-modeline--ml-indicator))))
      (let ((dsh-emacs--history-page t))
        ;; Drop the seq watermark so only the history-page guard can reject the
        ;; replayed record: an older page must never rewind the live status.
        (setq dsh-emacs--modeline-execution-seq nil)
        (dsh-emacs-render-history-events
         (list `((event . ,(dsh-test--execution-event
                            "compaction/end" 1
                            '((compactionId . "c") (turn . 1)))))) nil 10
         :follow-p nil))
      (ert-info ((format "%s" "execution-history-page-keeps-current-status"))
        (should (string-match-p "Compacting.*Retry 3/5"
                                (dsh-emacs-modeline--ml-indicator))))
      (dsh-emacs--ml-busy-clear)
      (ert-info ((format "%s" "execution-teardown-clears-feedback"))
        (should (null dsh-emacs--modeline-compaction))
        (should (null dsh-emacs--modeline-compaction-start))
        (should (string-empty-p (dsh-emacs--ml-busy-indicator)))
        (should (null (dsh-emacs-modeline--execution-indicator))))
      (let ((render (symbol-function 'dsh-emacs-render-history-events)))
        (cl-letf (((symbol-function 'dsh-emacs-render-history-events)
                   (lambda (&rest args)
                     (apply render args)
                     (dsh-emacs-events--dispatch-event
                      (current-buffer)
                      (dsh-test--execution-event "llm/retry-started" 12
                                                 '((retryId . "reconnect")
                                                   (turn . 1) (step . 2)
                                                   (retry . 3)))))))
          (dsh-emacs-events--follow-snapshot (current-buffer) snapshot)))
      (ert-info ((format "%s" "execution-snapshot-cannot-overwrite-newer-live-event"))
        (should (string-match-p "Compacting.*Retrying 3/5"
                                (dsh-emacs-modeline--ml-indicator))))
      (dsh-emacs-events--follow-snapshot
       (current-buffer)
       `((cursor . 13)
         (records . [((type . "event")
                      (event . ,(dsh-test--execution-event
                                 "turn/end" 13 '((turn . 1)))))])))
      (ert-info ((format "%s" "execution-closed-snapshot-is-idle"))
        (should (null dsh-emacs--modeline-compaction))
        (should (null dsh-emacs--modeline-compaction-start))
        (should (string-empty-p (dsh-emacs--ml-busy-indicator)))
        (should (null (dsh-emacs-modeline--execution-indicator))))
      (dsh-emacs-events--follow-snapshot (current-buffer) snapshot)
      (dsh-emacs-events--follow-snapshot
       (current-buffer) '((cursor . 14) (records . [])))
      (ert-info ((format "%s" "execution-missing-snapshot-evidence-clears-stale-status"))
        (should (null dsh-emacs--modeline-compaction))
        (should (null dsh-emacs--modeline-compaction-start))
        (should (string-empty-p (dsh-emacs--ml-busy-indicator)))
        (should (null (dsh-emacs-modeline--execution-indicator)))))))

(ert-deftest dsh-emacs-test-execution-execution-state-is-buffer-local ()
  :tags '(dsh-unit)
  (let ((first (generate-new-buffer " *execution-first*"))
        (second (generate-new-buffer " *execution-second*")))
    (unwind-protect
        (progn
          (with-current-buffer first
            (dsh-emacs-mode)
            (dsh-emacs-events--dispatch-event
             first (dsh-test--execution-event
                    "compaction/start" 1 '((compactionId . "c") (turn . nil)))))
          (with-current-buffer second
            (dsh-emacs-mode)
            (ert-info ((format "%s" "execution-state-is-buffer-local"))
              (should (null dsh-emacs--modeline-compaction))
              (should (null dsh-emacs--modeline-compaction-start))
              (should (string-empty-p (dsh-emacs--ml-busy-indicator)))
              (should (null (dsh-emacs-modeline--execution-indicator)))))
          (save-window-excursion
            (delete-other-windows)
            (let ((clicked (selected-window)))
              (set-window-buffer clicked first)
              (select-window (split-window-below))
              (switch-to-buffer second)
              (call-interactively
               #'dsh-emacs-describe-status nil
               (vector (list 'mouse-1 (list clicked 'mode-line '(0 . 0) 0))))
              (with-current-buffer "*dsh status*"
                (ert-info ((format "%s" "execution-click-uses-clicked-chat"))
                  (should (equal (buffer-string)
                                 "Compacting context (between turns)\n"))))))
          (with-current-buffer first
            (let ((process (make-pipe-process :name "execution-lost" :noquery t)))
              (unwind-protect
                  (progn
                    (setq dsh-emacs--event-process process)
                    (process-put process 'dsh-emacs-chat-buffer first)
                    (cl-letf (((symbol-function 'dsh-emacs-events--schedule-reconnect)
                               #'ignore))
                      (dsh-emacs-events--lost process))
                    (ert-info ((format "%s" "execution-socket-loss-clears-status-now"))
                      (should (null dsh-emacs--modeline-compaction))
                      (should (null dsh-emacs--modeline-compaction-start))
                      (should (string-empty-p (dsh-emacs--ml-busy-indicator)))
                      (should (null (dsh-emacs-modeline--execution-indicator)))))
                (delete-process process)))))
      (kill-buffer first)
      (kill-buffer second))))

(provide 'dsh-test-execution)
;;; dsh-test-execution.el ends here

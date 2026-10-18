;;; render-report.el --- Scoped render diagnostics -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "28.1"))
;; Usage: emacs -Q --batch -l scripts/render-report.el -f dsh-render-report-batch
;; This developer tool is not loaded by dsh-emacs.  Use interpreted sources:
;; primitive advice does not observe every byte/native-compiled instruction.

(add-to-list 'load-path
             (expand-file-name ".." (file-name-directory load-file-name)))
(require 'dsh-emacs)
(dolist (entry load-history)
  (when (and (stringp (car entry))
             (string-match-p "\\`dsh-emacs.*\\.el[cn]\\'"
                             (file-name-nondirectory (car entry))))
    (error "Render report requires interpreted dsh-emacs sources: %s"
           (car entry))))

;; Special even on older Emacs versions where trampolines do not exist.
(defvar comp-enable-subr-trampolines)
(defvar dsh-render-report--active nil)

(defun dsh-render-report-measure (function)
  "Call synchronous FUNCTION and report work on the current buffer as a plist.
No text content is retained.  :text-edits are chronological (START OLD NEW)
change-hook notifications, in coordinates at that change, not a final diff.
:property-calls are (SETTER START END PROPERTY); PROPERTY is nil for a plist.
Their summed extents include repeated and unchanged writes, not display damage.
String and scratch-buffer property calls are excluded.  Hooks suppressed by
FUNCTION and work deferred to a timer are not observed.
:build-ms times fragment string construction, or session render entry through
arrival of its prepared source at row reconciliation.  :other-ms includes
lookup, comparisons, writes and navigation; it is not pure publication time.
Timings include instrumentation overhead.  Errors propagate after cleanup.
Nested measurements are rejected."
  (when dsh-render-report--active (error "Render measurement already active"))
  (let* ((dsh-render-report--active t)
         (target (current-buffer))
         (hook-local (local-variable-p 'after-change-functions))
         (char-tick (buffer-chars-modified-tick))
         (tick (buffer-modified-tick))
         (last-char-tick char-tick)
         (renders 0) (rows 0) (row-builds 0) (flushes 0)
         (generated-lines 0) (generated-chars 0)
         (build-ms 0.0) session-start edits properties advice-list
         ;; Avoid native trampoline compilation in a batch developer tool.
         (comp-enable-subr-trampolines nil)
         (after-change
          (lambda (start end old-length)
            (when (eq (current-buffer) target)
              (let ((now (buffer-chars-modified-tick)))
                (unless (= now last-char-tick)
                  (push (list start old-length (- end start)) edits))
                (setq last-char-tick now)))))
         (start (float-time)))
    (unwind-protect
        (progn
          (add-hook 'after-change-functions after-change nil t)
          (dolist (symbol '(dsh-emacs-ui--render-fragment
                            dsh-emacs-session--render
                            dsh-emacs-session--render-session
                            dsh-emacs-session--pad-right
                            dsh-emacs-session--update-rows
                            dsh-emacs-render--flush-stream
                            put-text-property set-text-properties
                            add-text-properties remove-text-properties))
            (let ((wrapper
                   (lambda (original &rest args)
                     (pcase symbol
                       ('dsh-emacs-ui--render-fragment
                        (if (not (eq (current-buffer) target))
                            (apply original args)
                          (let* ((began (float-time))
                                 (text (apply original args)))
                            (cl-incf renders)
                            (cl-incf build-ms (* 1000 (- (float-time) began)))
                            (cl-incf generated-chars (length text))
                            (cl-incf generated-lines (cl-count ?\n text))
                            text)))
                       ('dsh-emacs-session--render
                        (when (eq (current-buffer) target)
                          (cl-incf renders)
                          (setq session-start (float-time)))
                        (apply original args))
                       ('dsh-emacs-session--render-session
                        (when session-start (cl-incf rows))
                        (apply original args))
                       ('dsh-emacs-session--pad-right
                        ;; One title layout per newly constructed visual row.
                        (when session-start (cl-incf row-builds))
                        (apply original args))
                       ('dsh-emacs-session--update-rows
                        (when (eq (current-buffer) target)
                          (when session-start
                            (cl-incf build-ms
                                     (* 1000 (- (float-time) session-start)))
                            (setq session-start nil))
                          (with-current-buffer (car args)
                            (cl-incf generated-chars (buffer-size))
                            (cl-incf generated-lines
                                     (count-lines (point-min) (point-max)))))
                        (apply original args))
                       ('dsh-emacs-render--flush-stream
                        (when (eq (or (car args) (current-buffer)) target)
                          (cl-incf flushes))
                        (apply original args))
                       (_
                        (let ((object (nth (if (eq symbol 'put-text-property)
                                               4 3) args))
                              (start (car args))
                              (end (cadr args)))
                          (when (eq (or object (current-buffer)) target)
                            ;; Later edits or cleanup may move/detach markers.
                            (push (list symbol
                                        (if (markerp start)
                                            (marker-position start) start)
                                        (if (markerp end)
                                            (marker-position end) end)
                                        (when (eq symbol 'put-text-property)
                                          (nth 2 args)))
                                  properties)))
                        (apply original args))))))
              (push (cons symbol wrapper) advice-list)
              (advice-add symbol :around wrapper)))
          (setq start (float-time))
          (save-current-buffer (funcall function))
          (let ((elapsed (* 1000 (- (float-time) start))))
            (list :renders renders :session-rows rows :session-row-builds row-builds
                  :stream-flushes flushes
                  :generated-lines generated-lines :generated-chars generated-chars
                  :text-edits (nreverse edits)
                  :property-calls (nreverse properties)
                  :text-changed (/= char-tick (buffer-chars-modified-tick))
                  :modified (/= tick (buffer-modified-tick))
                  :build-ms build-ms :other-ms (- elapsed build-ms)
                  :elapsed-ms elapsed)))
      (dolist (entry advice-list)
        (advice-remove (car entry) (cdr entry)))
      (when (buffer-live-p target)
        (with-current-buffer target
          (remove-hook 'after-change-functions after-change t)
          ;; Do not leave a new local binding, or remove hooks the measured
          ;; operation itself installed (e.g. a new fragment's cache hook).
          (when (and (not hook-local) (equal after-change-functions '(t)))
            (kill-local-variable 'after-change-functions)))))))

(defun dsh-render-report-scenario (scenario measure)
  "Run one fresh synthetic SCENARIO through MEASURE, a function of a thunk.
Setup is excluded.  No server is contacted and no live chat is modified."
  (with-temp-buffer
    (if (eq scenario 'session-title)
        (let ((dsh-emacs--sessions
               (cl-loop for i below 540 collect
                        (dsh-protocol-session--from-alist
                         `((sessionId . ,(format "report-%d" i))
                           (projections (values (title . "Title A")))))))
              (dsh-emacs--workspaces nil)
              (dsh-emacs--archived-sessions nil)
              (dsh-emacs--current-session nil)
              (dsh-emacs--subagent-catalogs (make-hash-table :test 'equal)))
          (dsh-emacs-session--render)
          (setcar dsh-emacs--sessions
                  (dsh-protocol-session--from-alist
                   '((sessionId . "report-0")
                     (projections (values (title . "Title B"))))))
          (funcall measure #'dsh-emacs-session--render))
      (let* ((model (dsh-emacs-ui-make-fragment
                     :namespace-id "report" :block-id "card" :style 'minimal
                     :label-left "Title A"
                     :body (apply #'concat (make-list 5000 "body line\n"))))
             (update (lambda () (dsh-emacs-ui-update-fragment model))))
        (dsh-emacs-ui-update-fragment model :expanded t)
        (pcase scenario
          ('fragment-title (setf (alist-get :label-left model) "Title B"))
          ((or 'fragment-after-stream 'fragment-rewarmed)
           ;; Flush a real pending plain-text delta outside the card.  Exclude
           ;; that write from the unchanged-card report, as well as setup.
           (goto-char (point-max))
           (let ((inhibit-read-only t)) (insert "\nstream: "))
           (let ((dsh-emacs--streaming-assistant
                  (list :end (copy-marker (point) t)
                        :pending '("delta") :event-id "report-stream")))
             (unwind-protect
                 (dsh-emacs-render--flush-stream)
               (set-marker (plist-get dsh-emacs--streaming-assistant :end) nil)))
           (when (eq scenario 'fragment-rewarmed) (funcall update)))
          ('fragment-warm nil)
          (_ (error "Unknown render scenario: %S" scenario)))
        (funcall measure update)))))

(defun dsh-render-report-batch ()
  "Print work counts and five uninstrumented timing samples per scenario.
GC is forced before each timed update and otherwise included in its time.
Fixtures are rebuilt and warmed separately for every sample."
  (princ (format "Emacs %s; %s; interpreted batch sources\n"
                 emacs-version system-type))
  (dolist (scenario '(session-title fragment-title fragment-warm
                     fragment-after-stream fragment-rewarmed))
    (let* ((report (dsh-render-report-scenario
                    scenario #'dsh-render-report-measure))
           (calls (plist-get report :property-calls))
           (samples
            (cl-loop repeat 5 collect
                     (dsh-render-report-scenario
                      scenario
                      (lambda (run)
                        (garbage-collect)
                        (let ((start (float-time)))
                          (funcall run)
                          (* 1000 (- (float-time) start))))))))
      ;; Keep the batch report compact; the callable API retains every range.
      (setq report (copy-sequence report))
      (setq report (plist-put report :property-calls (length calls)))
      (setq report (plist-put report :property-span
                              (cl-loop for call in calls
                                       sum (- (nth 2 call) (nth 1 call)))))
      (princ (format "%s\n  %S\n  samples-ms: %S; median-ms: %.3f\n"
                     scenario report samples
                     (nth 2 (sort (copy-sequence samples) #'<)))))))

(provide 'dsh-render-report)
;;; render-report.el ends here

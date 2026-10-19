;;; dsh-emacs-history.el --- Browse the chat transcript -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026
;; Author: dsh-emacs contributors
;; URL: https://github.com/vritser/dsh-emacs
;; Version: 0.6.1
;; License: GPL-3.0-or-later
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:

;; Older-page loading and navigation share the rendered transcript.  Reading
;; positions belong to windows; pagination belongs to the session buffer.

;;; Code:

(require 'cl-lib)
(require 'dsh-emacs-server)
(require 'dsh-emacs-render)

(defvar dsh-emacs--buffer-session)
(defvar dsh-emacs--buffer-subagent)
(defvar dsh-emacs--input-marker)
(defvar dsh-emacs-history-window)
(declare-function dsh-emacs--seed-input-history "dsh-emacs"
                  (events session-id &optional older))
(declare-function dsh-emacs--active-session-id "dsh-emacs" ())

(defun dsh-emacs-imenu-create-user-index ()
  "Build an Imenu index of loaded user questions.
Targets are advancing markers so a menu opened before an older page lands
still jumps to the original question.  Labels include line numbers to
identify repeated questions."
  (let (index)
    (save-excursion
      (goto-char (point-min))
      (while (< (point) (point-max))
        (when (get-text-property (point) 'dsh-emacs-user-message)
          (let* ((raw (buffer-substring-no-properties
                       (point) (line-end-position)))
                 (content (if (string-prefix-p "❯ " raw)
                              (substring raw 2) raw))
                 (preview (if (> (length content) 60)
                              (concat (substring content 0 57) "...")
                            content)))
            (push (cons (format "%d: %s" (line-number-at-pos) preview)
                        (copy-marker (point) t))
                  index)))
        (goto-char (next-single-property-change
                    (point) 'dsh-emacs-user-message nil (point-max)))))
    (nreverse index)))

(defun dsh-emacs-goto-latest ()
  "Return this window to the draft and resume following new output.
Other windows keep their reading positions; the draft is left untouched."
  (interactive)
  (unless (and (markerp dsh-emacs--input-marker)
               (marker-buffer dsh-emacs--input-marker))
    (user-error "This buffer has no chat input"))
  (goto-char (point-max))
  (recenter -1))

(defcustom dsh-emacs-history-rounds 3
  "Number of complete earlier rounds fetched by `dsh-emacs-load-older-history'.
A partially visible oldest round counts as the first round to complete.
A prefix argument overrides this value for one load."
  :type 'natnum
  :group 'dsh-emacs)

(defvar-local dsh-emacs--history-loading nil
  "Current round-loading request plist, or nil.
Its `:token' cons distinguishes late callbacks from canceled or superseded
loads, so mutating the request plist in place cannot make an in-flight
response look current.")

(defun dsh-emacs--history-load-active-p (request)
  "Return non-nil while REQUEST is this buffer's current round load."
  (eq (plist-get request :token)
      (plist-get dsh-emacs--history-loading :token)))

(defun dsh-emacs--load-older-history-page (buffer page-value)
  "Prepend one older history page, described by PAGE-VALUE, to BUFFER.
Runs as the `session/page' callback: renders the page above the currently
loaded transcript, keeps the loaded window viewport in place, extends the
pagination frontier, and seeds `M-p' recall from the page's user messages."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq dsh-emacs--history-loading nil)
      (let* ((page (dsh-protocol--struct #'dsh-protocol-history-page-p
                                         #'dsh-protocol-history-page--from-alist
                                         page-value))
             (entries (dsh-protocol-history-page-records page))
             (rendered 0)
             (cursor (dsh-protocol-history-page-oldest page)))
        (when (and entries (integerp cursor))
          ;; The prepend marker must exist before the first render: every
          ;; renderer resolves its insertion position through it.  The page
          ;; sits below the live frontier, and the renderer leaves
          ;; `dsh-emacs--anchor-seq' alone for a prepend, so a live frame
          ;; cannot replay the loaded page.
          (setq dsh-emacs--history-insert-marker
                (dsh-emacs-render--history-prepend-marker))
          (let ((saved-point (copy-marker (point) t))
                (views (cl-loop
                        for window in (get-buffer-window-list buffer nil t)
                        collect (list window
                                      (copy-marker (window-start window) t)
                                      (copy-marker (window-point window) t)
                                      (window-vscroll window t)
                                      (window-hscroll window)))))
            (unwind-protect
                ;; Bind the page flag around the render: it is what tells the
                ;; renderers this batch is settled history (the insertion
                ;; marker is positional and may legitimately be nil).
                (let ((dsh-emacs--history-page t)
                      (dsh-emacs-ui--following-windows-function #'ignore))
                  (setq rendered
                        (dsh-emacs-render-history-events
                         entries nil dsh-emacs--history-earliest-seq
                         :insert-before
                         (and dsh-emacs--history-insert-marker
                              (marker-position dsh-emacs--history-insert-marker))
                         :follow-p nil)))
              ;; Insertion-type t keeps the old text even when a window starts
              ;; exactly at the prepend boundary.  Restore only views of this
              ;; buffer, without restoring the user's whole window layout.
              (goto-char saved-point)
              (set-marker saved-point nil)
              (pcase-dolist (`(,window ,start ,point ,vscroll ,hscroll) views)
                (when (and (window-live-p window)
                           (eq (window-buffer window) buffer))
                  (set-window-point window point)
                  (set-window-start window start t)
                  (set-window-vscroll window vscroll t)
                  (set-window-hscroll window hscroll))
                (set-marker start nil)
                (set-marker point nil))
              (when (markerp dsh-emacs--history-insert-marker)
                (set-marker dsh-emacs--history-insert-marker nil))
              (setq dsh-emacs--history-insert-marker nil))))
        (if (and entries (integerp cursor))
            (progn
              (setq dsh-emacs--history-earliest-seq cursor)
              (setq dsh-emacs--history-has-more
                    (dsh-protocol-history-page-has-more page))
              (dsh-emacs--seed-input-history
               entries (or dsh-emacs--buffer-session
                           (dsh-emacs--active-session-id)) t)
              (let ((rounds (dsh-protocol-history-page-rounds page)))
                (message "%s%s"
                         (if rounds
                             (format "Loaded rounds %d–%d (%d round%s)"
                                     (caar rounds) (car (car (last rounds)))
                                     (length rounds) (if (= (length rounds) 1) "" "s"))
                           (format "Loaded %d history events (no round boundaries)"
                                   rendered))
                         (if dsh-emacs--history-has-more
                             "; C-c C-o loads earlier rounds"
                           "; beginning of history"))))
          (setq dsh-emacs--history-has-more nil)
          (message "No older messages remain"))))))

(defun dsh-emacs-history--fetch-rounds (buffer request)
  "Continue REQUEST until its complete rounds are available in BUFFER.
Stage records without changing the transcript or its pagination cursor;
failed, canceled and superseded requests can therefore be retried safely."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (dsh-emacs--history-load-active-p request)
        (message "Loading older rounds… %d/%d rounds ready; C-c C-o cancels"
                 (length (plist-get request :rounds)) (plist-get request :target))
        (condition-case err
            (dsh-emacs--rpc-async
             "session/page"
             (dsh-protocol-history-page-request
              (plist-get request :session) (plist-get request :address)
              (plist-get request :through) (plist-get request :before)
              (plist-get request :limit)
              (- (plist-get request :target) (length (plist-get request :rounds))))
             (lambda (ok value)
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (when (dsh-emacs--history-load-active-p request)
                     (condition-case err
                         (progn
                           (unless (and ok (listp value))
                             (error "History request failed: %S" value))
                           (unless (and (equal dsh-emacs--buffer-session
                                               (plist-get request :session))
                                        (equal dsh-emacs--buffer-subagent
                                               (plist-get request :address))
                                        (equal dsh-emacs--history-earliest-seq
                                               (plist-get request :frontier)))
                             (error "History changed while loading; retry from the current view"))
                           (let* ((page (dsh-protocol-history-page--from-alist value))
                                  (records (dsh-protocol-history-page-records page))
                                  (oldest (dsh-protocol-history-page-oldest page))
                                  (more (dsh-protocol-history-page-has-more page))
                                  (rounds (append (dsh-protocol-history-page-rounds page)
                                                  (plist-get request :rounds)))
                                  (all (append records (plist-get request :records)))
                                  (target (plist-get request :target)))
                             (when (or (and more (null records))
                                       (and oldest
                                            (>= (dsh-protocol-history-page-newest page)
                                                (plist-get request :before))))
                               (error "History page did not move backwards"))
                             (setf (plist-get request :records) all
                                   (plist-get request :rounds) rounds)
                             (if (and more (< (length rounds) target))
                                 (progn
                                   (setf (plist-get request :before) oldest)
                                   (dsh-emacs-history--fetch-rounds buffer request))
                               ;; The server's message budget can return an
                               ;; extra partial round.  Keep only the requested
                               ;; complete suffix, retaining its next-page cursor.
                               (when (>= (length rounds) target)
                                 (setq more (or more (> (length rounds) target))
                                       rounds (last rounds target)
                                       oldest (nth 1 (car rounds))
                                       all (memq (nth 2 (car rounds)) all)))
                               (let* ((window (plist-get request :window))
                                      (point (plist-get request :point))
                                      (visit (and (window-live-p window)
                                                  (eq window (selected-window))
                                                  (eq (window-buffer window) buffer)
                                                  (= (window-point window) point))))
                                 (dsh-emacs--load-older-history-page
                                  buffer (dsh-protocol--make-history-page
                                          :records all :oldest (or oldest
                                                                   (plist-get request :before))
                                          :has-more more :rounds rounds))
                                 (when (and visit all)
                                   (push-mark (marker-position point) t)
                                   (when-let* ((start (dsh-emacs-render--history-prepend-marker)))
                                     (goto-char start)
                                     (recenter 0)
                                     (set-marker start nil)))
                                 (set-marker point nil)))))
                       (error
                        (setq dsh-emacs--history-loading nil)
                        (set-marker (plist-get request :point) nil)
                        (message "Could not load rounds: %s" (error-message-string err)))))))))
          (error
           (setq dsh-emacs--history-loading nil)
           (set-marker (plist-get request :point) nil)
           (message "Could not load rounds: %s" (error-message-string err))))))))

(defun dsh-emacs-load-older-history (&optional rounds)
  "Load ROUNDS complete earlier rounds, default `dsh-emacs-history-rounds'.
With a prefix argument, use that many rounds.  A partial oldest round counts
as the first round to complete.  Long rounds are fetched in bounded batches;
the transcript changes only when the requested range or session start is
reached.  Invoke again while loading to cancel without moving the cursor.
The initiating window visits the newly loaded range if its point has not
moved during the request; other windows retain their reading positions."
  (interactive (list (and current-prefix-arg
                          (prefix-numeric-value current-prefix-arg))))
  (cond
   ((not (bound-and-true-p dsh-emacs--buffer-session))
    (user-error "Older history is only available inside a chat buffer"))
   (dsh-emacs--history-loading
    (set-marker (plist-get dsh-emacs--history-loading :point) nil)
    (setq dsh-emacs--history-loading nil)
    (message "History loading canceled; no rounds added"))
   ((not (and (boundp 'dsh-emacs--input-marker)
              (markerp dsh-emacs--input-marker)))
    (message "This chat buffer has no transcript to extend"))
   ((null dsh-emacs--history-earliest-seq)
    (message "No earlier history is known for this session yet"))
   ((not dsh-emacs--history-has-more)
    (message "No older rounds remain"))
   ((null dsh-emacs--history-cursor)
    (message "This session has no history cursor yet"))
   (t
    (let ((count (or rounds dsh-emacs-history-rounds)))
      (unless (and (integerp count) (> count 0))
        (user-error "Round count must be a positive integer"))
      (unless (and (integerp dsh-emacs-history-window) (> dsh-emacs-history-window 0))
        (user-error "History batch size must be a positive integer"))
      (setq dsh-emacs--history-loading
            (list :token (list 'dsh-emacs-history-load)
                  :target count :before dsh-emacs--history-earliest-seq
                  :frontier dsh-emacs--history-earliest-seq
                  :through dsh-emacs--history-cursor :session dsh-emacs--buffer-session
                  :address dsh-emacs--buffer-subagent :limit dsh-emacs-history-window
                  :point (copy-marker (point) t)
                  :window (get-buffer-window (current-buffer) t)
                  :records nil :rounds nil))
      (dsh-emacs-history--fetch-rounds (current-buffer) dsh-emacs--history-loading)))))

(provide 'dsh-emacs-history)
;;; dsh-emacs-history.el ends here

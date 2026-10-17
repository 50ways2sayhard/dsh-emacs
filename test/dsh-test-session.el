;;; dsh-test-session.el --- Session tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)

(defun dsh-test--goto-marker (marker)
  "Move the buffer point and the selected window's point onto MARKER's line.
A real GUI moves both together; tests that only `goto-char' would leave the
window's own point behind, which the session list now preserves per window."
  (goto-char (point-min))
  (search-forward marker)
  (beginning-of-line)
  (when (eq (window-buffer (selected-window)) (current-buffer))
    (set-window-point (selected-window) (point))))

(load (expand-file-name "scripts/render-report.el" dsh-emacs-test-root) nil t)

;; --- Test 10: session list functions exist ---
(ert-deftest dsh-emacs-test-session-session-render-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "session--render function exists"))
    (should (fboundp 'dsh-emacs-session--render))))

(ert-deftest dsh-emacs-test-session-session-shorten-cwd-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "session--shorten-cwd function exists"))
    (should (fboundp 'dsh-emacs-session--shorten-cwd))))

(ert-deftest dsh-emacs-test-session-open-session-at-point-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "open-session-at-point function exists"))
    (should (fboundp 'dsh-emacs-open-session-at-point))))

(ert-deftest dsh-emacs-test-session-session-cwd-is-absolute ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-default-cwd "~/"))
    (ert-info ((format "%s" "session-cwd-is-absolute"))
      (should (file-name-absolute-p (dsh-emacs--absolute-cwd nil))))))

(ert-deftest dsh-emacs-test-session-session-time-formats-milliseconds ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "session-time-formats-milliseconds"))
    (should (stringp (dsh-emacs-session--compact-time (* (float-time) 1000))))))

;; --- Test: session list time column alignment — padded by display width (CJK
;; takes 2 columns) ---
(ert-deftest dsh-emacs-test-session-session-pad-right-aligns-wide-characters ()
  :tags '(dsh-unit)
  (let* ((ascii (dsh-emacs-session--pad-right "hello" 45))
         (cjk (dsh-emacs-session--pad-right "自动摘要名称" 45))
         (trunc (dsh-emacs-session--pad-right
                 (make-string 60 ?x) 45)))
    (ert-info ((format "%s" "session-pad-right-aligns-wide-characters"))
      (should (and (= 45 (string-width ascii))
                   (= 45 (string-width cjk))
                   (= 45 (string-width trunc))
                   (not (equal ascii cjk)))))))

;; --- Test 51: session list workspace filtering ---
(ert-deftest dsh-emacs-test-session-session-filter-restricts-workspace ()
  :tags '(dsh-unit)
  (let* ((sessions (list (list (cons 'sessionId "s1") (cons 'updatedAt 100)
                               (cons 'projections
                                     (list (cons 'values (list (cons 'title "Alpha"))))))
                         (list (cons 'sessionId "s2") (cons 'updatedAt 200)
                               (cons 'projections
                                     (list (cons 'values (list (cons 'title "Beta"))))))
                         (list (cons 'sessionId "s3") (cons 'updatedAt 300)
                               (cons 'projections
                                     (list (cons 'values (list (cons 'title "Gamma"))))))))
         (workspaces (list (list (cons 'workspaceId "w1") (cons 'title "WS A")
                                 (cons 'sessionIds ["s1" "s2"]))))
         (sessions-s (dsh-emacs-test--session-items sessions))
         (workspaces-s (mapcar #'dsh-protocol-workspace--from-alist workspaces)))
    ;; Filter to w1: only WS A members remain, Ungrouped bucket suppressed
    ;; Note: the `filtered' initializer must be evaluated after the filter
    ;; binding exists, hence let* here (let evaluates initializers before
    ;; binding, reading the old value)
    (let* ((dsh-emacs--archived-sessions nil)
           (dsh-emacs-session--filter-ws-id "w1")
           (filtered (dsh-emacs-session--group-sessions sessions-s workspaces-s)))
      (ert-info ((format "%s" "session-filter-restricts-workspace"))
        (should (and (= 1 (length filtered))
                     (equal "WS A" (plist-get (car filtered) :label))
                     (= 2 (length (plist-get (car filtered) :sessions)))))))
    ;; No filter: both WS A and Ungrouped buckets present
    (let* ((dsh-emacs--archived-sessions nil)
           (dsh-emacs-session--filter-ws-id nil)
           (grouped (dsh-emacs-session--group-sessions sessions-s workspaces-s)))
      (ert-info ((format "%s" "session-group-keeps-ungrouped"))
        (should (and (= 2 (length grouped))
                     (cl-some (lambda (g) (equal "WS A" (plist-get g :label))) grouped)
                     (cl-some (lambda (g) (equal "Ungrouped" (plist-get g :label))) grouped)))))
    ;; Render level: while filtering, other workspaces / ungrouped
    ;; sessions are not visible
    (let ((buf (generate-new-buffer " *dsh-filter-render*")))
      (unwind-protect
          (with-current-buffer buf
            (let ((dsh-emacs--sessions sessions-s)
                  (dsh-emacs--workspaces workspaces-s)
                  (dsh-emacs--archived-sessions nil)
                  (dsh-emacs-session--filter-ws-id "w1")
                  (dsh-emacs-session--filter-ws-title "WS A"))
              (dsh-emacs-session--render)
              (let ((txt (buffer-substring-no-properties
                          (point-min) (point-max))))
                ;; Rows sorted by recency (Beta before Alpha); match the whole span
                ;; to avoid order dependence
                (ert-info ((format "%s" "session-filter-render-hides-other-sessions"))
                  (should (and (string-match-p "Filter: WS A" txt)
                               (string-match-p "Alpha" txt)
                               (string-match-p "Beta" txt)
                               (not (string-match-p "Gamma" txt))))))))
        (kill-buffer buf)))))

;; --- Test 51b: session list workspace collapse survives redraw ---
(ert-deftest dsh-emacs-test-session-workspace-fold-tab-keybinding ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "workspace-fold-tab-keybinding"))
    (should (eq (lookup-key dsh-emacs-session-mode-map (kbd "TAB"))
                #'dsh-emacs-session-toggle))))

(ert-deftest dsh-emacs-test-session-workspace-fold-keeps-header-focused ()
  :tags '(dsh-unit)
  (let* ((sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "s1") (cons 'updatedAt 100)
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title "Alpha")))))))))
         (workspaces (list (dsh-protocol-workspace--from-alist
                            (list (cons 'workspaceId "w1")
                                  (cons 'title "WS A")
                                  (cons 'sessionIds ["s1"])))))
         (buf (generate-new-buffer " *dsh-workspace-fold*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces workspaces)
                (dsh-emacs--archived-sessions nil))
            (dsh-emacs-session--render)
            (dsh-test--goto-marker "WS A")
            (dsh-emacs-session-toggle-workspace)
            (ert-info ((format "%s" "workspace-fold-keeps-header-focused"))
              (should (equal (dsh-emacs-workspace-id-at-point) "w1")))
            (let ((folded (buffer-substring-no-properties
                           (point-min) (point-max))))
              (ert-info ((format "%s" "workspace-fold-hides-session"))
                (should (and (string-match-p "▸ WS A  (1)" folded)
                             (not (string-match-p "Alpha" folded))))))
            (dsh-emacs-session--render)
            (let ((refreshed (buffer-substring-no-properties
                              (point-min) (point-max))))
              (ert-info ((format "%s" "workspace-fold-survives-render"))
                (should (and (string-match-p "▸ WS A  (1)" refreshed)
                             (not (string-match-p "Alpha" refreshed))))))
            (dsh-test--goto-marker "WS A")
            (dsh-emacs-open-session-at-point)
            (ert-info ((format "%s" "workspace-ret-expands"))
              (should (string-match-p "Alpha"
                                      (buffer-substring-no-properties
                                       (point-min) (point-max)))))))
      (kill-buffer buf))))

(ert-deftest dsh-emacs-test-session-ungrouped-fold-hides-session ()
  :tags '(dsh-unit)
  (let* ((sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "loose")
                                (cons 'updatedAt 100)
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title
                                                              "Loose")))))))))
         (buf (generate-new-buffer " *dsh-ungrouped-fold*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces nil)
                (dsh-emacs--archived-sessions nil))
            (dsh-emacs-session--render)
            (goto-char (point-min))
            (search-forward "Ungrouped")
            (beginning-of-line)
            (dsh-emacs-session-toggle-workspace)
            (let ((folded (buffer-substring-no-properties
                           (point-min) (point-max))))
              (ert-info ((format "%s" "ungrouped-fold-hides-session"))
                (should (and (string-match-p "▸ Ungrouped  (1)" folded)
                             (not (string-match-p "Loose" folded))))))))
      (kill-buffer buf))))

;; --- Test 51c: opening the list auto-jumps to the active session ---
;; Two sessions in one workspace: "active" is the older one, so a plain
;; render parks point on "other" (newest first).  Only the pending
;; `dsh-emacs-session--auto-jump-session' target moves it.
(ert-deftest dsh-emacs-test-session-session-row-pos-absent-session ()
  :tags '(dsh-unit)
  (let* ((sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "other") (cons 'updatedAt 200)
                                (cons 'cwd "/tmp/ws-a")
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title "Other"))))))
                          (list (cons 'sessionId "active") (cons 'updatedAt 100)
                                (cons 'cwd "/tmp/ws-a")
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title
                                                              "Active")))))))))
         (workspaces (list (dsh-protocol-workspace--from-alist
                            (list (cons 'workspaceId "w1")
                                  (cons 'title "WS A")
                                  (cons 'sessionIds ["other" "active"])))))
         (buf (generate-new-buffer " *dsh-auto-jump*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces workspaces)
                (dsh-emacs--archived-sessions nil))
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "session-row-pos-absent-session"))
              (should (null (dsh-emacs-session--row-pos 'dsh-emacs-session-id "nope"))))
            (ert-info ((format "%s" "session-row-pos-picks-row"))
              (should (equal "other"
                             (get-text-property
                              (dsh-emacs-session--row-pos 'dsh-emacs-session-id "other")
                              'dsh-emacs-session-id))))
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "session-render-parks-on-newest"))
              (should (equal "other" (dsh-emacs-session-id-at-point))))
            (setq dsh-emacs-session--auto-jump-session "active")
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "auto-jump-lands-on-target"))
              (should (equal "active" (dsh-emacs-session-id-at-point))))
            (ert-info ((format "%s" "auto-jump-target-cleared"))
              (should (null dsh-emacs-session--auto-jump-session)))
            ;; A pending target outranks the active `w' workspace filter.
            (setq dsh-emacs-session--filter-ws-id "w1"
                  dsh-emacs-session--filter-ws-title "WS A"
                  dsh-emacs-session--auto-jump-session "active")
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "auto-jump-clears-hiding-filter"))
              (should (and (null dsh-emacs-session--filter-ws-id)
                           (equal "active" (dsh-emacs-session-id-at-point)))))))
      (kill-buffer buf))))

;; --- Test 51d: a target inside a folded group expands just that group ---
(ert-deftest dsh-emacs-test-session-auto-jump-fold-hides-rows ()
  :tags '(dsh-unit)
  (let* ((sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "a1") (cons 'updatedAt 100)
                                (cons 'cwd "/tmp/ws-a")
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title "A1"))))))
                          (list (cons 'sessionId "b1") (cons 'updatedAt 100)
                                (cons 'cwd "/tmp/ws-b")
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title
                                                              "B1")))))))))
         (workspaces (list (dsh-protocol-workspace--from-alist
                            (list (cons 'workspaceId "w1")
                                  (cons 'title "WS A")
                                  (cons 'sessionIds ["a1"])))
                           (dsh-protocol-workspace--from-alist
                            (list (cons 'workspaceId "w2")
                                  (cons 'title "WS B")
                                  (cons 'sessionIds ["b1"])))))
         (buf (generate-new-buffer " *dsh-auto-jump-fold*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces workspaces)
                (dsh-emacs--archived-sessions nil))
            (dsh-emacs-session--render)
            (dsh-emacs-collapse-workspaces)
            (ert-info ((format "%s" "auto-jump-fold-hides-rows"))
              (should (not (string-match-p
                            "A1" (buffer-substring-no-properties (point-min) (point-max))))))
            (setq dsh-emacs-session--auto-jump-session "a1")
            (dsh-emacs-session--render)
            (let ((text (buffer-substring-no-properties (point-min) (point-max))))
              (ert-info ((format "%s" "auto-jump-expands-target-group"))
                (should (equal "a1" (dsh-emacs-session-id-at-point)))
                (should (string-match-p "A1" text))
                (should (not (string-match-p "B1" text)))
                (should (null dsh-emacs-session--auto-jump-session))))))
      (kill-buffer buf))))

;; --- Test 51e: each window showing the list keeps its own row ---
;; A render erases the buffer, which clamps every window's point to the
;; start; the row each window was on has to be captured and put back, not
;; just the current buffer's point.
(ert-deftest dsh-emacs-test-session-window-row-survives-render ()
  :tags '(dsh-unit)
  (let* ((sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "s1") (cons 'updatedAt 300)
                                (cons 'cwd "/tmp/ws-a")
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title "One"))))))
                          (list (cons 'sessionId "s2") (cons 'updatedAt 200)
                                (cons 'cwd "/tmp/ws-a")
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title "Two"))))))
                          (list (cons 'sessionId "s3") (cons 'updatedAt 100)
                                (cons 'cwd "/tmp/ws-a")
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title
                                                              "Three")))))))))
         (workspaces (list (dsh-protocol-workspace--from-alist
                            (list (cons 'workspaceId "w1")
                                  (cons 'title "WS A")
                                  (cons 'sessionIds ["s1" "s2" "s3"])))))
         (buf (generate-new-buffer " *dsh-window-rows*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces workspaces)
                (dsh-emacs--archived-sessions nil))
            (dsh-emacs-session--render)
            ;; Show the list in a window: `set-window-point' is a no-op on a
            ;; window that displays some other buffer.
            (set-window-buffer (selected-window) (current-buffer))
            (dsh-emacs-session--render)
            ;; the selected window's own point, as the focused window's would be
            (set-window-point (selected-window)
                              (dsh-emacs-session--row-pos 'dsh-emacs-session-id
                                                          "s3"))
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "window-row-survives-render"))
              (should (equal "s3"
                             (get-text-property (window-point (selected-window))
                                                'dsh-emacs-session-id))))
            ;; a window parked on a group header comes back to that header
            (set-window-point (selected-window)
                              (or (dsh-emacs-session--row-pos
                                   'dsh-emacs-workspace-group-id "w1")
                                  (point-min)))
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "window-header-row-survives-render"))
              (should (equal "w1"
                             (get-text-property (window-point (selected-window))
                                                'dsh-emacs-workspace-group-id))))
            ;; a row that is gone (collapsed group) leaves the window at the top
            (set-window-point (selected-window)
                              (dsh-emacs-session--row-pos 'dsh-emacs-session-id
                                                          "s3"))
            (setq dsh-emacs-session--workspace-fold-overrides '(("w1" . t)))
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "window-row-gone-falls-back-to-top"))
              (should (equal "w1"
                             (get-text-property (window-point (selected-window))
                                                'dsh-emacs-workspace-group-id))))))
      (kill-buffer buf))))

;; --- Test 51f: a refresh keeps the scroll position (no visible re-flow) ---
;; The window point may sit outside the viewport; the viewport itself must
;; come back exactly where it was, or every background refresh scrolls the
;; list under the user.
(ert-deftest dsh-emacs-test-session-refresh-keeps-scroll-position ()
  :tags '(dsh-unit)
  (let* ((sessions (dsh-emacs-test--session-items
                    (cl-loop for i from 1 to 60
                             collect (list (cons 'sessionId (format "s%02d" i))
                                           (cons 'updatedAt (+ 1000 i))
                                           (cons 'cwd "/tmp/ws-a")
                                           (cons 'projections
                                                 (list (cons 'values
                                                             (list (cons 'title
                                                                         (format "T%02d"
                                                                                 i))))))))))
         (workspaces (list (dsh-protocol-workspace--from-alist
                            (list (cons 'workspaceId "w1")
                                  (cons 'title "WS A")
                                  (cons 'sessionIds
                                        (vconcat (cl-loop for i from 1 to 60
                                                          collect (format "s%02d" i))))))))
         (buf (generate-new-buffer " *dsh-scroll-keep*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces workspaces)
                (dsh-emacs--archived-sessions nil))
            (dsh-emacs-session-mode)
            (set-window-buffer (selected-window) (current-buffer))
            (dsh-emacs-session--render)
            (let ((p10 (dsh-emacs-session--row-pos 'dsh-emacs-session-id "s10"))
                  (p45 (dsh-emacs-session--row-pos 'dsh-emacs-session-id "s45")))
              ;; NOFORCE: redisplay may adjust this start to keep point visible.
              ;; Batch checks only the requested start, before any redisplay.
              (set-window-point (selected-window) p10)
              (set-window-start (selected-window) p45 t)
              (let ((before-start (window-start (selected-window)))
                    (before-row
                     (get-text-property (window-start (selected-window))
                                        'dsh-emacs-row-id)))
                (dsh-emacs-session--render)
                (ert-info ((format "%s" "refresh-keeps-scroll-position"))
                  (should (equal before-start (window-start (selected-window))))
                  (should (equal before-row
                                 (get-text-property (window-start (selected-window))
                                                    'dsh-emacs-row-id))))))))
      (kill-buffer buf))))

;; A reordered focus can leave the old viewport.  Forcing that viewport
;; makes GUI redisplay move point to its middle; a batch window does not
;; redisplay, so also check the NOFORCE contract at the Emacs boundary.
(ert-deftest dsh-emacs-test-session-session-reorder-preserves-point-over-forced-viewport ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--sessions
         (cl-loop for i below 70 collect
                  (dsh-protocol-session--from-alist
                   `((sessionId . ,(format "focus-%d" i))
                     (updatedAt . ,(- 1000 i))
                     (projections (values (title . ,(format "Focus %d" i))))))))
        (dsh-emacs--workspaces nil)
        (dsh-emacs--archived-sessions nil)
        (hl-line-overlay-buffer nil)
        (hl-line-sticky-flag nil))
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (cl-letf (((symbol-function 'dsh-emacs-events-host-connect) #'ignore))
          (dsh-emacs-session-mode))
        (goto-char (dsh-emacs-session--row-pos 'dsh-emacs-session-id "focus-55"))
        (set-window-start
         (selected-window)
         (dsh-emacs-session--row-pos 'dsh-emacs-session-id "focus-50") t)
        (hl-line-highlight)
        (let ((overlay hl-line-overlay)
              (window (overlay-get hl-line-overlay 'window))
              (set-start (symbol-function 'set-window-start))
              starts)
          (setf (dsh-protocol-session-updated-at (nth 55 dsh-emacs--sessions)) 2000)
          (cl-letf (((symbol-function 'set-window-start)
                     (lambda (win pos &optional noforce)
                       (push noforce starts)
                       (funcall set-start win pos noforce))))
            (dsh-emacs-session--render))
          (ert-info ((format "%s" "session-reorder-preserves-point-over-forced-viewport"))
            (should (equal (dsh-emacs-session-id-at-point) "focus-55"))
            (should (equal starts '(t))))
          (ert-info ((format "%s" "session-reorder-refreshes-existing-line-highlight"))
            (should (eq overlay hl-line-overlay))
            (should (= (overlay-start overlay) (line-beginning-position)))
            (should (= (overlay-end overlay) (line-beginning-position 2)))
            (should (eq (overlay-get overlay 'window) window))))))))

;; A partial first paint can already have the user's global line highlight.
;; Inserting later rows at its end stretches that second overlay until the
;; next command, even when the list's own local overlay has been corrected.
(ert-deftest dsh-emacs-test-session-session-first-load-keeps-both-highlights-on-one-row ()
  :tags '(dsh-unit)
  (let* ((sessions
          (cl-loop for i below 3 collect
                   (dsh-protocol-session--from-alist
                    `((sessionId . ,(format "initial-%d" i))
                      (updatedAt . ,(- 100 i))
                      (projections (values (title . ,(format "Initial %d" i))))))))
         (dsh-emacs--sessions (list (car sessions)))
         (dsh-emacs--workspaces nil)
         (dsh-emacs--archived-sessions nil)
         (global-hl-line-mode t)
         (global-hl-line-overlays nil)
         (global-hl-line-sticky-flag nil)
         (hl-line-overlay-buffer nil))
    (save-window-excursion
      (with-temp-buffer
        ;; Emacs 31 excludes space-prefixed internal buffers from global hl-line.
        (rename-buffer "*dsh-initial-highlight-test*" t)
        (switch-to-buffer (current-buffer))
        (cl-letf (((symbol-function 'dsh-emacs-events-host-connect) #'ignore)
                  ((symbol-function 'dsh-emacs-session--auto-refresh-start) #'ignore))
          (dsh-emacs-session-mode))
        (global-hl-line-highlight)
        (let ((overlay global-hl-line-overlay)
              (window (overlay-get global-hl-line-overlay 'window)))
          (setq dsh-emacs--sessions sessions)
          (dsh-emacs-session--render)
          (ert-info ((format "%s" "session-first-load-keeps-both-highlights-on-one-row"))
            (should (equal (dsh-emacs-session-id-at-point) "initial-0"))
            (should (eq overlay global-hl-line-overlay))
            (should (eq (overlay-get overlay 'window) window))
            (should (= (overlay-start overlay) (line-beginning-position)))
            (should (= (overlay-end overlay) (line-beginning-position 2)))
            (should (= (overlay-start hl-line-overlay) (line-beginning-position)))
            (should (= (overlay-end hl-line-overlay) (line-beginning-position 2)))))))))

;; Removing the focused row must not send every view to workspace one.
;; Include middle/end removals and a workspace with no session rows.
(ert-deftest dsh-emacs-test-session-removed-row-keeps-nearby-focus-case ()
  :tags '(dsh-unit)
  (dolist (scenario '(("b1" "b2" session)
                      ("c2" "c1" session)
                      ("empty" "wc" workspace)))
    (let* ((dsh-emacs--sessions
            (cl-loop for id in '("a1" "b1" "b2" "c1" "c2")
                     for time downfrom 100 collect
                     (dsh-protocol-session--from-alist
                      `((sessionId . ,id) (updatedAt . ,time)))))
           (dsh-emacs--workspaces
            (mapcar #'dsh-protocol-workspace--from-alist
                    '(((workspaceId . "wa") (title . "A") (sessionIds . ["a1"]))
                      ((workspaceId . "wb") (title . "B") (sessionIds . ["b1" "b2"]))
                      ((workspaceId . "empty") (title . "Empty") (sessionIds . []))
                      ((workspaceId . "wc") (title . "C") (sessionIds . ["c1" "c2"])))))
           (dsh-emacs--archived-sessions (make-hash-table :test #'equal))
           (removed (nth 0 scenario))
           (expected (nth 1 scenario)))
      (save-window-excursion
        (with-temp-buffer
          (switch-to-buffer (current-buffer))
          (cl-letf (((symbol-function 'dsh-emacs-events-host-connect) #'ignore))
            (dsh-emacs-session-mode))
          (setq-local dsh-emacs-session--workspace-fold-default nil)
          (dsh-emacs-session--render)
          (goto-char (dsh-emacs-session--row-pos 'dsh-emacs-row-id removed))
          (hl-line-highlight)
          (let ((other (split-window-below)))
            (set-window-point other
                              (dsh-emacs-session--row-pos 'dsh-emacs-row-id "b2"))
            (if (eq (nth 2 scenario) 'session)
                (puthash removed t dsh-emacs--archived-sessions)
              (setq dsh-emacs--workspaces
                    (cl-remove removed dsh-emacs--workspaces
                               :key #'dsh-protocol-workspace-workspace-id :test #'equal)))
            (dsh-emacs-session--render)
            (ert-info ((format "%s" (format "removed-row-keeps-nearby-focus-%s" removed)))
              (should (equal (get-text-property (point) 'dsh-emacs-row-id) expected))
              (should (equal (get-text-property (overlay-start hl-line-overlay)
                                                'dsh-emacs-row-id) expected))
              (should (equal (get-text-property (window-point other) 'dsh-emacs-row-id) "b2")))
            ;; A second projection/refresh must retain the fallback choice.
            (dsh-emacs-session--render)
            (ert-info ((format "%s" (format "removed-row-fallback-survives-refresh-%s" removed)))
              (should (equal (get-text-property (point) 'dsh-emacs-row-id) expected)))))))))

;; --- Test 51i: re-opening the list keeps the user's folded groups ---
;; Re-running the major mode on every open runs `kill-all-local-variables',
;; which wipes the buffer's fold overrides and workspace filter — a group the
;; user folded with TAB (or collapsed with `dsh-emacs-collapse-workspaces')
;; came back expanded on the next `C-c C-l'.
(ert-deftest dsh-emacs-test-session-reopen-keeps-folded-group ()
  :tags '(dsh-unit)
  (let ((dsh-emacs--current-session "s1")
        (dsh-emacs--archived-sessions nil))
    (unwind-protect
        (cl-letf (((symbol-function 'dsh-emacs-list-sessions) #'ignore)
                  ((symbol-function 'dsh-emacs--rpc-async)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dsh-emacs-events-host-connect) #'ignore)
                  ((symbol-function 'dsh-emacs-events-host-disconnect) #'ignore))
          (let ((dsh-emacs--sessions
                 (dsh-emacs-test--session-items
                  (list (list (cons 'sessionId "s1") (cons 'updatedAt 20)
                              (cons 'cwd "/tmp/ws-a")
                              (cons 'projections
                                    (list (cons 'values
                                                (list (cons 'title "One"))))))
                        (list (cons 'sessionId "s2") (cons 'updatedAt 10)
                              (cons 'cwd "/tmp/ws-b")
                              (cons 'projections
                                    (list (cons 'values
                                                (list (cons 'title
                                                            "Two")))))))))
                (dsh-emacs--workspaces
                 (list (dsh-protocol-workspace--from-alist
                        (list (cons 'workspaceId "w1")
                              (cons 'title "WS A")
                              (cons 'sessionIds ["s1"])))
                       (dsh-protocol-workspace--from-alist
                        (list (cons 'workspaceId "w2")
                              (cons 'title "WS B")
                              (cons 'sessionIds ["s2"]))))))
            (dsh-emacs-list-sessions-display)
            ;; the user folds WS B
            (with-current-buffer dsh-emacs-sessions-buffer
              (goto-char (point-min))
              (search-forward "WS B")
              (beginning-of-line)
              (dsh-emacs-session-toggle-workspace))
            ;; ... and re-opens the list
            (dsh-emacs-list-sessions-display)
            (ert-info ((format "%s" "reopen-keeps-folded-group"))
              (should (with-current-buffer dsh-emacs-sessions-buffer
                        (dsh-emacs-session--workspace-collapsed-p "w2"))))
            (ert-info ((format "%s" "reopen-keeps-folded-session-hidden"))
              (should (not (string-match-p
                            "Two"
                            (with-current-buffer dsh-emacs-sessions-buffer
                              (buffer-substring-no-properties (point-min)
                                                              (point-max)))))))))
      (when (get-buffer dsh-emacs-sessions-buffer)
        (kill-buffer dsh-emacs-sessions-buffer)))))

(ert-deftest dsh-emacs-test-session-workspace-fold-default-collapsed ()
  :tags '(dsh-unit)
  (let* ((sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "default-loose")
                                (cons 'updatedAt 100)
                                (cons 'projections
                                      (list (cons 'values
                                                  (list (cons 'title
                                                              "Default Loose")))))))))
         (buf (generate-new-buffer " *dsh-workspace-fold-default*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces nil)
                (dsh-emacs--archived-sessions nil)
                (dsh-emacs-workspaces-collapsed-by-default t))
            (dsh-emacs-session--render)
            (ert-info ((format "%s" "workspace-fold-default-collapsed"))
              (should (not (string-match-p
                            "Default Loose"
                            (buffer-substring-no-properties (point-min) (point-max))))))
            (dsh-emacs-expand-workspaces)
            (ert-info ((format "%s" "workspace-expand-workspaces-shows-session"))
              (should (string-match-p
                       "Default Loose"
                       (buffer-substring-no-properties (point-min) (point-max)))))
            (dsh-emacs-collapse-workspaces)
            (ert-info ((format "%s" "workspace-collapse-workspaces-hides-session"))
              (should (not (string-match-p
                            "Default Loose"
                            (buffer-substring-no-properties
                             (point-min) (point-max))))))))
      (kill-buffer buf))))

;; --- Test 60: subagent sessions do not enter a group ---
;; The server marks subagent sessions with origin: "subagent"; they
;; must not appear in the session list (including the Ungrouped bucket).
(ert-deftest dsh-emacs-test-session-subagent-session-hidden-from-list ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs--archived-sessions nil)
         (sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "s1")
                                (cons 'origin "subagent")
                                (cons 'updatedAt 100))
                          (list (cons 'sessionId "s2")
                                (cons 'updatedAt 200)))))
         (workspaces nil))
    ;; No workspace: subagent must be dropped, only s2 enters Ungrouped
    (let ((grouped (dsh-emacs-session--group-sessions sessions workspaces)))
      (let* ((ungrouped (cl-find-if (lambda (g) (equal "Ungrouped" (plist-get g :label))) grouped))
             (members (and ungrouped (plist-get ungrouped :sessions)))
             (ids (mapcar #'dsh-protocol-session-session-id members)))
        (ert-info ((format "%s" "subagent-session-hidden-from-list"))
          (should (and (= (length grouped) 1)
                       (equal ids '("s2")))))))))

;; --- Test 61: blank sessions keep only the current session ---
;; dsh web's sessionVisible rule: not subagent, not archived,
;; and (not blank or is current). The three Untitled (blank) ones
;; should be hidden, but the currently open blank one is kept.
(ert-deftest dsh-emacs-test-session-blank-hidden-except-current ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs--archived-sessions nil)
         (dsh-emacs--current-session "s-blank-open")
         (sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "s-a")
                                (cons 'blank :json-true)
                                (cons 'updatedAt 300))
                          (list (cons 'sessionId "s-blank-open")
                                (cons 'blank :json-true)
                                (cons 'updatedAt 200))
                          (list (cons 'sessionId "s-b")
                                (cons 'blank :json-false)
                                (cons 'updatedAt 100))))))
    (let* ((grouped (dsh-emacs-session--group-sessions sessions nil))
           (ungrouped (cl-find-if (lambda (g) (equal "Ungrouped"
                                                     (plist-get g :label)))
                                  grouped))
           (members (and ungrouped (plist-get ungrouped :sessions)))
           (ids (sort (mapcar #'dsh-protocol-session-session-id members)
                      #'string<)))
      ;; s-a (blank, not current) is hidden; s-blank-open (blank but
      ;; current) and s-b (not blank) are kept
      (ert-info ((format "%s" "blank-hidden-except-current"))
        (should (and (equal ids '("s-b" "s-blank-open"))
                     (not (member "s-a" ids))))))))

;; --- Test 62: an empty workspace stays visible and sessions can
;; be created from it ---
;; After blank filtering a workspace may have no members; an empty
;; group must still appear in the list (rendering the New Session
;; line), and `c' (dsh-emacs-new-session) on it should pass
;; workspaceId rather than cwd.
(ert-deftest dsh-emacs-test-session-empty-workspace-stays-visible ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs--archived-sessions nil)
         (dsh-emacs--current-session nil)
         (empty-ws (mapcar #'dsh-protocol-workspace--from-alist
                           (list (list (cons 'workspaceId "w-empty")
                                       (cons 'title "Empty WS")
                                       (cons 'path "/tmp/dsh-empty-ws")
                                       (cons 'sessionIds [])))))
         (sessions nil))
    ;; 1) Grouping: an empty workspace is still in the result
    (let* ((grouped (dsh-emacs-session--group-sessions sessions empty-ws))
           (ws-group (cl-find-if (lambda (g)
                                   (equal "w-empty"
                                          (plist-get g :workspace-id)))
                                 grouped)))
      (ert-info ((format "%s" "empty-workspace-stays-visible"))
        (should (and ws-group
                     (equal "Empty WS" (plist-get ws-group :label))
                     (null (plist-get ws-group :sessions))))))
    ;; 2) Rendering: the empty group shows the New Session line, and
    ;; that line carries the workspace-id property
    (let ((buf (generate-new-buffer " *dsh-empty-ws-render*")))
      (unwind-protect
          (with-current-buffer buf
            (let ((dsh-emacs--sessions sessions)
                  (dsh-emacs--workspaces empty-ws)
                  (dsh-emacs--archived-sessions nil)
                  (dsh-emacs-session--filter-ws-id nil)
                  (dsh-emacs-session--filter-ws-title nil))
              (dsh-emacs-session--render)
              (let ((txt (buffer-substring-no-properties
                          (point-min) (point-max))))
                ;; Locate the New Session line of the empty workspace and check
                ;; that it carries workspace-id
                (goto-char (point-min))
                (let ((found nil))
                  (while (and (not found)
                              (search-forward "New Session" nil t))
                    (when (dsh-emacs-workspace-id-at-point)
                      (setq found t))
                    (when (get-text-property (1- (point))
                                             'dsh-emacs-workspace-id)
                      (setq found t)))
                  (ert-info ((format "%s" "empty-workspace-renders-new-session"))
                    (should (and found (string-match-p "Empty WS" txt))))))))
        (kill-buffer buf)))
    ;; 3) new-session on a workspace line should pass workspaceId, and
    ;; the new session's default-directory immediately aligns with the
    ;; workspace path (magit et al. locate the project this way).
    (let ((calls nil)
          (draft nil)
          (buf (generate-new-buffer " *dsh-empty-ws-create*")))
      (unwind-protect
          (with-current-buffer buf
            (insert "  New Session\n")
            (put-text-property (point-min) (point-max)
                               'dsh-emacs-workspace-id "w-empty")
            (goto-char (point-min))
            (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                       (lambda (method params cb)
                         (push (list method params) calls)
                         (funcall cb t `((sessionId . ,(cdr (assq 'sessionId
                                                                  (cdr (assq 'request params)))))))))
                      ((symbol-function 'pop-to-buffer)
                       (lambda (buffer &rest _) buffer))
                      ((symbol-function 'dsh-emacs--activate-chat-buffer)
                       (lambda (sid buffer &optional _address)
                         (puthash sid buffer dsh-emacs--chat-buffers)
                         (with-current-buffer buffer
                           (setq-local dsh-emacs--buffer-session sid)
                           (dsh-emacs--chat-buffer-sync sid)
                           (dsh-emacs-mode))))
                      ((symbol-value 'dsh-emacs--current-buffer) buf)
                      (dsh-emacs--workspaces empty-ws))
              (setq draft (call-interactively #'dsh-emacs-new-session))
              (let* ((call (car calls))
                     (params (cadr call)))
                (ert-info ((format "%s" "new-session-in-workspace-uses-workspace-id"))
                  (should (and (string= "session/create" (car call))
                               (string= "w-empty"
                                        (cdr (assq 'workspaceId (cdr (assq 'request params)))))
                               (null (assq 'cwd (cdr (assq 'request params)))))))
                ;; The new session buffer's default-directory should be the workspace path
                (ert-info ((format "%s" "new-workspace-session-sets-default-directory"))
                  (should (or (null (cdr (assq 'workspaceId (cdr (assq 'request params)))))
                              (string-suffix-p "/tmp/dsh-empty-ws"
                                               (directory-file-name
                                                (buffer-local-value
                                                 'default-directory draft)))))))))
        (when (buffer-live-p draft) (kill-buffer draft))
        (kill-buffer buf)))))

;; --- Test 62b: redraw keeps the session line under point (no jump
;; back to top between events/refreshes) ---
(ert-deftest dsh-emacs-test-session-session-render-keeps-focused-row ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs--archived-sessions nil)
         (dsh-emacs--current-session nil)
         (dsh-emacs-session--filter-ws-id nil)
         (dsh-emacs-session--filter-ws-title nil)
         (sessions (dsh-emacs-test--session-items
                    (list (list (cons 'sessionId "s-one")
                                (cons 'blank :json-false)
                                (cons 'cwd "/tmp/x")
                                (cons 'updatedAt 300))
                          (list (cons 'sessionId "s-two")
                                (cons 'blank :json-false)
                                (cons 'cwd "/tmp/y")
                                (cons 'updatedAt 200))
                          (list (cons 'sessionId "s-three")
                                (cons 'blank :json-false)
                                (cons 'cwd "/tmp/z")
                                (cons 'updatedAt 100)))))
         (old-sessions dsh-emacs--sessions)
         (old-ws dsh-emacs--workspaces)
         (buf (generate-new-buffer " *dsh-sess-restore*")))
    (unwind-protect
        (with-current-buffer buf
          (let ((dsh-emacs--sessions sessions)
                (dsh-emacs--workspaces nil))
            (dsh-emacs-session--render)
            ;; Put point on the s-two line
            (goto-char (point-min))
            (catch 'found
              (while (not (eobp))
                (when (equal "s-two" (dsh-emacs-session-id-at-point))
                  (throw 'found t))
                (forward-line 1)))
            (let ((expect (dsh-emacs-session-id-at-point)))
              ;; After redraw point should still be on the same session line
              (dsh-emacs-session--render)
              (ert-info ((format "%s" "session-render-keeps-focused-row"))
                (should (equal expect (dsh-emacs-session-id-at-point)))))))
      (kill-buffer buf))
    (setq dsh-emacs--sessions old-sessions
          dsh-emacs--workspaces old-ws)))

;; --- Test 98p3: wire `false' booleans never read as running ---
;; `json-read' decodes JSON false as the truthy symbol `:json-false'.  Keeping
;; it in the session struct made `dsh-emacs--busy-p' report an IDLE session as
;; running, so every idle `C-c C-c' was routed to the queue path — the message
;; showed first as the blue Next Message preview and only then entered the
;; transcript, instead of the plain send's immediate transcript echo.
(ert-deftest dsh-emacs-test-session-session-wire-false-normalizes-to-nil ()
  :tags '(dsh-unit)
  (let* ((idle (dsh-protocol-session--from-alist
                '((sessionId . "s-idle") (running . :json-false)
                  (blank . :json-false))))
         (busy (dsh-protocol-session--from-alist
                '((sessionId . "s-run") (running . t) (blank . t)))))
    (ert-info ((format "%s" "session-wire-false-normalizes-to-nil"))
      (should (null (dsh-protocol-session-running idle)))
      (should (null (dsh-protocol-session-blank idle))))
    (ert-info ((format "%s" "session-wire-true-normalizes-to-t"))
      (should (eq t (dsh-protocol-session-running busy))))))

(ert-deftest dsh-emacs-test-session-idle-row-is-not-busy ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-busy-false*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq-local dsh-emacs--buffer-session "s-idle")
          (dsh-emacs--ml-busy-clear)
          (setq dsh-emacs--sessions
                (list (dsh-protocol-session--from-alist
                       '((sessionId . "s-idle") (running . :json-false)))))
          (ert-info ((format "%s" "idle-row-is-not-busy"))
            (should (null (dsh-emacs--busy-p))))
          (setf (dsh-protocol-session-running (car dsh-emacs--sessions)) t)
          (ert-info ((format "%s" "running-row-is-busy"))
            (should (dsh-emacs--busy-p))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; --- Test 120: session state comes from the running flag, do not invent an
;; interactive state from the wire ---
;; `projections.values.sessionStats.pendingInteraction' does not exist on the
;; session-list wire (never did in 0.1.2 either), so a session that waits on a
;; tool approval must NOT be reported as approval/pending from session data:
;; the only honest list state is running vs idle.
(ert-deftest dsh-emacs-test-session-session-status-ignores-absent-interaction-projection ()
  :tags '(dsh-unit)
  (let* ((with-bogus (dsh-protocol-session--from-alist
                      '((sessionId . "s-status")
                        (running . :json-false)
                        (projections . ((values . ((sessionStats . ((pendingInteraction . "approval"))))))))))
         (running (dsh-protocol-session--from-alist
                   '((sessionId . "s-status2") (running . t)))))
    (ert-info ((format "%s" "session-status-ignores-absent-interaction-projection"))
      (should (eq (dsh-emacs-session--compute-status with-bogus nil) 'idle))
      (should (eq (dsh-emacs-session--compute-status running t) 'running))
      (should (not (fboundp 'dsh-protocol-session-pending-interaction))))))

;; Visual row reuse must preserve mutable inputs and current command targets.
(ert-deftest dsh-emacs-test-session-session-row-cache ()
  :tags '(dsh-unit)
  (let* ((now 1000.0)
         (title (copy-sequence "Original title"))
         (dsh-emacs--sessions
          (list (dsh-protocol-session--from-alist
                 `((sessionId . "cached-a") (updatedAt . 1000)
                   (projections (values (title . ,title)))))
                (dsh-protocol-session--from-alist
                 '((sessionId . "cached-b") (updatedAt . 1000)
                   (projections (values (title . "Second")))))))
         (dsh-emacs--workspaces nil)
         (dsh-emacs--archived-sessions nil)
         (dsh-emacs--current-session nil)
         (dsh-emacs-workspaces-collapsed-by-default nil)
         (dsh-emacs--subagent-catalogs (make-hash-table :test #'equal)))
    (with-temp-buffer
      (cl-letf (((symbol-function 'float-time) (lambda (&optional _) now)))
        (cl-labels
            ((check (label builds)
               (let ((report (dsh-render-report-measure #'dsh-emacs-session--render)))
                 (ert-info ((format "%s" (concat "session-row-cache-" label)))
                   (should (= builds (plist-get report :session-row-builds))))))
             (row () (dsh-emacs-session--row-pos 'dsh-emacs-session-id "cached-a")))
          (check "cold-builds-every-row" 2)
          (check "warm-builds-no-rows" 0)
          (setcar dsh-emacs--sessions (copy-dsh-protocol-session
                                       (car dsh-emacs--sessions)))
          (setf (dsh-protocol-session-context-window (car dsh-emacs--sessions)) 128000)
          (check "metadata-only-replacement-reuses-layout" 0)
          (ert-info ((format "%s" "session-row-cache-publishes-current-object-in-padding"))
            (should (eq (get-text-property (+ (row) 35) 'dsh-emacs-session)
                        (car dsh-emacs--sessions))))
          (aset title 0 ?X)
          (check "in-place-title-mutation-rebuilds-one" 1)
          (ert-info ((format "%s" "session-row-cache-shows-mutated-title"))
            (should (string-match-p "Xriginal title" (buffer-string))))
          (put-text-property 0 1 'help-echo 'changed-property title)
          (check "title-property-change-rebuilds-one" 1)
          (ert-info ((format "%s" "session-row-cache-retains-title-properties"))
            (should (text-property-any (point-min) (point-max) 'help-echo 'changed-property)))
          (setf (dsh-protocol-session-running (car dsh-emacs--sessions)) t)
          (check "status-only-change-rebuilds-one" 1)
          (ert-info ((format "%s" "session-row-cache-status-face-updates"))
            (should (eq (get-text-property (+ (row) 4) 'face) 'dsh-emacs-status-running-face)))
          (setq now 1061.0)
          (check "unchanged-timestamps-age" 2)
          (ert-info ((format "%s" "session-row-cache-time-bucket-updates"))
            (should (string-match-p "1m" (buffer-string))))
          (setq dsh-emacs--current-session "cached-a")
          (setf (dsh-protocol-session-blank (car dsh-emacs--sessions)) t)
          (check "blank-title-rebuilds-one" 1)
          (ert-info ((format "%s" "session-row-cache-blank-title-shown"))
            (should (string-match-p "New Session" (buffer-string))))
          (setf (dsh-protocol-session-blank (car dsh-emacs--sessions)) nil
                (dsh-protocol-session-title-value (car dsh-emacs--sessions)) nil
                (dsh-protocol-session-cwd (car dsh-emacs--sessions)) "/tmp/fallback")
          (check "fallback-title-rebuilds-one" 1)
          (let ((warm (buffer-string)))
            (setq dsh-emacs-session--row-cache nil)
            (check "explicit-cold-render-rebuilds" 2)
            (ert-info ((format "%s" "session-row-cache-cold-and-warm-output-identical"))
              (should (equal-including-properties warm (buffer-string)))))
          (let ((inhibit-read-only t))
            (goto-char (+ (row) 5))
            (delete-char 1)
            (insert "!")
            (put-text-property (+ (row) 35) (+ (row) 36) 'dsh-emacs-subagent 'stale))
          (check "warm-render-repairs-external-edits" 0)
          (ert-info ((format "%s" "session-row-cache-repairs-text-and-command-properties"))
            (should (not (string-match-p "!" (buffer-string))))
            (should (null (get-text-property (+ (row) 35) 'dsh-emacs-subagent))))
          (let ((cache dsh-emacs-session--row-cache) escaped)
            (cl-letf (((symbol-function 'dsh-emacs-session--update-rows)
                       (lambda (_) (error "Publication failed"))))
              (condition-case err
                  (dsh-emacs-session--render)
                (error (setq escaped err))))
            (ert-info ((format "%s" "session-row-cache-failed-publication-keeps-previous-cache"))
              (should (equal escaped '(error "Publication failed")))
              (should (eq cache dsh-emacs-session--row-cache))))
          (setq dsh-emacs--sessions (list (car dsh-emacs--sessions)))
          (check "removed-row-is-pruned" 0)
          (ert-info ((format "%s" "session-row-cache-holds-only-visible-rows"))
            (should (= (hash-table-count dsh-emacs-session--row-cache) 1))
            (should (null (gethash "cached-b" dsh-emacs-session--row-cache))))
          (let ((cache dsh-emacs-session--row-cache))
            (with-temp-buffer
              (check "other-list-buffer-starts-cold" 1)
              (ert-info ((format "%s" "session-row-cache-buffer-ownership-is-independent"))
                (should (not (eq cache dsh-emacs-session--row-cache))))))
          (setq dsh-emacs-session--workspace-fold-overrides '((:ungrouped . t)))
          (check "fold-hides-and-prunes-rows" 0)
          (ert-info ((format "%s" "session-row-cache-folded-cache-is-empty"))
            (should (= (hash-table-count dsh-emacs-session--row-cache) 0)))
          (setq dsh-emacs-session--workspace-fold-overrides nil)
          (check "unfold-rebuilds-pruned-row" 1)
          (setq dsh-emacs--sessions nil)
          (check "empty-list-prunes-all-rows" 0)
          (ert-info ((format "%s" "session-row-cache-empty-list-cache-is-empty"))
            (should (= (hash-table-count dsh-emacs-session--row-cache) 0))))))))

;; A visual hit never skips child traversal, notices or navigation metadata.
(ert-deftest dsh-emacs-test-session-session-row-cache-2 ()
  :tags '(dsh-unit)
  (let* ((dsh-emacs--sessions
          (dsh-emacs-test--session-items '(((sessionId . "cache-root")))))
         (workspace (dsh-protocol-workspace--from-alist
                     '((workspaceId . "cache-ws") (title . "Workspace")
                       (sessionIds . ["cache-root"]))))
         (dsh-emacs--workspaces (list workspace))
         (dsh-emacs--archived-sessions nil)
         (dsh-emacs--current-session nil)
         (dsh-emacs-workspaces-collapsed-by-default nil)
         (dsh-emacs--subagent-catalogs (make-hash-table :test #'equal))
         (cell (dsh-protocol-subagent-cell--from-alist
                '((key . subagentCatalog) (seq . 1)
                  (value . [((id . "cache-child") (label . "Child")
                             (mode . "one-shot"))])))))
    (puthash "cache-root" (list :cells (list (cons 'subagentCatalog cell)))
             dsh-emacs--subagent-catalogs)
    (with-temp-buffer
      (setq dsh-emacs-session--expanded-subagents '("cache-root" "cache-child"))
      (cl-labels ((check (label builds)
                    (let ((report (dsh-render-report-measure #'dsh-emacs-session--render)))
                      (ert-info ((format "%s" (concat "session-row-cache-" label)))
                        (should (= builds (plist-get report :session-row-builds))))))
                  (child-pos () (dsh-emacs-session--row-pos
                                 'dsh-emacs-session-id "cache-child")))
        (check "cold-child-layout" 2)
        (setf (dsh-protocol-subagent-cell-value cell)
              (list (copy-dsh-protocol-subagent-entry
                     (car (dsh-protocol-subagent-cell-value cell)))))
        (setf (dsh-protocol-workspace-title workspace) "Renamed workspace")
        (check "equal-child-replacement-reuses-layout" 0)
        (ert-info ((format "%s" "session-row-cache-current-child-and-workspace-metadata"))
          (should (eq (cdr (get-text-property (child-pos) 'dsh-emacs-subagent))
                      (car (dsh-protocol-subagent-cell-value cell))))
          (should (equal (get-text-property (child-pos) 'dsh-emacs-workspace-title)
                         "Renamed workspace")))
        (setf (dsh-protocol-subagent-entry-mode
               (car (dsh-protocol-subagent-cell-value cell))) "continuable")
        (check "child-mode-change" 1)
        (ert-info ((format "%s" "session-row-cache-current-child-mode"))
          (should (string-match-p "continuable · unknown" (buffer-string))))
        (push (dsh-protocol-session--from-alist
               '((sessionId . "cache-child") (origin . "subagent")
                 (parentSessionId . "cache-root") (running . t)))
              dsh-emacs--sessions)
        (check "child-activity-change" 1)
        (ert-info ((format "%s" "session-row-cache-current-child-activity"))
          (should (string-match-p "continuable · running" (buffer-string)))
          (should (eq (get-text-property (child-pos) 'dsh-emacs-session)
                      (car dsh-emacs--sessions))))
        (puthash "cache-child"
                 (list :cells
                       (list (cons 'subagentCatalog
                                   (dsh-protocol-subagent-cell--from-alist
                                    '((key . subagentCatalog) (seq . 1)
                                      (value . [((id . "cache-grandchild")
                                                 (label . "Grandchild")
                                                 (mode . "one-shot"))]))))))
                 dsh-emacs--subagent-catalogs)
        (check "cached-root-still-traverses-new-grandchild" 2)
        (ert-info ((format "%s" "session-row-cache-new-grandchild-direct-parent"))
          (should (equal (car (get-text-property
                               (dsh-emacs-session--row-pos 'dsh-emacs-session-id "cache-grandchild")
                               'dsh-emacs-subagent))
                         "cache-child")))
        (puthash "cache-root"
                 (plist-put (gethash "cache-root" dsh-emacs--subagent-catalogs)
                            :state 'error)
                 dsh-emacs--subagent-catalogs)
        (check "cached-root-still-renders-notice" 0)
        (ert-info ((format "%s" "session-row-cache-error-notice-visible"))
          (should (string-match-p "Cannot load subagents" (buffer-string))))
        (setq dsh-emacs-session--expanded-subagents nil)
        (check "collapse-updates-disclosure-and-prunes-descendants" 1)
        (ert-info ((format "%s" "session-row-cache-hidden-descendants-pruned"))
          (should (= (hash-table-count dsh-emacs-session--row-cache) 1)))))))

(provide 'dsh-test-session)
;;; dsh-test-session.el ends here

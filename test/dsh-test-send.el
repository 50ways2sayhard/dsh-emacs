;;; dsh-test-send.el --- Send editor context into a chat -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

(defun dsh-test--send-sessions (entries)
  "Session structs for ENTRIES, a list of (SESSION-ID . CWD)."
  (dsh-emacs-test--session-items
   (mapcar (lambda (entry)
             (list (cons 'sessionId (car entry))
                   (cons 'cwd (cdr entry))
                   (cons 'blank :json-false)))
           entries)))

(defun dsh-test--send-chat (session cwd)
  "Create a dsh chat buffer for SESSION whose working directory is CWD."
  (let ((buffer (generate-new-buffer (format " *dsh-send-%s*" session))))
    (with-current-buffer buffer
      (dsh-emacs-mode)
      (setq dsh-emacs--current-session session)
      (setq-local dsh-emacs--buffer-session session)
      (setq default-directory (file-name-as-directory cwd))
      (dsh-emacs--ml-busy-clear))
    buffer))

(defun dsh-test--send-source (directory content name)
  "Visit a file NAME with CONTENT under DIRECTORY and return its buffer."
  (let ((file (expand-file-name name directory)))
    (with-temp-file file
      (insert content))
    (find-file-noselect file)))

(defun dsh-test--send-select-lines (from to)
  "Select whole lines FROM through TO inclusive in the current buffer."
  (goto-char (point-min))
  (forward-line (1- from))
  (set-mark (point))
  (forward-line (- to (1- from)))
  (activate-mark))

;; --- Region context: mention + line range + fenced block ---
(ert-deftest dsh-emacs-test-send-region-appends-context-to-chat-input ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (src nil)
         (chat nil)
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)))))
    (unwind-protect
        (progn
          (setq src (dsh-test--send-source
                     dir ";; header\n(defun a)\n(defun b)\n(defun c)\n"
                     "src.el"))
          (setq chat (dsh-test--send-chat "sess-a" dir))
          (with-current-buffer src
            (dsh-test--send-select-lines 2 3)
            (dsh-emacs-send-region))
          (should (equal (concat "@src.el (lines 2-3):\n\n"
                                 "```emacs-lisp\n"
                                 "(defun a)\n(defun b)\n"
                                 "```")
                         (with-current-buffer chat
                           (dsh-emacs--get-input)))))
      (when (buffer-live-p src) (kill-buffer src))
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory dir t))))

;; --- Appending keeps an existing draft, separated by a blank line ---
(ert-deftest dsh-emacs-test-send-region-separates-from-existing-draft ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (src nil)
         (chat nil)
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)))))
    (unwind-protect
        (progn
          (setq src (dsh-test--send-source
                     dir ";; header\n(defun a)\n" "src.el"))
          (setq chat (dsh-test--send-chat "sess-a" dir))
          (with-current-buffer chat
            (dsh-emacs--replace-input "explain this"))
          (with-current-buffer src
            (dsh-test--send-select-lines 2 2)
            (dsh-emacs-send-region))
          (should (equal (concat "explain this\n\n"
                                 "@src.el (lines 2-2):\n\n"
                                 "```emacs-lisp\n(defun a)\n```")
                         (with-current-buffer chat
                           (dsh-emacs--get-input)))))
      (when (buffer-live-p src) (kill-buffer src))
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory dir t))))

;; --- A file travels as a mention relative to the chat's workspace ---
(ert-deftest dsh-emacs-test-send-file-inserts-relative-mention ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (src nil)
         (chat nil)
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)))))
    (unwind-protect
        (progn
          (setq src (dsh-test--send-source dir "print(1)\n" "proj.py"))
          (setq chat (dsh-test--send-chat "sess-a" dir))
          (with-current-buffer src
            (dsh-emacs-send-file))
          (should (equal "@proj.py"
                         (with-current-buffer chat
                           (dsh-emacs--get-input)))))
      (when (buffer-live-p src) (kill-buffer src))
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory dir t))))

;; --- Auto target: the chat whose directory contains this buffer ---
(ert-deftest dsh-emacs-test-send-file-targets-chat-in-buffer-cwd ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (other (make-temp-file "dsh-send-other-" t))
         (src nil)
         (chat nil)
         (bystander nil)
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)
                                        (cons "sess-b" other)))))
    (unwind-protect
        (progn
          (setq src (dsh-test--send-source dir "x = 1\n" "src.py"))
          (setq chat (dsh-test--send-chat "sess-a" dir))
          (setq bystander (dsh-test--send-chat "sess-b" other))
          (with-current-buffer src
            (dsh-emacs-send-file))
          (should (equal "@src.py"
                         (with-current-buffer chat
                           (dsh-emacs--get-input))))
          (should (equal "" (with-current-buffer bystander
                              (dsh-emacs--get-input)))))
      (when (buffer-live-p src) (kill-buffer src))
      (when (buffer-live-p chat) (kill-buffer chat))
      (when (buffer-live-p bystander) (kill-buffer bystander))
      (delete-directory dir t)
      (delete-directory other t))))

;; --- Dwim falls back to the line at point, labeled by buffer name ---
(ert-deftest dsh-emacs-test-send-dwim-line-labels-buffer-without-file ()
  :tags '(dsh-unit)
  (let* ((chat nil)
         (src (generate-new-buffer " *dsh-send-line*"))
         (dsh-emacs--sessions (dsh-test--send-sessions nil)))
    (unwind-protect
        (progn
          (setq chat (dsh-test--send-chat "sess-a" temporary-file-directory))
          (with-current-buffer src
            (setq default-directory temporary-file-directory)
            (insert "alpha\nbeta\n")
            (goto-char (point-min))
            (forward-line 1)
            (dsh-emacs-send-dwim '(4)))
          (should (equal (concat (format "Buffer %s (lines 2-2):\n\n"
                                         (buffer-name src))
                                 "```\nbeta\n```")
                         (with-current-buffer chat
                           (dsh-emacs--get-input)))))
      (when (buffer-live-p src) (kill-buffer src))
      (when (buffer-live-p chat) (kill-buffer chat)))))

;; --- Images cannot be read through a mention, so they are staged ---
(ert-deftest dsh-emacs-test-send-file-stages-image-instead-of-mention ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (png (expand-file-name "shot.png" dir))
         (src (generate-new-buffer " *dsh-send-image*"))
         (chat nil)
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)))))
    (unwind-protect
        (progn
          (with-temp-file png
            (set-buffer-multibyte nil)
            (insert (base64-decode-string
                     "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")))
          (setq chat (dsh-test--send-chat "sess-a" dir))
          (with-current-buffer src
            (setq buffer-file-name png)
            (setq default-directory dir)
            (dsh-emacs-send-file))
          (with-current-buffer chat
            (should (equal "" (dsh-emacs--get-input)))
            (let ((attachments (dsh-emacs-pending-attachments)))
              (should (= 1 (length attachments)))
              (should (assq 'mediaType (car attachments))))))
      (when (buffer-live-p src) (kill-buffer src))
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory dir t))))

;; --- No region is a user error, not a silent no-op ---
(ert-deftest dsh-emacs-test-send-region-without-region-signals ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (insert "text\n")
    (goto-char (point-min))
    (deactivate-mark)
    (should-error (dsh-emacs-send-region) :type 'user-error)))

;; --- The -to variant sends to the chat it was told, not the inferred one ---
(ert-deftest dsh-emacs-test-send-file-to-uses-prompted-chat ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (other (make-temp-file "dsh-send-other-" t))
         (src nil)
         (chat (dsh-test--send-chat "sess-a" dir))
         (picked (dsh-test--send-chat "sess-b" other))
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)
                                        (cons "sess-b" other)))))
    (unwind-protect
        (progn
          (setq src (dsh-test--send-source other "x = 1\n" "src.py"))
          (with-current-buffer src
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (_prompt collection &rest _)
                         (car (member (buffer-name picked) collection)))))
              (dsh-emacs-send-file-to)))
          (should (equal "@src.py"
                         (with-current-buffer picked
                           (dsh-emacs--get-input))))
          (should (equal "" (with-current-buffer chat
                              (dsh-emacs--get-input)))))
      (when (buffer-live-p src) (kill-buffer src))
      (when (buffer-live-p chat) (kill-buffer chat))
      (when (buffer-live-p picked) (kill-buffer picked))
      (delete-directory dir t)
      (delete-directory other t))))

;; --- Screenshot capture shells out, then stages the PNG like an image file ---
(ert-deftest dsh-emacs-test-send-screenshot-stages-captured-png ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (png (expand-file-name "shot.png" dir))
         (chat nil)
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)))))
    (unwind-protect
        (progn
          (with-temp-file png
            (set-buffer-multibyte nil)
            (insert (base64-decode-string
                     "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")))
          (setq chat (dsh-test--send-chat "sess-a" dir))
          (with-current-buffer chat
            (let ((dsh-emacs-send-screenshot-command (list "cp" png "%s")))
              (dsh-emacs-send-screenshot))
            (let ((attachments (dsh-emacs-pending-attachments)))
              (should (= 1 (length attachments)))
              (should (assq 'mediaType (car attachments))))))
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory dir t))))

;; --- Without a capture command the screenshot command says so ---
(ert-deftest dsh-emacs-test-send-screenshot-without-command-signals ()
  :tags '(dsh-unit)
  (let ((chat (dsh-test--send-chat "sess-a" temporary-file-directory))
        (dsh-emacs--sessions (dsh-test--send-sessions nil))
        (dsh-emacs-send-screenshot-command nil))
    (unwind-protect
        (with-current-buffer chat
          (should-error (dsh-emacs-send-screenshot) :type 'user-error))
      (when (buffer-live-p chat) (kill-buffer chat)))))

;; --- Inside a chat, dwim reads a file instead of quoting the transcript ---
(ert-deftest dsh-emacs-test-send-dwim-in-chat-reads-file ()
  :tags '(dsh-unit)
  (let* ((dir (make-temp-file "dsh-send-" t))
         (file (expand-file-name "note.md" dir))
         (chat nil)
         (dsh-emacs--sessions
          (dsh-test--send-sessions (list (cons "sess-a" dir)))))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "# note\n"))
          (setq chat (dsh-test--send-chat "sess-a" dir))
          (with-current-buffer chat
            (cl-letf (((symbol-function 'read-file-name)
                       (lambda (&rest _) file)))
              (dsh-emacs-send-dwim))
            (should (equal "@note.md" (dsh-emacs--get-input)))))
      (when (buffer-live-p chat) (kill-buffer chat))
      (delete-directory dir t))))

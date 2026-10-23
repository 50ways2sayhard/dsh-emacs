;;; dsh-emacs-send.el --- Send editor context into a dsh chat  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  dsh-emacs contributors

;; Author: dsh-emacs contributors
;; Version: 0.6.1
;; Package-Requires: ((emacs "28.1"))
;; Keywords: tools, convenience
;; License: GPL-3.0-or-later

;; This file is part of dsh-emacs.

;;; Commentary:

;; The chat buffer is where prompts are written, so the editor context a
;; prompt talks about has to reach that buffer's input first: the active
;; region, the file at point, dired's marked files, the line under point,
;; a screenshot.  These commands gather that context and leave it in the
;; input area, where the draft is still editable and nothing is sent
;; before `C-c C-c' — the same shape agent-shell gives its
;; `agent-shell-send-*' commands, adapted to how dsh consumes context:
;;
;;   - A file travels as an `@path' mention, not as uploaded bytes.  dsh
;;     resolves mentions against the session's workspace and the model
;;     reads the file itself when it needs the contents.  Image files are
;;     the exception: a filesystem read cannot show the model pixels, so
;;     they are staged as attachments instead (like `C-c C-a').
;;   - A region or line travels as text: its `@file (lines A-B)' header
;;     plus a fenced code block, because an `@' mention has no line-range
;;     syntax.  Text from a buffer without a file is labeled by buffer
;;     name instead.
;;   - Text is appended to whatever draft already exists, separated by a
;;     blank line, so a send command never destroys a half-written prompt.
;;
;; The target is the current chat when invoked from one; otherwise the
;; open chat whose working directory contains this buffer's, else the
;; only open chat, else a completion prompt over the live chats.  The
;; `-to' variants always prompt, and a prefix argument on `send-dwim'
;; does the same.
;;
;; Screenshot capture is the one host-dependent piece: it shells out to
;; `dsh-emacs-send-screenshot-command', which defaults to macOS's
;; `screencapture -i' and is nil (command unavailable) elsewhere.
;;
;; dsh-emacs already uploads clipboard images and dropped/picked files
;; (`C-c C-v', `C-c C-a', drag-and-drop); this module deliberately does
;; not duplicate those gestures.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(require 'dsh-emacs-reference)

(declare-function dsh-emacs--attachable-file "dsh-emacs" (file))
(declare-function dsh-emacs--chat-cwd "dsh-emacs" (session-id))
(declare-function dsh-emacs--get-input "dsh-emacs" ())
(declare-function dsh-emacs--input-end "dsh-emacs" ())
(declare-function dsh-emacs--stage-attachments "dsh-emacs" (attachments))
(declare-function dired-get-marked-files "dired" ())

(defvar dsh-emacs--buffer-session)
(defvar dsh-emacs--input-marker)

(defcustom dsh-emacs-send-screenshot-command
  (if (eq system-type 'darwin) '("screencapture" "-i" "-x" "%s"))
  "Command that captures a screenshot into the file named by `%s'.
The value is a list of the program and its arguments; each argument
containing `%s' is expanded to a temporary PNG path.  `screencapture -i'
opens the interactive selection UI, so the command may be cancelled and
then produces no image (reported as `user-error').  The default is
available on macOS only; elsewhere set this to an equivalent command, or
leave it nil to disable `dsh-emacs-send-screenshot'."
  :type '(choice (const :tag "Unavailable" nil)
                 (repeat string))
  :group 'dsh-emacs)

(defun dsh-emacs-send--chat-buffer-p (buffer)
  "Return non-nil when BUFFER is a live dsh chat buffer."
  (and (bufferp buffer)
       (buffer-live-p buffer)
       (with-current-buffer buffer
         (and (derived-mode-p 'dsh-emacs-mode)
              dsh-emacs--buffer-session))))

(defun dsh-emacs-send--live-chat-buffers ()
  "Return the live chat buffers, most recently used first."
  (cl-remove-if-not #'dsh-emacs-send--chat-buffer-p (buffer-list)))

(defun dsh-emacs-send--buffer-cwd (buffer)
  "Return chat BUFFER's session working directory."
  (dsh-emacs--chat-cwd (buffer-local-value 'dsh-emacs--buffer-session buffer)))

(defun dsh-emacs-send--buffer-in-cwd-p (buffer)
  "Return non-nil when chat BUFFER's working directory contains this buffer's."
  (when-let* ((cwd (dsh-emacs-send--buffer-cwd buffer)))
    (file-in-directory-p default-directory cwd)))

(defun dsh-emacs-send--prompt-target ()
  "Read the live chat buffer to send context to."
  (let ((buffers (dsh-emacs-send--live-chat-buffers)))
    (unless buffers
      (user-error "No open dsh chat buffer"))
    (if (null (cdr buffers))
        (car buffers)
      (get-buffer (completing-read "Send to chat: "
                                   (mapcar #'buffer-name buffers) nil t)))))

(defun dsh-emacs-send--auto-target ()
  "Return the chat buffer a send command should use by default."
  (cond
   ((dsh-emacs-send--chat-buffer-p (current-buffer))
    (current-buffer))
   ((cl-find-if #'dsh-emacs-send--buffer-in-cwd-p
                (dsh-emacs-send--live-chat-buffers)))
   (t (dsh-emacs-send--prompt-target))))

(defun dsh-emacs-send--append-input (text)
  "Append TEXT to the current chat input, separated from an existing draft."
  (let ((inhibit-read-only t))
    (goto-char (dsh-emacs--input-end))
    (unless (string-empty-p (string-trim (or (dsh-emacs--get-input) "")))
      (insert "\n\n"))
    (insert text)
    (goto-char (dsh-emacs--input-end))))

(defun dsh-emacs-send--deliver (buffer text attachments)
  "Insert TEXT and stage ATTACHMENTS in chat BUFFER, then show BUFFER.
TEXT nil or empty inserts nothing; ATTACHMENTS nil stages nothing."
  (unless (dsh-emacs-send--chat-buffer-p buffer)
    (user-error "Not a dsh chat buffer: %s"
                (if (buffer-live-p buffer)
                    (buffer-name buffer)
                  "dead buffer")))
  (with-current-buffer buffer
    (when attachments
      (dsh-emacs--stage-attachments attachments))
    (when (and text (not (string-empty-p text)))
      (dsh-emacs-send--append-input text)))
  (unless (eq buffer (current-buffer))
    (pop-to-buffer buffer))
  buffer)

(defun dsh-emacs-send--mention (file cwd)
  "Return the `@' mention for FILE relative to CWD, or nil when impossible."
  (let* ((kind (if (file-directory-p file) "directory" "file"))
         (path (if (and cwd (file-in-directory-p file cwd))
                   (file-relative-name file cwd)
                 (expand-file-name file))))
    (dsh-emacs-reference--format-file-mention path kind)))

(defun dsh-emacs-send--language ()
  "Return the fence language for this buffer's major mode, or nil.
Plain-text modes get no language so the block stays unhighlighted."
  (let ((mode (symbol-name major-mode)))
    (unless (member mode '("fundamental-mode" "text-mode" "conf-mode"))
      (replace-regexp-in-string "\\(?:-ts\\)?-mode\\'" "" mode))))

(defun dsh-emacs-send--fence (text)
  "Return backtick fence marks longer than any run in TEXT."
  (let ((marks "```"))
    (while (string-match-p (concat (regexp-quote marks) "`") text)
      (setq marks (concat marks "`")))
    marks))

(defun dsh-emacs-send--context-text (start end cwd)
  "Return prompt text for the region START..END of the current buffer.
CWD is the target chat's directory, used to keep a file mention relative.
A file-visiting buffer is introduced by its mention and line range, any
other buffer by its name and line range."
  (let* ((body (string-trim-right
                (buffer-substring-no-properties start end)))
         (first (line-number-at-pos start))
         (last (line-number-at-pos (if (> end start) (1- end) start)))
         (file (buffer-file-name))
         (language (dsh-emacs-send--language))
         (marks (dsh-emacs-send--fence body))
         (location (if file
                       (let ((mention (dsh-emacs-send--mention file cwd)))
                         (if mention
                             (format "%s (lines %d-%d)" mention first last)
                           (format "%s (lines %d-%d)"
                                   (abbreviate-file-name file) first last)))
                     (format "Buffer %s (lines %d-%d)"
                             (buffer-name) first last))))
    (format "%s:\n\n%s%s\n%s\n%s"
            location marks (or language "") body marks)))

(defun dsh-emacs-send--region (target &optional start end)
  "Send the region (or START..END) to chat TARGET, nil meaning the default."
  (unless (and start end)
    (unless (use-region-p)
      (user-error "No region selected"))
    (setq start (region-beginning)
          end (region-end)))
  (deactivate-mark)
  (let* ((buffer (or target (dsh-emacs-send--auto-target)))
         (text (dsh-emacs-send--context-text
                start end (dsh-emacs-send--buffer-cwd buffer))))
    (dsh-emacs-send--deliver buffer text nil)))

;;;###autoload
(defun dsh-emacs-send-region ()
  "Send the active region to a dsh chat's input area.
The region travels as text — an `@file (lines A-B)' header followed by a
fenced block — because a dsh `@' mention has no line-range syntax.  The
text waits in the chat input; `C-c C-c' sends it."
  (interactive)
  (dsh-emacs-send--region nil))

;;;###autoload
(defun dsh-emacs-send-region-to ()
  "Send the active region to a chat chosen from the open dsh chats."
  (interactive)
  (unless (use-region-p)
    (user-error "No region selected"))
  (let ((start (region-beginning))
        (end (region-end)))
    (dsh-emacs-send--region (dsh-emacs-send--prompt-target) start end)))

(defun dsh-emacs-send--files ()
  "Return the files `dsh-emacs-send-file' should send from this buffer.
Dired sends its marked files (or the file on its current line), a
file-visiting buffer sends its file, and any other buffer reads a name."
  (cond
   ((derived-mode-p 'dired-mode) (dired-get-marked-files))
   ((buffer-file-name) (list (buffer-file-name)))
   (t (list (read-file-name "Send file: " nil nil t)))))

(defun dsh-emacs-send--classify (files)
  "Split FILES into (ATTACHMENTS . MENTION-FILES).
An image the host can carry inline becomes an attachment: a filesystem
read cannot show the model an image's contents, so an `@path' mention
would name a file the model cannot inspect.  Every other path stays a
mention."
  (let (attachments mentions)
    (dolist (file files)
      (let ((attachment (dsh-emacs--attachable-file file)))
        (if (and attachment (assq 'mediaType attachment))
            (push attachment attachments)
          (push file mentions))))
    (cons (nreverse attachments) (nreverse mentions))))

(defun dsh-emacs-send--mention-text (files cwd)
  "Return the `@' mention line for FILES relative to CWD."
  (mapconcat
   (lambda (file)
     (unless (or (file-directory-p file)
                 (and (file-regular-p file) (file-readable-p file)))
       (user-error "Cannot send %s: not a readable file or directory"
                   (abbreviate-file-name file)))
     (or (dsh-emacs-send--mention file cwd)
         (user-error "Cannot reference %s as an @ mention"
                     (abbreviate-file-name file))))
   files " "))

(defun dsh-emacs-send--send-files (target prompt-for-file)
  "Send the file(s) around point to chat TARGET (nil = the default).
PROMPT-FOR-FILE always reads a file name instead of using the buffer's."
  (let* ((buffer (or target (dsh-emacs-send--auto-target)))
         (files (if prompt-for-file
                    (list (read-file-name "Send file: " nil nil t))
                  (dsh-emacs-send--files)))
         (classify (dsh-emacs-send--classify files))
         (text (dsh-emacs-send--mention-text
                (cdr classify) (dsh-emacs-send--buffer-cwd buffer))))
    (dsh-emacs-send--deliver buffer text (car classify))))

;;;###autoload
(defun dsh-emacs-send-file (&optional prompt-for-file)
  "Send the file at point to a dsh chat's input area as an `@' mention.
With an active region in a file-visiting buffer, send that region
instead; with a prefix argument (PROMPT-FOR-FILE non-nil), read a file
name instead of using the buffer's.  Dired sends its marked files, a
file-visiting buffer sends its file, and any other buffer reads a name.

The file is referenced, not uploaded: the chat receives `@path' text and
the model reads the file when it needs it.  Images are the exception —
they are staged as attachments, because the model cannot inspect image
contents through a filesystem read.  Either way the text or attachment
waits in the chat input and `C-c C-c' sends it."
  (interactive "P")
  (if (and (not prompt-for-file)
           (not (derived-mode-p 'dired-mode))
           (region-active-p)
           (buffer-file-name))
      (dsh-emacs-send-region)
    (dsh-emacs-send--send-files nil prompt-for-file)))

;;;###autoload
(defun dsh-emacs-send-file-to (&optional prompt-for-file)
  "Send the file at point as an `@' mention to a chat chosen by prompt.
PROMPT-FOR-FILE behaves as in `dsh-emacs-send-file'."
  (interactive "P")
  (if (and (not prompt-for-file)
           (not (derived-mode-p 'dired-mode))
           (region-active-p)
           (buffer-file-name))
      (dsh-emacs-send-region-to)
    (dsh-emacs-send--send-files (dsh-emacs-send--prompt-target)
                                prompt-for-file)))

;;;###autoload
(defun dsh-emacs-send-other-file ()
  "Read a file name and send it to a dsh chat's input area as an `@' mention."
  (interactive)
  (dsh-emacs-send-file t))

(defun dsh-emacs-send--line (target)
  "Send the line at point to chat TARGET (nil = the default)."
  (let ((start (line-beginning-position))
        (end (line-end-position)))
    (when (string-empty-p (string-trim (buffer-substring-no-properties
                                        start end)))
      (user-error "Nothing to send at point"))
    (let* ((buffer (or target (dsh-emacs-send--auto-target)))
           (text (dsh-emacs-send--context-text
                  start end (dsh-emacs-send--buffer-cwd buffer))))
      (dsh-emacs-send--deliver buffer text nil))))

;;;###autoload
(defun dsh-emacs-send-dwim (&optional arg)
  "Send what point means to a dsh chat's input area.
In dired, send the marked files; with an active region, send the region;
in a chat buffer, read a file name; in a file-visiting buffer, send the
file; anywhere else, send the line at point.  The context waits in the chat
input and `C-c C-c' sends it.  With a prefix argument ARG, read the target
chat from the open chats."
  (interactive "P")
  (let ((target (and arg (dsh-emacs-send--prompt-target))))
    (cond
     ((derived-mode-p 'dired-mode)
      (dsh-emacs-send--send-files target nil))
     ((use-region-p)
      (dsh-emacs-send--region target))
     ((derived-mode-p 'dsh-emacs-mode)
      (dsh-emacs-send--send-files target t))
     ((buffer-file-name)
      (dsh-emacs-send--send-files target nil))
     (t (dsh-emacs-send--line target)))))

(defun dsh-emacs-send--capture-screenshot ()
  "Capture a screenshot to a temporary PNG file and return its path."
  (unless dsh-emacs-send-screenshot-command
    (user-error
     "Screenshot capture is unavailable; set `dsh-emacs-send-screenshot-command'"))
  (let* ((file (make-temp-file "dsh-emacs-screenshot-" nil ".png"))
         (command (car dsh-emacs-send-screenshot-command))
         (args (mapcar (lambda (arg)
                         (if (string-match-p "%s" arg)
                             (string-join (split-string arg "%s") file)
                           arg))
                       (cdr dsh-emacs-send-screenshot-command)))
         (keep nil))
    (unwind-protect
        (progn
          (unless (zerop (apply #'call-process command nil nil nil args))
            (user-error "Screenshot command %s failed" command))
          (unless (and (file-exists-p file)
                       (> (file-attribute-size (file-attributes file)) 0))
            (user-error "Screenshot command %s produced no image" command))
          (setq keep t)
          file)
      (unless keep
        (ignore-errors (delete-file file))))))

;;;###autoload
(defun dsh-emacs-send-screenshot (&optional arg)
  "Capture a screenshot and stage it for a dsh chat.
The screenshot joins the chat's staged attachments; `C-c C-c' sends it
with the drafted caption.  With a prefix argument ARG, read the target
chat from the open chats.  See `dsh-emacs-send-screenshot-command'."
  (interactive "P")
  (let* ((buffer (if arg
                     (dsh-emacs-send--prompt-target)
                   (dsh-emacs-send--auto-target)))
         (file (dsh-emacs-send--capture-screenshot)))
    (unwind-protect
        (let ((attachment (dsh-emacs--attachable-file file)))
          (unless (assq 'mediaType attachment)
            (user-error "Screenshot is not in `dsh-emacs-attach-media-types'"))
          (dsh-emacs-send--deliver buffer nil (list attachment)))
      (ignore-errors (delete-file file)))))

(provide 'dsh-emacs-send)

;;; dsh-emacs-send.el ends here

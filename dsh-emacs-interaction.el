;;; dsh-emacs-interaction.el --- Composer forms for dsh questions and approvals  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  dsh-emacs contributors

;; Author: dsh-emacs contributors
;; Version: 0.6.1
;; Package-Requires: ((emacs "28.1"))
;; Keywords: tools, convenience
;; License: GPL-3.0-or-later

;; This file is part of dsh-emacs.

;;; Commentary:

;; dsh pushes `user-questions/request' and `approval/request'
;; waterfalls over the core connection's `$events' stream.  Each
;; waterfall must be answered with an outcome POSTed to
;; /api/$events/result, and until it is answered the host waits.
;;
;; Earlier versions collected every question in the minibuffer.  The
;; minibuffer is a single global resource: with several sessions live,
;; a question from one session interrupted whatever the user was typing
;; in another, and C-g (or any reader error) declined the whole batch by
;; accident.  This module renders each request as a form in the owning
;; chat buffer's Composer chrome instead — the rows directly above the
;; input line, matching dsh web's composer ask panel.  Nothing is read
;; synchronously, so the process filter never blocks and parallel
;; sessions keep running.
;;
;; A form is a fixed set of read-only rows plus cells:
;;
;;   ? Question 1/2 · Scope   (Nerd Font help-circle when available)
;;      Which files may I touch?
;;      1 src/    2 test/    3 docs/
;;      Click an option to answer · type your own · C-c C-c · empty skips
;;
;; Option cells are clickable/`RET'-able (`dsh-emacs-interaction-activate').
;; A single-select option answers at once; a multi-select option toggles
;; its number in the draft so the user can keep picking, then `C-c C-c'
;; sends.  Free-text answers and skips still use the draft.  `C-c C-c'
;; (still the chat's send key) answers the form while one is current
;; instead of sending a message; `C-c C-k' declines the batch (the same
;; `rejected' outcome dsh web's "leave" produces, so the host aborts the
;; ask instead of waiting forever); `C-c C-u' allows a pending approval
;; once.
;;
;; Requests are per-buffer, oldest first.  The oldest question form owns
;; the input line (only one draft exists); later ones are queued one-line
;; summaries, and each becomes current as the one before it is answered.
;; Approvals carry their own cells and can be decided in any order.
;;
;; A timed question (`wait' in the frame) stays answerable after its
;; window closes.  The form claims the `userQuestions/attachWait' stream
;; while it is pending, so the host suspends the deadline instead of
;; expiring the call; the claim is released once the answer is
;; acknowledged.  When the host still closes the window (timed out
;; elsewhere, replayed projection), the form becomes `late': it stays in
;; the Composer and answers through `userQuestions/answer' instead of
;; the waterfall.  `C-c C-p' materializes late forms for a session's
;; still-`continued' calls.
;;
;; Deferred arrivals and replays: an event-id already answered or
;; withdrawn is remembered (`dsh-emacs-interaction--retired') so a
;; replayed frame cannot reopen a form.  A closed chat hands its live
;; frames back with outcome `next' — another client may claim them —
;; the same handoff the `$events' dispatcher does when no chat buffer is
;; live.  A new `$events' generation retires the previous generation's
;; forms, because the old event ids cannot be answered with the new
;; client id.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(require 'dsh-emacs-faces)
(require 'dsh-emacs-protocol)

(declare-function dsh-emacs--clear-input "dsh-emacs" ())
(declare-function dsh-emacs--events-result-async
                  "dsh-emacs" (client-id event-id outcome callback))
(declare-function dsh-emacs--input-end "dsh-emacs" ())
(declare-function dsh-emacs--rpc-async "dsh-emacs" (method params callback))
(declare-function dsh-emacs-composer--row-width "dsh-emacs-composer" ())
(declare-function dsh-emacs-composer-refresh "dsh-emacs-composer" ())
(declare-function dsh-emacs-events-close-stream
                  "dsh-emacs-events" (process stream-id))
(declare-function dsh-emacs-events-open-stream
                  "dsh-emacs-events" (process endpoint args name handler))
(declare-function dsh-emacs-notify--post
                  "dsh-emacs-render" (session-id body &optional buffer))
(declare-function dsh-emacs-plan--cancel "dsh-emacs-plan" (&optional event-id))
(declare-function dsh-emacs-render--tool-state "dsh-emacs-render" (call-id))
(declare-function dsh-emacs-render-question-settled
                  "dsh-emacs-render" (call-id answers-json))
(declare-function dsh-emacs-subagent-require "dsh-emacs-subagent" (capability))
(declare-function nerd-icons-mdicon "nerd-icons" (icon-name &rest args))

(defvar nerd-icons-font-family)
(defvar dsh-emacs--buffer-session)
(defvar dsh-emacs--chat-buffers)
(defvar dsh-emacs--event-process)
(defvar dsh-emacs--input-marker)
(defvar dsh-emacs--tool-states)
(defvar dsh-emacs-approval-language)
(defvar dsh-emacs-events--client-id)

;;; State

(defun dsh-emacs-interaction--make-request (&rest slots)
  "Return a fresh pending waterfall request from keyword SLOTS.
A request is a plist owned by one chat buffer's buffer-local
`dsh-emacs-interaction--requests': `:kind' (`question' or `approval'),
`:id' (the waterfall event id, or \"call:CALL-ID\" for a late question),
`:event-id' (nil once it can only be answered late), `:session-id',
`:chat', `:questions', `:index', `:answers', `:wait', `:call-id',
`:tool-name', `:reason', `:state' (`pending', `sending' or `late') and
`:claim' (the `userQuestions/attachWait' stream while the form keeps a
timed window open).  Every slot is present up front, so later updates
can `setf' `plist-get' in place."
  (let ((request (list :kind nil :id nil :event-id nil :session-id nil
                       :chat nil :questions nil :index 0 :answers nil
                       :wait nil :call-id nil :tool-name nil :reason nil
                       :state 'pending :claim nil)))
    (cl-loop for (key value) on slots by #'cddr
             do (setf (plist-get request key) value))
    request))

(defvar-local dsh-emacs-interaction--requests nil
  "This chat buffer's pending waterfall forms, oldest first.
Entries are request plists made by
`dsh-emacs-interaction--make-request'.  The oldest
question form owns the input line; approvals are decided by their cells
or `C-c C-u'.")

(defvar-local dsh-emacs-interaction--session-questions nil
  "This chat buffer's latest `userQuestions' projection.
A `dsh-protocol-user-questions' struct: the still-answerable calls
(`active', state `open'/`continued') and the settled ones.  It outlives
single waterfalls: timed asks remain answerable after their window.")

(defvar-local dsh-emacs-interaction--retired nil
  "Event ids already answered or withdrawn in this chat buffer.
A replayed waterfall with one of these ids is ignored, so a form never
reopens for an outcome the host already received.  Bounded by
`dsh-emacs-interaction--retired-limit'.")

(defconst dsh-emacs-interaction--retired-limit 200
  "How many retired event ids a chat buffer keeps for replay dedupe.")

(defconst dsh-emacs-interaction--max-forms 3
  "How many pending requests render as full Composer forms.
Older ones stay pending in `dsh-emacs-interaction--requests' and are
named in a summary row; the oldest request is always rendered.")

;;; Lookup

(defun dsh-emacs-interaction--find (id)
  "Return this buffer's pending request named ID, or nil."
  (and id
       (cl-find id dsh-emacs-interaction--requests
                :key (lambda (request) (plist-get request :id))
                :test #'equal)))

(defun dsh-emacs-interaction--request-for-call (call-id)
  "Return this buffer's request for CALL-ID, live or late."
  (and call-id
       (cl-find-if (lambda (request)
                     (equal call-id (plist-get request :call-id)))
                   dsh-emacs-interaction--requests)))

(defun dsh-emacs-interaction--oldest ()
  "Return this buffer's oldest pending request, or nil."
  (car dsh-emacs-interaction--requests))

(defun dsh-emacs-interaction--current-question ()
  "Return the question form that owns the input line, or nil."
  (cl-find 'question dsh-emacs-interaction--requests
           :key (lambda (request) (plist-get request :kind))))

(defun dsh-emacs-interaction--current-approval ()
  "Return this buffer's oldest pending approval form, or nil."
  (cl-find 'approval dsh-emacs-interaction--requests
           :key (lambda (request) (plist-get request :kind))))

(defun dsh-emacs-interaction--visible ()
  "Return (SHOWN . ELIDED) for this buffer's Composer form rows.
SHOWN starts with the oldest request -- the one that owns the input line
when it is a question -- and ends with the newest, so an arriving request
is always visible; ELIDED counts the middle requests left out of the
display once more than `dsh-emacs-interaction--max-forms' are pending."
  (let ((requests dsh-emacs-interaction--requests)
        (max dsh-emacs-interaction--max-forms)
        (total (length dsh-emacs-interaction--requests)))
    (if (<= total max)
        (cons requests 0)
      (cons (append (list (car requests))
                    (last requests (1- max)))
            (- total max)))))

(defun dsh-emacs-interaction--remember-retired (id)
  "Remember ID as retired in this buffer for replay dedupe."
  (when (stringp id)
    (setq dsh-emacs-interaction--retired
          (cons id dsh-emacs-interaction--retired))
    (when (> (length dsh-emacs-interaction--retired)
             dsh-emacs-interaction--retired-limit)
      (setcdr (nthcdr (1- dsh-emacs-interaction--retired-limit)
                      dsh-emacs-interaction--retired)
              nil))))

;;; Timed wait claim

(defun dsh-emacs-interaction--claim (request chat session-id wait)
  "Hold the timed foreground window of REQUEST's call open.
WAIT is the frame's `dsh-protocol-question-wait'.  The host suspends the
wait's deadline while a client holds the `userQuestions/attachWait'
stream, so the form cannot be expired and declined out from under the
user.  The claim is released when the answer is acknowledged or the form
retires; a non-timed or call-less wait needs no claim."
  (when (and wait (dsh-protocol-question-wait-timed wait)
             (buffer-live-p chat))
    (let ((call-id (dsh-protocol-question-wait-call-id wait)))
      (when (and (stringp call-id) (not (string-empty-p call-id)))
        (with-current-buffer chat
          (let ((process (and (boundp 'dsh-emacs--event-process)
                              dsh-emacs--event-process)))
            (when (process-live-p process)
              (let ((stream (dsh-emacs-events-open-stream
                             process "userQuestions/attachWait"
                             (dsh-protocol-question-wait-request session-id call-id)
                             "userQuestions/attachWait"
                             (lambda (_value) nil))))
                (when stream
                  (setf (plist-get request :claim)
                        (cons process stream)))))))))))

(defun dsh-emacs-interaction--release (request)
  "Release REQUEST's held timed window, if any."
  (when-let* ((claim (plist-get request :claim)))
    (setf (plist-get request :claim) nil)
    (dsh-emacs-events-close-stream (car claim) (cdr claim))))

(defun dsh-emacs-interaction--refresh ()
  "Repaint this chat buffer's Composer rows."
  (when (derived-mode-p 'dsh-emacs-mode)
    (dsh-emacs-composer-refresh)))

(defun dsh-emacs-interaction--question-icon (&optional face)
  "Return the question form's leading icon, preferring Nerd Font.
Uses `nf-md-help_circle_outline' when `nerd-icons' and its font are
available on a graphic frame; otherwise a plain `?' so terminals never
see a PUA glyph.  FACE defaults to `dsh-emacs-accent-face'."
  (let ((face (or face 'dsh-emacs-accent-face)))
    (or (when (and (display-graphic-p)
                   (or (featurep 'nerd-icons) (require 'nerd-icons nil t))
                   (fboundp 'nerd-icons-mdicon)
                   (boundp 'nerd-icons-font-family)
                   (find-font (font-spec :family nerd-icons-font-family)))
          (nerd-icons-mdicon "nf-md-help_circle_outline"
                             :face face :height 1.0 :v-adjust 0.0))
        (propertize "?" 'face face))))

(defun dsh-emacs-interaction--retire (request &optional note)
  "Drop REQUEST from this buffer and release its held window.
NOTE, when non-nil, is echoed.  The request's event id joins the retired
set so a replay cannot reopen it."
  (dsh-emacs-interaction--release request)
  (setq dsh-emacs-interaction--requests
        (delq request dsh-emacs-interaction--requests))
  (dsh-emacs-interaction--remember-retired
   (or (plist-get request :event-id)
       (plist-get request :id)))
  (dsh-emacs-interaction--refresh)
  (when (and note (buffer-live-p (current-buffer)))
    (message "%s" note)))

;;; Input handling

(defun dsh-emacs-interaction--input-text ()
  "Return the raw text of this chat's input line."
  (if (and (boundp 'dsh-emacs--input-marker)
           (markerp dsh-emacs--input-marker)
           (eq (marker-buffer dsh-emacs--input-marker) (current-buffer)))
      (buffer-substring-no-properties dsh-emacs--input-marker
                                      (dsh-emacs--input-end))
    ""))

(defun dsh-emacs-interaction--tokens (text)
  "Return TEXT's comma-separated, trimmed tokens."
  (split-string (string-trim text) "[ \t]*,[ \t]*" t))

(defun dsh-emacs-interaction--toggle-token (text number)
  "Return TEXT with option NUMBER toggled in its token list."
  (let* ((token (number-to-string number))
         (tokens (dsh-emacs-interaction--tokens text))
         (kept (delete token (copy-sequence tokens))))
    (if (= (length kept) (length tokens))
        (string-join (append kept (list token)) ", ")
      (string-join kept ", "))))

(defun dsh-emacs-interaction--resolve-options (text options multi)
  "Return option labels named in TEXT, or nil when TEXT is a custom answer.
Numbers are option positions; labels match case-insensitively in option
order.  A single-select question resolves only one option, because it
cannot answer with two.  Any token that names no option makes TEXT a
custom answer, so loose free text wins over partial matches."
  (let ((picked nil)
        (matched t))
    (dolist (token (dsh-emacs-interaction--tokens text))
      (let* ((trimmed (string-trim token))
             (number (and (string-match-p "\\`[0-9]+\\'" trimmed)
                          (string-to-number trimmed)))
             (positioned (and number (> number 0)
                              (<= number (length options))
                              (nth (1- number) options)))
             (labelled (unless positioned
                         (cl-find-if
                          (lambda (candidate)
                            (string-equal
                             (downcase trimmed)
                             (downcase (or (dsh-protocol-question-option-label
                                            candidate)
                                           ""))))
                          options))))
        (cond
         (positioned (cl-pushnew positioned picked :test #'eq))
         (labelled (cl-pushnew labelled picked :test #'eq))
         (t (setq matched nil)))))
    (when (and matched picked
               (or multi (= (length picked) 1)))
      (let ((labels nil))
        (dolist (option options)
          (when (memq option picked)
            (push (dsh-protocol-question-option-label option) labels)))
        (nreverse labels)))))

(defun dsh-emacs-interaction--interpret (question text)
  "Return (MODE . VALUE) for TEXT answering QUESTION.
MODE is `skip' (VALUE nil), `custom' (VALUE the text) or `labels'
(VALUE a list of option labels in option order)."
  (let ((options (dsh-protocol-question-options question))
        (trimmed (string-trim (or text ""))))
    (cond
     ((string-empty-p trimmed) (cons 'skip nil))
     ((null options) (cons 'custom trimmed))
     (t (let ((labels (dsh-emacs-interaction--resolve-options
                       trimmed options
                       (dsh-protocol-question-multi-select question))))
          (if labels (cons 'labels labels) (cons 'custom trimmed)))))))

(defun dsh-emacs-interaction--make-answer (question text)
  "Return the wire answer request for QUESTION built from TEXT."
  (let ((id (dsh-protocol-question-id question))
        (interpreted (dsh-emacs-interaction--interpret question text)))
    (pcase (car interpreted)
      ('skip (dsh-protocol-question-answer-request id []))
      ('custom (dsh-protocol-question-answer-request
                id [] (cdr interpreted)))
      ('labels (dsh-protocol-question-answer-request
                id (cdr interpreted))))))

(defun dsh-emacs-interaction--stage-option (id index number)
  "Act on option NUMBER of question INDEX of request ID.
A single-select question answers with that option immediately.  A
multi-select question toggles the number in the comma-separated draft
so the user can keep picking, then answer with `C-c C-c'."
  (let ((request (dsh-emacs-interaction--find id)))
    (unless request
      (user-error "That request is no longer pending"))
    (when (eq (plist-get request :state) 'sending)
      (user-error "This answer is being sent already"))
    (unless (= index (plist-get request :index))
      (user-error "That question is not the one being asked"))
    (let* ((question (nth index (plist-get request :questions)))
           (multi (dsh-protocol-question-multi-select question)))
      (if multi
          (let* ((current (dsh-emacs-interaction--input-text))
                 (text (dsh-emacs-interaction--toggle-token current number)))
            (dsh-emacs--clear-input)
            (goto-char dsh-emacs--input-marker)
            (insert text)
            (if (string-empty-p text)
                (message "Cleared the staged options — C-c C-c sends")
              (message "Staged %s — C-c C-c sends" text)))
        (dsh-emacs--clear-input)
        (dsh-emacs-interaction--advance
         request
         (dsh-emacs-interaction--make-answer
          question (number-to-string number)))))))

;;; Rendering

(defvar dsh-emacs-interaction-cell-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'dsh-emacs-interaction-activate)
    (define-key map [return] #'dsh-emacs-interaction-activate)
    (define-key map [mouse-1] #'dsh-emacs-interaction-activate)
    (define-key map [mouse-2] #'dsh-emacs-interaction-activate)
    map)
  "Keymap carried by every Composer form cell.
The cells live on read-only chrome text above the input line, so this
keymap cannot shadow anything in the draft.")

(defun dsh-emacs-interaction--fit (text &optional face)
  "Truncate TEXT to one Composer row and fontify it with FACE.
Use this for chrome that must stay one line (title, hint, queued
summaries).  Question text and options wrap instead — see
`dsh-emacs-interaction--wrap' / `--pack-cells'."
  (let ((body (truncate-string-to-width
               text (dsh-emacs-composer--row-width) nil nil "…")))
    (if face (propertize body 'face face) body)))

(defvar dsh-emacs-interaction--url-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'dsh-emacs-interaction-open-url-at-point)
    (define-key map [mouse-1] #'dsh-emacs-interaction-open-url-at-point)
    map)
  "Keymap for URLs embedded in Composer interaction forms.")

(defun dsh-emacs-interaction-open-url-at-point (&optional event)
  "Open the URL under point or mouse EVENT with `browse-url'."
  (interactive (list last-command-event))
  (let* ((pos (or (and (consp event) (posn-point (event-start event)))
                  (point)))
         (url (and pos (get-text-property pos 'dsh-emacs-interaction-url))))
    (when (and (stringp url) (not (string-empty-p url)))
      (browse-url url))))

(defun dsh-emacs-interaction--linkify (text)
  "Return TEXT with http(s) URLs clickable via `browse-url'.
Continuation rows from hard-wrapping keep the same URL property, so a
link that spans Composer lines remains one clickable target."
  (let ((out (copy-sequence text))
        (start 0))
    (while (string-match "https?://[^[:space:]\n]+" out start)
      (let* ((beg (match-beginning 0))
             (end (match-end 0))
             (url (match-string 0 out)))
        (add-text-properties
         beg end
         (list 'face 'link
               'mouse-face 'highlight
               'help-echo (format "%s\nRET or mouse-1 opens in a browser" url)
               'keymap dsh-emacs-interaction--url-keymap
               'dsh-emacs-interaction-url url)
         out)
        (setq start end)))
    out))

(defun dsh-emacs-interaction--wrap (text &optional face indent)
  "Return TEXT wrapped to the Composer width as one or more rows.
INDENT (default 3 spaces) prefixes the first line and each soft wrap
(after whitespace).  Hard-broken continuations of a long token — URLs
in particular — omit the indent so selecting the wrapped block still
copies the original string.  http(s) URLs are linkified on the source
string before wrapping, so a URL that spans Composer rows keeps one
`browse-url' target on every fragment."
  (let* ((indent (or indent "   "))
         (row-width (max 1 (dsh-emacs-composer--row-width)))
         (source (dsh-emacs-interaction--linkify
                  (replace-regexp-in-string
                   "[ \t]*\n[ \t]*" " "
                   (string-trim (or text "")))))
         (rows nil)
         (pos 0)
         (len (length source))
         (continue-unindented nil))
    (if (string-empty-p source)
        (dsh-emacs-interaction--fit indent face)
      (while (< pos len)
        (let* ((prefix (if continue-unindented "" indent))
               (limit (max 1 (- row-width (string-width prefix))))
               (end pos)
               (width 0)
               (break pos)
               (hard nil))
          (while (and (< end len)
                      (<= (+ width (char-width (aref source end))) limit))
            (let ((ch (aref source end)))
              (setq width (+ width (char-width ch))
                    end (1+ end))
              (when (memq ch '(?\s ?\t))
                (setq break end))))
          (cond
           ((= end pos)
            (setq end (1+ pos)
                  hard t))
           ((and (< end len) (> break pos))
            (setq end break
                  hard nil))
           ((< end len)
            (setq hard t)))
          ;; `substring' keeps the URL text properties on each fragment.
          (push (concat prefix
                        (string-trim-right (substring source pos end)))
                rows)
          (setq pos end
                continue-unindented hard)
          (unless hard
            (while (and (< pos len)
                        (memq (aref source pos) '(?\s ?\t)))
              (setq pos (1+ pos))))))
      (let ((body (mapconcat #'identity (nreverse rows) "\n")))
        (if face
            ;; Keep URL `link' faces; apply FACE only where none is set.
            (let ((i 0)
                  (n (length body)))
              (while (< i n)
                (let ((next (or (next-single-property-change i 'face body)
                                n)))
                  (unless (get-text-property i 'face body)
                    (put-text-property i next 'face face body))
                  (setq i next)))
              body)
          body)))))

(defun dsh-emacs-interaction--pack-cells (cells &optional indent)
  "Join CELLS into Composer rows, wrapping before they overflow.
INDENT (default 3 spaces) prefixes every row.  A cell wider than the
budget still occupies its own row — never truncated — so every option
stays clickable."
  (let* ((indent (or indent "   "))
         (width (max 1 (dsh-emacs-composer--row-width)))
         (gap "   ")
         (rows nil)
         (current indent))
    (dolist (cell cells)
      (let* ((candidate (if (equal current indent)
                            (concat indent cell)
                          (concat current gap cell))))
        (if (and (not (equal current indent))
                 (> (string-width candidate) width))
            (progn
              (push current rows)
              (setq current (concat indent cell)))
          (setq current candidate))))
    (unless (equal current indent)
      (push current rows))
    (mapconcat #'identity (nreverse rows) "\n")))

(defun dsh-emacs-interaction--cell (label id action face &optional help)
  "Propertize LABEL as a form cell of request ID performing ACTION.
ACTION is `(option INDEX NUMBER)', `allow' or `reject'."
  (propertize label
              'face face
              'mouse-face 'highlight
              'help-echo (format "%s\nRET or mouse-1 decides" (or help label))
              'keymap dsh-emacs-interaction-cell-keymap
              'dsh-emacs-interaction-id id
              'dsh-emacs-interaction-action action))

(defun dsh-emacs-interaction--control-at (pos)
  "Return the cell control at POS as (ID . ACTION), or nil."
  (let ((id (and pos (get-text-property pos 'dsh-emacs-interaction-id))))
    (when id
      (cons id (get-text-property pos 'dsh-emacs-interaction-action)))))

(defun dsh-emacs-interaction--event-pos (event)
  "Return the buffer position of mouse EVENT."
  (let ((start (event-start event)))
    (when start (posn-point start))))

(defun dsh-emacs-interaction--question-title (question index total state)
  "Return the chip row naming REQUEST's current question."
  (let ((header (and question (dsh-protocol-question-header question)))
        (icon (if (eq state 'sending)
                  (propertize "…" 'face 'dsh-emacs-accent-face)
                (dsh-emacs-interaction--question-icon))))
    (dsh-emacs-interaction--fit
     (concat icon " "
             "Question"
             (if (> total 1) (format " %d/%d" (1+ index) total) "")
             (if (and (stringp header) (not (string-empty-p header)))
                 (concat " · " header)
               "")
             (if (eq state 'late) " · window closed — answer late" ""))
     'dsh-emacs-accent-face)))

(defun dsh-emacs-interaction--options-line (request index options state)
  "Return REQUEST's clickable option cells for the question at INDEX.
Cells exist only while the form can still take an answer.  Options pack
across as many Composer rows as needed so a long label is never
ellipsized away."
  (let ((id (plist-get request :id))
        (actionable (memq state '(pending late)))
        (cells nil))
    (cl-loop for option in options
             for number from 1
             for label = (or (dsh-protocol-question-option-label option) "")
             for description = (dsh-protocol-question-option-description option)
             do (push (if actionable
                          (dsh-emacs-interaction--cell
                           (format "%d %s" number label)
                           id (list 'option index number)
                           'dsh-emacs-accent-face
                           (format "%s%s" label
                                   (if (and (stringp description)
                                            (not (string-empty-p description)))
                                       (concat "\n" description)
                                     "")))
                        (format "%d %s" number label))
                      cells))
    (dsh-emacs-interaction--pack-cells (nreverse cells))))

(defun dsh-emacs-interaction--question-hint (request options)
  "Return the how-to-answer row of REQUEST."
  (let ((state (plist-get request :state))
        (multi (dsh-protocol-question-multi-select
                (nth (plist-get request :index)
                     (plist-get request :questions)))))
    (dsh-emacs-interaction--fit
     (concat "   "
             (cond
              ((eq state 'late)
               "Type the answer in the input line, then C-c C-c")
              (multi
               "Click options to stage them, or type numbers/labels, then C-c C-c")
              (options
               "Click an option to answer, or type a number/label/your own answer")
              (t "Type your answer in the input line, then C-c C-c"))
             (cond
              ((not (eq state 'pending)) " · C-c C-k dismisses")
              (options " · empty + C-c C-c skips · C-c C-k declines")
              (t " · empty + C-c C-c skips · C-c C-k declines")))
     'dsh-emacs-meta-face)))

(defun dsh-emacs-interaction--question-form (request)
  "Return REQUEST's question rows."
  (let* ((questions (plist-get request :questions))
         (total (length questions))
         (index (plist-get request :index))
         (state (plist-get request :state))
         (question (nth index questions))
         (lines nil))
    (push (dsh-emacs-interaction--question-title question index total state)
          lines)
    (when question
      (push (dsh-emacs-interaction--wrap
             (or (dsh-protocol-question-text question) ""))
            lines)
      (let ((detail (dsh-protocol-question-detail question)))
        (when (and (stringp detail) (not (string-empty-p detail)))
          (push (dsh-emacs-interaction--wrap detail 'dsh-emacs-meta-face)
                lines)))
      (let ((options (dsh-protocol-question-options question)))
        (when (and options (not (eq state 'sending)))
          (push (dsh-emacs-interaction--options-line request index options state)
                lines))
        (when (memq state '(pending late))
          (push (dsh-emacs-interaction--question-hint request options) lines))))
    (concat (mapconcat #'identity (nreverse lines) "\n") "\n")))

(defun dsh-emacs-interaction--approval-form (request)
  "Return REQUEST's approval rows."
  (let* ((state (plist-get request :state))
         (id (plist-get request :id))
         (tool (plist-get request :tool-name))
         (command (dsh-emacs-interaction--command-line
                   (plist-get request :call-id)))
         (reason (plist-get request :reason))
         (lines (list
                 (dsh-emacs-interaction--fit
                  (concat (if (eq state 'sending) "⏳ " "⚠ ")
                          "Approval · " (or tool "tool"))
                  'dsh-emacs-approval-justification-face))))
    (when (and (stringp command) (not (string-empty-p command)))
      (push (dsh-emacs-interaction--wrap command
                                         'dsh-emacs-approval-command-face)
            lines))
    (when (and (stringp reason) (not (string-empty-p reason)))
      (push (dsh-emacs-interaction--wrap
             reason 'dsh-emacs-approval-justification-face)
            lines))
    (pcase state
      ('pending
       (push (concat "   "
                     (dsh-emacs-interaction--cell
                      "Allow once" id 'allow 'dsh-emacs-accent-face
                      "Allow this tool call once")
                     "   "
                     (dsh-emacs-interaction--cell
                      "Reject" id 'reject
                      'dsh-emacs-approval-justification-face
                      "Reject this tool call"))
             lines)
       (push (dsh-emacs-interaction--fit
              "   C-c C-u a allows once · C-c C-k rejects · RET or mouse-1 on a cell decides"
              'dsh-emacs-meta-face)
             lines))
      ('sending
       (push (dsh-emacs-interaction--fit "   Sending the decision…"
                                         'dsh-emacs-meta-face)
             lines)))
    (concat (mapconcat #'identity (nreverse lines) "\n") "\n")))

(defun dsh-emacs-interaction--queued-text (request)
  "Return REQUEST's one-line queued summary."
  (let ((text
         (pcase (plist-get request :kind)
           ('question
            (let ((questions (plist-get request :questions)))
              (format "%s Question · %s — queued behind the form above"
                      (dsh-emacs-interaction--question-icon
                       'dsh-emacs-meta-face)
                      (or (dsh-protocol-question-header (car questions))
                          (dsh-protocol-question-text (car questions))
                          "asked elsewhere"))))
           ('approval
            (format "⚠ Approval · %s — queued"
                    (or (plist-get request :tool-name)
                        "tool"))))))
    (concat (dsh-emacs-interaction--fit (concat "   " text)
                                        'dsh-emacs-meta-face)
            "\n")))

(defun dsh-emacs-interaction--form-text (request)
  "Return REQUEST's Composer rows."
  (pcase (plist-get request :kind)
    ('question
     (if (eq request (dsh-emacs-interaction--current-question))
         (dsh-emacs-interaction--question-form request)
       (dsh-emacs-interaction--queued-text request)))
    ('approval (dsh-emacs-interaction--approval-form request))))

(defun dsh-emacs-interaction--chrome ()
  "Return (SIG . TEXT) for this buffer's Composer form rows.
TEXT renders the newest pending requests, closest to the input line;
SIG changes whenever a row would repaint.  Composer calls this on every
render, so it must stay cheap and side-effect free."
  (let* ((visible (dsh-emacs-interaction--visible))
         (shown (car visible))
         (elided (cdr visible)))
    (if (null shown)
        (cons nil "")
      (cons
       (list (dsh-emacs-composer--row-width)
             elided
             (mapcar (lambda (request)
                       (list (plist-get request :id)
                             (plist-get request :kind)
                             (plist-get request :state)
                             (plist-get request :index)))
                     shown))
       (concat
        (dsh-emacs-interaction--form-text (car shown))
        (when (> elided 0)
          (concat (dsh-emacs-interaction--fit
                   (format "   %d more pending request(s) in this chat" elided)
                   'dsh-emacs-meta-face)
                  "\n"))
        (mapconcat #'dsh-emacs-interaction--form-text (cdr shown) ""))))))

;;; Activation

(defun dsh-emacs-interaction--event ()
  "Return the mouse event that triggered this command, if any."
  (let ((event last-command-event))
    (when (and (consp event)
               (memq (car event) '(mouse-1 mouse-2)))
      event)))

(defun dsh-emacs-interaction--decide-by-id (id allow)
  "Answer the approval form ID with ALLOW."
  (let ((request (dsh-emacs-interaction--find id)))
    (unless request
      (user-error "That approval is no longer pending"))
    (dsh-emacs-interaction--decide request allow)))

;;;###autoload
(defun dsh-emacs-interaction-activate ()
  "Decide the Composer form cell at point or under the mouse.
A single-select option cell answers immediately; a multi-select option
cell toggles its number in the draft; approval cells allow or reject
at once."
  (interactive)
  (let* ((event (dsh-emacs-interaction--event))
         (pos (if event (dsh-emacs-interaction--event-pos event) (point)))
         (control (dsh-emacs-interaction--control-at pos)))
    (unless control
      (user-error "No pending request cell here"))
    (pcase (cdr control)
      ('allow (dsh-emacs-interaction--decide-by-id (car control) t))
      ('reject (dsh-emacs-interaction--decide-by-id (car control) nil))
      (`(option ,index ,number)
       (dsh-emacs-interaction--stage-option (car control) index number)))))

;;; Submitting

(defun dsh-emacs-interaction--advance (request answer)
  "Record ANSWER for REQUEST's current question.
A batch with more questions keeps the form and asks the next one; the
last answer submits the whole batch as one outcome."
  (setf (plist-get request :answers)
        (cons answer (plist-get request :answers)))
  (let ((next (1+ (plist-get request :index)))
        (total (length (plist-get request :questions))))
    (if (< next total)
        (progn
          (setf (plist-get request :index) next)
          (dsh-emacs-interaction--refresh)
          (message "Answered question %d/%d" next total))
      (dsh-emacs-interaction--send request))))

(defun dsh-emacs-interaction--send (request)
  "Send REQUEST's collected answers to the host."
  (let ((answers (nreverse (plist-get request :answers))))
    (setf (plist-get request :answers) nil
          (plist-get request :state) 'sending)
    (dsh-emacs-interaction--refresh)
    (if (plist-get request :event-id)
        (dsh-emacs-interaction--send-live request answers)
      (dsh-emacs-interaction--send-late request answers))))

(defun dsh-emacs-interaction--send-live (request answers)
  "Answer REQUEST's live waterfall with ANSWERS."
  (let ((count (length answers)))
    (dsh-emacs--events-result-async
     dsh-emacs-events--client-id
     (plist-get request :event-id)
     (dsh-protocol-question-result-outcome answers)
     (lambda (ok value)
       (when (buffer-live-p (plist-get request :chat))
         (with-current-buffer (plist-get request :chat)
           (dsh-emacs-interaction--retire
            request
            (if ok
                (format "Answered %d question(s)" count)
              (format "Question response not accepted (%s)" value)))))))))

(defun dsh-emacs-interaction--send-late (request answers)
  "Submit ANSWERS for REQUEST's timed call through `userQuestions/answer'."
  (let ((count (length answers)))
    (dsh-emacs--rpc-async
     "userQuestions/answer"
     (dsh-protocol-question-late-answer-request
      (plist-get request :session-id)
      (plist-get request :call-id)
      answers)
     (lambda (ok value)
       (when (buffer-live-p (plist-get request :chat))
         (with-current-buffer (plist-get request :chat)
           (cond
            ((not ok)
             (setf (plist-get request :state) 'late)
             (dsh-emacs-interaction--refresh)
             (message "Question answer not accepted (%s)" value))
            ((eq value t)
             (dsh-emacs-interaction--retire
              request (format "Answered %d question(s)" count)))
            (t (dsh-emacs-interaction--retire
                request "Question is no longer waiting for an answer")))))))))

(defun dsh-emacs-interaction--skip ()
  "Answer REQUEST's current question with an empty selection.
This is dsh web's per-question Skip; the remaining questions of the
batch are still asked."
  (let ((request (dsh-emacs-interaction--current-question)))
    (unless request
      (user-error "No pending question in this buffer"))
    (when (eq (plist-get request :state) 'sending)
      (user-error "This answer is being sent already"))
    (let ((question (nth (plist-get request :index)
                         (plist-get request :questions))))
      (dsh-emacs--clear-input)
      (dsh-emacs-interaction--advance
       request (dsh-emacs-interaction--make-answer question "")))))

(defun dsh-emacs-interaction--submit-pending ()
  "Answer the input line's question form with the draft text.
Return non-nil when the input was consumed.  Returns nil when no
question form owns the input line, so `dsh-emacs-send-or-stop' still
sends the draft.  Approvals are decided by a cell, not by text: with one
pending and an empty draft the send key explains its keys instead of
posting an empty message."
  (when (derived-mode-p 'dsh-emacs-mode)
    (let ((request (dsh-emacs-interaction--current-question)))
      (cond
       ((null request)
        (when (and (dsh-emacs-interaction--current-approval)
                   (string-empty-p
                    (string-trim (dsh-emacs-interaction--input-text))))
          (user-error
           "Pending approval: C-c C-u a allows once, C-c C-k rejects")))
       ((memq (plist-get request :state) '(pending late))
        (let* ((index (plist-get request :index))
               (question (nth index (plist-get request :questions)))
               (answer (dsh-emacs-interaction--make-answer
                        question (dsh-emacs-interaction--input-text))))
          (dsh-emacs--clear-input)
          (dsh-emacs-interaction--advance request answer)
          t))))))

;;; Decisions

(defun dsh-emacs-interaction--abandon (request)
  "Answer REQUEST's question waterfall as abandoned by the user.
The outcome is `rejected' with a cancel error body, so the host aborts
the ask tool call instead of staying blocked on it."
  (if (plist-get request :event-id)
      (progn
        (setf (plist-get request :state) 'sending)
        (dsh-emacs-interaction--refresh)
        (dsh-emacs--events-result-async
         dsh-emacs-events--client-id
         (plist-get request :event-id)
         (dsh-protocol-events-cancelled-outcome "User abandoned the questions")
         (lambda (ok value)
           (when (buffer-live-p (plist-get request :chat))
             (with-current-buffer (plist-get request :chat)
               (dsh-emacs-interaction--retire
                request
                (if ok
                    "Question cancelled"
                  (format "Question response not accepted (%s)" value))))))))
    ;; A late form has no waterfall left to abandon: dismissing it is local.
    (dsh-emacs-interaction--retire request "Late question dismissed")))

(defun dsh-emacs-interaction--decide (request allow)
  "Answer approval REQUEST with ALLOW."
  (unless (eq (plist-get request :state) 'pending)
    (user-error "This approval is being sent already"))
  (setf (plist-get request :state) 'sending)
  (dsh-emacs-interaction--refresh)
  (let ((tool (plist-get request :tool-name)))
    (dsh-emacs--events-result-async
     dsh-emacs-events--client-id
     (plist-get request :event-id)
     (dsh-protocol-approval-outcome allow)
     (lambda (ok value)
       (when (buffer-live-p (plist-get request :chat))
         (with-current-buffer (plist-get request :chat)
           (dsh-emacs-interaction--retire
            request
            (if ok
                (format "%s %s" (if allow "Allowed" "Rejected")
                        (or tool "the tool call"))
              (format "Approval response not accepted (%s)" value)))))))))

;;; Approval helpers

(defun dsh-emacs-interaction--approval-reason (request)
  "Return REQUEST's reason in `dsh-emacs-approval-language' when available."
  (let ((reasons (dsh-protocol-approval-request-display-reasons request)))
    (or (let* ((language (or (bound-and-true-p dsh-emacs-approval-language)
                             (getenv "LC_ALL")
                             (getenv "LC_MESSAGES")
                             (getenv "LANG")
                             "en"))
               (tag (downcase (car (split-string language "[-_.@]"))))
               (tag (replace-regexp-in-string "_" "-" tag))
               (localized (cdr (assoc tag reasons))))
          (and (stringp localized) localized))
        (dsh-protocol-approval-request-reason request))))

(defun dsh-emacs-interaction--command-line (call-id)
  "Return CALL-ID's command line from the transcript's tool state, if any.
Bash calls render their body as `$ command'; other tools fall back to
`title — args'."
  (when (and (stringp call-id)
             (boundp 'dsh-emacs--tool-states)
             (hash-table-p dsh-emacs--tool-states))
    (let* ((state (dsh-emacs-render--tool-state call-id))
           (title (plist-get state :title))
           (args (plist-get state :args)))
      (cond
       ((and (stringp args) (string-prefix-p "$ " args)) args)
       ((and title args) (format "%s — %s" title args))
       (t (or title args))))))

;;; Arrival

(defun dsh-emacs-interaction--notify-question (request)
  "Post the desktop notice announcing REQUEST's questions."
  (when-let* ((chat (plist-get request :chat)))
    (let* ((questions (plist-get request :questions))
           (first (and questions (dsh-protocol-question-text (car questions))))
           (count (length questions)))
      (dsh-emacs-notify--post
       (plist-get request :session-id)
       (format "Question%s%s"
               (if (and (stringp first) (not (string-empty-p first)))
                   (format ": %s" first)
                 "")
               (if (> count 1) (format " (+%d more)" (1- count)) ""))
       chat))))

(cl-defun dsh-emacs-interaction--question-requested
    (chat event-id session-id questions &optional wait)
  "Render a `user-questions/request' waterfall in CHAT as a Composer form.
EVENT-ID is the waterfall to answer, QUESTIONS its decoded
`dsh-protocol-question' values, and WAIT the optional timed call whose
window the form keeps open.  Requires a live CHAT and an EVENT-ID: without
either this client is not the waterfall's claimant, and the dispatcher
hands the frame on instead.  A replayed already-retired event-id is
ignored."
  (when (and (buffer-live-p chat) event-id
             (not (member event-id dsh-emacs-interaction--retired))
             (not (dsh-emacs-interaction--find event-id)))
    (with-current-buffer chat
      (let* ((questions
              (mapcar
               (lambda (question)
                 (dsh-protocol--struct #'dsh-protocol-question-p
                                      #'dsh-protocol-question--from-alist
                                      question))
               (append questions nil)))
             (call-id (or (and wait (dsh-protocol-question-wait-call-id wait))
                          (and questions (dsh-protocol-question-call-id
                                          (car questions))))))
        (unless (and call-id
                     (dsh-emacs-interaction--request-for-call call-id))
          (let ((request (dsh-emacs-interaction--make-request
                       :kind 'question :id event-id :event-id event-id
                       :session-id session-id :chat chat
                       :questions questions :index 0 :answers nil
                         :wait wait :call-id call-id :state 'pending)))
            (setq dsh-emacs-interaction--requests
                  (nconc dsh-emacs-interaction--requests (list request)))
            (dsh-emacs-interaction--claim request chat session-id wait)
            (dsh-emacs-interaction--refresh)
            (dsh-emacs-interaction--notify-question request)))))))

;;; Approval arrival

(cl-defun dsh-emacs-interaction--approval-requested
    (chat event-id session-id approval)
  "Render an `approval/request' waterfall in CHAT as a Composer form.
APPROVAL is the decoded `dsh-protocol-approval-request'."
  (when (and (buffer-live-p chat) event-id
             (not (member event-id dsh-emacs-interaction--retired))
             (not (dsh-emacs-interaction--find event-id)))
    (with-current-buffer chat
      (let* ((tool-name (dsh-protocol-approval-request-tool-name approval))
             (reason (dsh-emacs-interaction--approval-reason approval))
             (call-id (dsh-protocol-approval-request-call-id approval)))
        (unless (and call-id
                     (dsh-emacs-interaction--request-for-call call-id))
          (let ((request (dsh-emacs-interaction--make-request
                       :kind 'approval :id event-id :event-id event-id
                       :session-id session-id :chat chat
                         :tool-name tool-name :reason reason
                         :call-id call-id :state 'pending)))
            (setq dsh-emacs-interaction--requests
                  (nconc dsh-emacs-interaction--requests (list request)))
            (dsh-emacs-interaction--refresh)
            (let ((detail (or (dsh-emacs-interaction--command-line call-id)
                              reason tool-name)))
              (dsh-emacs-notify--post
               session-id
               (format "Approval%s"
                       (if detail (format ": %s" detail) ""))
               chat))))))))

;;; Lifecycle

(defun dsh-emacs-interaction--withdrawn (event-id)
  "Retire any pending form for waterfall EVENT-ID.
The host cancels a waterfall when the turn ends or when a timed question's
window closes.  A question form whose timed call outlives its window
becomes a late form (`userQuestions/answer' instead of an outcome), so the
question is not lost; anything else is retired.  The event id joins the
retired set so a replay cannot reopen it."
  (dsh-emacs-plan--cancel event-id)
  (when (and (boundp 'dsh-emacs--chat-buffers)
             (hash-table-p dsh-emacs--chat-buffers))
    (maphash
     (lambda (_session-id chat)
       (when (buffer-live-p chat)
         (with-current-buffer chat
           (when-let* ((request (dsh-emacs-interaction--find event-id)))
             (if (and (eq (plist-get request :kind) 'question)
                      (plist-get request :call-id)
                      (plist-get request :wait))
                 (progn
                   ;; The foreground window is gone; release its claim and
                   ;; keep the form, re-keyed to the call for a late answer.
                   (dsh-emacs-interaction--release request)
                   (dsh-emacs-interaction--remember-retired event-id)
                   (setf (plist-get request :event-id) nil
                         (plist-get request :wait) nil
                         (plist-get request :state) 'late
                         (plist-get request :id)
                         (concat "call:" (plist-get request :call-id)))
                   (dsh-emacs-interaction--refresh)
                   (message "Timed question closed — C-c C-c answers it late"))
               (dsh-emacs-interaction--retire
                request "Request was withdrawn"))))))
     dsh-emacs--chat-buffers)))

(defun dsh-emacs-interaction--questions-projected (questions)
  "Merge the decoded `userQuestions' projection QUESTIONS into this chat.
The projection is the source of truth for timed questions: settled calls
complete their transcript card and retire any form, and `continued' calls
with no live form become late forms.  A nil projection resets the mirror
on a new host generation and drops stale late forms; live waterfall
forms are retired by `dsh-emacs-interaction--generation-retired'."
  (if (null questions)
      (progn
        (setq dsh-emacs-interaction--session-questions nil)
        (dolist (request (copy-sequence dsh-emacs-interaction--requests))
          (when (eq (plist-get request :state) 'late)
            (dsh-emacs-interaction--retire request))))
    (let ((seq (dsh-protocol-user-questions-seq questions))
          (previous (and dsh-emacs-interaction--session-questions
                         (dsh-protocol-user-questions-seq
                          dsh-emacs-interaction--session-questions))))
      (when (or (not (integerp seq)) (not (integerp previous))
                (>= seq previous))
        (setq dsh-emacs-interaction--session-questions questions)
        (dolist (settled (dsh-protocol-user-questions-settled questions))
          (let ((call-id (dsh-protocol-settled-question-call-id settled)))
            (dsh-emacs-render-question-settled
             call-id
             (dsh-protocol-question-answers-json
              (dsh-protocol-settled-question-answers settled)))
            (when-let* ((request (dsh-emacs-interaction--request-for-call call-id)))
              ;; An in-flight answer owns its form until its callback runs.
              (unless (eq (plist-get request :state) 'sending)
                (dsh-emacs-interaction--retire
                 request "Question settled")))))
        (dolist (call (dsh-emacs-interaction--continued-calls))
          (unless (dsh-emacs-interaction--request-for-call
                   (dsh-protocol-pending-question-call-id call))
            (dsh-emacs-interaction--materialize-late (list call))))))))

(defun dsh-emacs-interaction--generation-retired ()
  "Retire every pending form of the previous `$events' generation.
Each reconnect mints a new client id; outcomes posted with it for old
event ids are no-ops, so keeping the forms would strand the user."
  (dsh-emacs-plan--cancel)
  (let ((count 0))
    (when (and (boundp 'dsh-emacs--chat-buffers)
               (hash-table-p dsh-emacs--chat-buffers))
      (maphash
       (lambda (_session-id chat)
         (when (buffer-live-p chat)
           (with-current-buffer chat
             (setq count (+ count (length dsh-emacs-interaction--requests)))
             (dolist (request dsh-emacs-interaction--requests)
               (dsh-emacs-interaction--release request)
               (dsh-emacs-interaction--remember-retired
                (or (plist-get request :event-id)
                    (plist-get request :id))))
             (setq dsh-emacs-interaction--requests nil)
             (dsh-emacs-interaction--refresh))))
       dsh-emacs--chat-buffers))
    (when (> count 0)
      (message "dsh: reconnected — %d pending request(s) retired" count))))

(defun dsh-emacs-interaction--chat-closed ()
  "Hand this chat's live waterfalls back to the host before closing.
A dead buffer can never answer, so each live form is answered with
outcome `next' (another client may claim it) instead of blocking the
host until the session ends."
  (dolist (request dsh-emacs-interaction--requests)
    (dsh-emacs-interaction--release request)
    (when-let* ((event-id (plist-get request :event-id))
                (client-id (and (boundp 'dsh-emacs-events--client-id)
                                dsh-emacs-events--client-id)))
      (dsh-emacs--events-result-async
       client-id event-id (dsh-protocol-events-next-outcome)
       (lambda (_ok _value) nil))))
  (setq dsh-emacs-interaction--requests nil
        dsh-emacs-interaction--session-questions nil))

(defun dsh-emacs-interaction--pending-p ()
  "Return non-nil when any chat buffer holds an unanswered form.
Reloading the package with live waterfalls would strand the host."
  (and (boundp 'dsh-emacs--chat-buffers)
       (hash-table-p dsh-emacs--chat-buffers)
       (catch 'pending
         (maphash
          (lambda (_session-id chat)
            (when (and (buffer-live-p chat)
                       (buffer-local-value 'dsh-emacs-interaction--requests chat))
              (throw 'pending t)))
          dsh-emacs--chat-buffers)
         nil)))

;;; Late answers

(defun dsh-emacs-interaction--continued-calls ()
  "Return this session's still-answerable `continued' timed calls."
  (let ((view dsh-emacs-interaction--session-questions))
    (when view
      (cl-remove-if-not
       (lambda (call)
         (eq 'continued (dsh-protocol-pending-question-state call)))
       (dsh-protocol-user-questions-active view)))))

(defun dsh-emacs-interaction--materialize-late (calls)
  "Render CALLS (`continued' projection entries) as late question forms."
  (dolist (call calls)
    (let* ((call-id (dsh-protocol-pending-question-call-id call))
           (id (concat "call:" (or call-id ""))))
      (unless (or (dsh-emacs-interaction--find id)
                  (dsh-emacs-interaction--request-for-call call-id)
                  (member id dsh-emacs-interaction--retired))
        (setq dsh-emacs-interaction--requests
              (nconc dsh-emacs-interaction--requests
                     (list (dsh-emacs-interaction--make-request
                            :kind 'question :id id :event-id nil
                            :session-id (and (boundp 'dsh-emacs--buffer-session)
                                             dsh-emacs--buffer-session)
                            :chat (current-buffer)
                            :questions (append (dsh-protocol-pending-question-questions
                                                call)
                                               nil)
                            :index 0 :answers nil
                            :call-id call-id :state 'late))))))
    (dsh-emacs-interaction--refresh)))

;;; Commands

;;;###autoload
(defun dsh-emacs-interaction-decline ()
  "Decline the pending request of this chat that owns the input line.
With no question form current, the oldest pending request (typically an
approval) is declined.
A question batch is abandoned as a whole with outcome `rejected', the
same signal dsh web's \"leave this question\" produces, so the host's ask
aborts instead of staying blocked.  An approval is rejected.  A late
question form is simply dismissed."
  (interactive)
  (let ((request (or (dsh-emacs-interaction--current-question)
                     (dsh-emacs-interaction--oldest))))
    (unless request
      (user-error "No pending request in this buffer"))
    (pcase (plist-get request :kind)
      ('question (dsh-emacs-interaction--abandon request))
      ('approval (dsh-emacs-interaction--decide request nil)))))

;;;###autoload
(defun dsh-emacs-interaction-allow ()
  "Allow the oldest pending approval of this chat once."
  (interactive)
  (let ((request (dsh-emacs-interaction--current-approval)))
    (unless request
      (user-error "No pending approval in this buffer"))
    (dsh-emacs-interaction--decide request t)))

;;;###autoload
(defun dsh-emacs-interaction-skip ()
  "Skip the current question with an empty answer.
The remaining questions of the batch are still asked; the host records
an empty selection for this one (dsh web's per-question Skip)."
  (interactive)
  (dsh-emacs-interaction--skip))

;;;###autoload
(defun dsh-emacs-interaction-focus ()
  "Move point to this chat's input line, where the form is answered."
  (interactive)
  (unless (and (boundp 'dsh-emacs--input-marker)
               (markerp dsh-emacs--input-marker)
               (eq (marker-buffer dsh-emacs--input-marker) (current-buffer)))
    (user-error "Not in a dsh chat buffer"))
  (goto-char (dsh-emacs--input-end))
  (unless (pos-visible-in-window-p (point))
    (recenter -1))
  (when (dsh-emacs-interaction--current-question)
    (message "Answer in the input line, then C-c C-c")))

;;;###autoload
(defun dsh-emacs-answer-question ()
  "Answer a timed `ask_user_question' whose foreground window has closed.
A timed question the user did not answer before its window expired stays
answerable (dsh 0.2.0).  This command renders each still-`continued' call
of the session's `userQuestions' projection as a late form in the
Composer: type the answer in the input line and `C-c C-c' submits it
through `userQuestions/answer'; the host steers it into the agent as a
late reply.  `C-c C-k' dismisses a late form.  Reports instead of
rendering when nothing is waiting."
  (interactive)
  (dsh-emacs-subagent-require 'mutate)
  (let ((session-id (and (boundp 'dsh-emacs--buffer-session)
                         dsh-emacs--buffer-session))
        (calls (dsh-emacs-interaction--continued-calls)))
    (unless session-id
      (user-error "Not in a dsh chat buffer"))
    (unless calls
      (user-error "No question is waiting for a later answer"))
    (dsh-emacs-interaction--materialize-late calls)
    (dsh-emacs-interaction-focus)
    (message "Answer the late question%s in the input line, then C-c C-c"
             (if (> (length calls) 1) "s" ""))))

(defvar dsh-emacs-interaction-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'dsh-emacs-interaction-allow)
    (define-key map (kbd "d") #'dsh-emacs-interaction-decline)
    (define-key map (kbd "s") #'dsh-emacs-interaction-skip)
    (define-key map (kbd "f") #'dsh-emacs-interaction-focus)
    map)
  "Keymap for pending questions and approvals.
Bound under `C-c C-u': `a' allows the oldest approval once, `d' declines
the oldest request, `s' skips the current question, and `f' focuses the
input line. `C-c C-k' and `C-c C-p' remain direct aliases for decline
and focus.")

(provide 'dsh-emacs-interaction)
;;; dsh-emacs-interaction.el ends here

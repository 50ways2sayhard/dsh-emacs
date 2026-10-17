;;; dsh-test-completion.el --- Completion tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)

(defvar corfu-auto)
(defvar corfu-auto-trigger)

;; --- Test 99b: one slash menu lists commands and skills ---
;; A skill pick inserts the /name gesture (the host expands it from the prompt
;; text); the command and skill catalogs share the candidate list, commands
;; first, with user-only skills marked.
(ert-deftest dsh-emacs-test-completion-slash-menu-lists-commands-and-skills ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-slash-menu*"))
        (old-commands dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs)
        (rows nil)
        (dsh-emacs--current-session "sess-slash-menu"))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-command--cache-catalog
           "sess-slash-menu"
           (list (dsh-protocol-command--from-alist
                  '((name . "compact") (description . "Compact history")))))
          (dsh-emacs-skill--cache-catalog
           "sess-slash-menu"
           (list (dsh-protocol-skill--from-alist
                  '((name . "review") (description . "Review a diff")
                    (modelInvocable . t)))
                 (dsh-protocol-skill--from-alist
                  '((name . "notes") (description . "Private notes")
                    (modelInvocable . :json-false)))))
          (goto-char dsh-emacs--input-marker)
          (insert "/rev")
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt collection &rest _)
                       (setq rows (mapcar (lambda (c)
                                            (get-text-property 0 'display (car c)))
                                          collection))
                       "/review")))
            (dsh-emacs-command)
            (ert-info ((format "%s" "slash-menu-lists-commands-and-skills"))
              (should (equal '("/compact — Compact history"
                               "/review — Review a diff"
                               "/notes — user-only · Private notes")
                             rows))
              (should (string= "/review "
                               (buffer-substring-no-properties
                                dsh-emacs--input-marker (point-max))))
              (should (= (point) (point-max))))))
      (setq dsh-emacs--command-catalogs old-commands
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; A command pick still runs through commands/execute, with the prefix
;; argument ignored (it only means "open the file" for a skill)
(ert-deftest dsh-emacs-test-completion-slash-menu-prefix-ignored-for-command ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-slash-menu-cmd*"))
        (old-commands dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs)
        (calls nil)
        (dsh-emacs--current-session "sess-slash-menu-cmd"))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-command--cache-catalog
           "sess-slash-menu-cmd"
           (list (dsh-protocol-command--from-alist
                  '((name . "compact") (description . "Compact history")))))
          (dsh-emacs-skill--cache-catalog "sess-slash-menu-cmd" nil)
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _) "/compact"))
                    ((symbol-function 'dsh-emacs--rpc-async)
                     (lambda (method params cb)
                       (push (list method params) calls)
                       (funcall cb t '((commandId . "c1")
                                       (result . ((kind . "success")
                                                  (text . "t"))))))))
            (dsh-emacs-command t)
            (ert-info ((format "%s" "slash-menu-prefix-ignored-for-command"))
              (should (string= "commands/execute" (car (car calls))))
              (should (string= "/compact" (cdr (assq 'line (cadr (car calls)))))))))
      (setq dsh-emacs--command-catalogs old-commands
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; With a prefix argument a picked skill opens its SKILL.md instead of
;; inserting the gesture
(ert-deftest dsh-emacs-test-completion-slash-menu-prefix-opens-skill-file ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-slash-menu-open*"))
        (dsh-emacs--command-catalogs nil)
        (dsh-emacs--skill-catalogs nil)
        (requests nil)
        (opened nil)
        (dsh-emacs--current-session "sess-slash-menu-open"))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-command--cache-catalog "sess-slash-menu-open" nil)
          (dsh-emacs-skill--cache-catalog
           "sess-slash-menu-open"
           (list (dsh-protocol-skill--from-alist
                  '((name . "review") (description . "R")
                    (modelInvocable . t)
                    (path . "/tmp/skills/review/SKILL.md")))))
          (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                     (lambda (method _params)
                       (push method requests)
                       '(t)))
                    ((symbol-function 'completing-read)
                     (lambda (&rest _) "/review"))
                    ((symbol-function 'find-file)
                     (lambda (path &rest _) (setq opened path))))
            (dsh-emacs-command t)
            (ert-info ((format "%s" "slash-menu-prefix-opens-skill-file"))
              (should (equal requests '("commands/list")))
              (should (equal "/tmp/skills/review/SKILL.md" opened)))))
      (kill-buffer buf))))

;; A provider that ships no file must say so instead of opening nothing
(ert-deftest dsh-emacs-test-completion-skill-open-without-path-signals ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "skill-open-without-path-signals"))
    (should (condition-case nil
                (progn (dsh-emacs-skill-open
                        (dsh-protocol-skill--from-alist '((name . "no-file"))))
                       nil)
              (user-error t)))))

;; The gesture insert belongs to a chat buffer
(ert-deftest dsh-emacs-test-completion-slash-gesture-insert-needs-chat-buffer ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "slash-gesture-insert-needs-chat-buffer"))
    (should (condition-case nil
                (with-temp-buffer (dsh-emacs-command--insert-gesture "review") nil)
              (user-error t)))))

;; The host only recognizes the gesture at the start of the message or after
;; whitespace (`(^|\s)/name'), so a gesture inserted right after a word needs a
;; leading space to be invocable — otherwise the prompt looks right and the
;; skill silently never fires
(ert-deftest dsh-emacs-test-completion-slash-gesture-adds-word-boundary ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-gesture-boundary*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char dsh-emacs--input-marker)
          (insert "seed the")
          (dsh-emacs-command--insert-gesture "review")
          (ert-info ((format "%s" "slash-gesture-adds-word-boundary"))
            (should (string= "seed the /review "
                             (buffer-substring-no-properties
                              dsh-emacs--input-marker (point-max)))))
          ;; at the input start the message itself begins with the gesture, so
          ;; no leading space is added
          (delete-region dsh-emacs--input-marker (point-max))
          (dsh-emacs-command--insert-gesture "review")
          (ert-info ((format "%s" "slash-gesture-no-space-at-input-start"))
            (should (string= "/review "
                             (buffer-substring-no-properties
                              dsh-emacs--input-marker (point-max)))))
          ;; The token being typed is what the insert replaces, wherever it is:
          ;; a mid-sentence `/rev' becomes `/review ', it is not appended to
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "seed the /rev")
          (dsh-emacs-command--insert-gesture "review")
          (ert-info ((format "%s" "slash-gesture-replaces-mid-sentence-token"))
            (should (string= "seed the /review "
                             (buffer-substring-no-properties
                              dsh-emacs--input-marker (point-max))))))
      (kill-buffer buf))))

;; --- Test 99c: /name gestures are chipped in the transcript ---
;; A slash token is chipped only when a cached catalog confirms it: the chip
;; says command (blue) vs skill (violet) and the tooltip carries the
;; description.  Paths, fractions, unknown names and punctuation-suffixed
;; prose stay plain — the host's own gesture scan would not match them either.
(ert-deftest dsh-emacs-test-completion-slash-gesture-chips-catalog-confirmed ()
  :tags '(dsh-unit)
  (let ((old-commands dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs)
        (sid "sess-gesture"))
    (unwind-protect
        (progn
          (dsh-emacs-command--cache-catalog
           sid (list (dsh-protocol-command--from-alist
                      '((name . "goal") (description . "goal ops")))))
          (dsh-emacs-skill--cache-catalog
           sid (list (dsh-protocol-skill--from-alist
                      '((name . "review") (description . "Review it")
                        (modelInvocable . t)))
                     (dsh-protocol-skill--from-alist
                      '((name . "notes") (description . "Private")
                        (modelInvocable . :json-false)))))
          (let* ((dsh-emacs--buffer-session sid)
                 (dsh-emacs--current-session sid)
                 (out (dsh-emacs-command-fontify-gestures
                       "please /review and /goal and /notes but not /usr/bin, 5/8, /nope or /goal,"))
                 (skill-pos (string-match "/review" out))
                 (command-pos (string-match "/goal" out))
                 (user-only-pos (string-match "/notes" out)))
            (ert-info ((format "%s" "slash-gesture-chips-catalog-confirmed"))
              (should (eq 'dsh-emacs-slash-skill-face
                          (get-text-property skill-pos 'face out)))
              (should (eq 'dsh-emacs-slash-command-face
                          (get-text-property command-pos 'face out)))
              (should (string= "Skill /review — Review it"
                               (get-text-property skill-pos 'help-echo out)))
              (should (string= "Slash command /goal — goal ops"
                               (get-text-property command-pos 'help-echo out)))
              (should (string= "Skill /notes — user-only · Private"
                               (get-text-property user-only-pos 'help-echo out)))
              (should (string= "review"
                               (get-text-property skill-pos
                                                  'dsh-emacs-slash-gesture out))))
            (ert-info ((format "%s" "slash-gesture-leaves-non-gestures-plain"))
              (should (null (get-text-property (string-match "/usr/bin" out)
                                               'dsh-emacs-slash-gesture out)))
              (should (null (get-text-property (string-match "5/8" out)
                                               'dsh-emacs-slash-gesture out)))
              (should (null (get-text-property (string-match "/nope" out)
                                               'dsh-emacs-slash-gesture out)))
              (should (null (get-text-property (1+ (string-match "/goal," out))
                                               'dsh-emacs-slash-gesture out)))))
          ;; A render path must never fetch: an unknown session stays plain
          ;; instead of blocking on the network.
          (let ((dsh-emacs--buffer-session "sess-gesture-cold")
                (dsh-emacs--current-session "sess-gesture-cold")
                (calls nil))
            (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                       (lambda (&rest _) (push 'sync calls) (cons nil nil)))
                      ((symbol-function 'dsh-emacs--rpc-async)
                       (lambda (&rest _) (push 'async calls))))
              (let ((out (dsh-emacs-command-fontify-gestures "try /review now")))
                (ert-info ((format "%s" "slash-gesture-render-never-fetches"))
                  (should (null calls))
                  (should (null (get-text-property (string-match "/review" out)
                                                   'dsh-emacs-slash-gesture out))))))))
      (setq dsh-emacs--command-catalogs old-commands
            dsh-emacs--skill-catalogs old-skills))))

;; The renderer chips the gesture of a user message, and the hidden
;; `skill-invocation' copy the host appends for a scanned gesture chips it
;; retroactively — the case that matters when a replayed transcript renders
;; before the skill catalog is fetched.  A richer catalog tooltip already on
;; the token survives the evidence pass.
(ert-deftest dsh-emacs-test-completion-render-chips-catalog-confirmed-gesture ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-gesture-render*"))
        (old-commands dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-modeline-setup)
          (setq-local dsh-emacs--buffer-session "sess-gesture-render")
          (dsh-emacs-skill--cache-catalog
           "sess-gesture-render"
           (list (dsh-protocol-skill--from-alist
                  '((name . "probe") (description . "Probe it")
                    (modelInvocable . t)))))
          (dsh-emacs-render-event
           '((type . "user/message") (seq . 1)
             (data . ((content . [((type . "text")
                                   (text . "run /probe and /cold-skill now"))])))))
          (let ((probe-pos (save-excursion
                             (goto-char (point-min))
                             (search-forward "/probe" nil t)
                             (- (point) 6)))
                (cold-pos (save-excursion
                            (goto-char (point-min))
                            (search-forward "/cold-skill" nil t)
                            (- (point) 11))))
            (ert-info ((format "%s" "render-chips-catalog-confirmed-gesture"))
              (should (memq 'dsh-emacs-slash-skill-face (dsh-test--faces-at probe-pos)))
              (should (string= "Skill /probe — Probe it"
                               (get-text-property probe-pos 'help-echo))))
            ;; unknown to every cache at render time: plain until told otherwise
            (ert-info ((format "%s" "render-leaves-unconfirmed-gesture-plain"))
              (should (null (memq 'dsh-emacs-slash-skill-face (dsh-test--faces-at cold-pos)))))
            ;; the host's injection is hidden, and chips the scanned gesture
            (dsh-emacs-render-event
             '((type . "user/message") (seq . 2)
               (data . ((content . [((type . "text") (text . "<skill_instructions…"))])
                        (source . ((kind . "skill-invocation")
                                   (name . "cold-skill")))))))
            (ert-info ((format "%s" "skill-invocation-hidden-and-chips-retroactively"))
              (should (memq 'dsh-emacs-slash-skill-face (dsh-test--faces-at cold-pos)))
              (should (string= "Skill /cold-skill"
                               (get-text-property cold-pos 'help-echo)))
              (should (null (string-match-p "skill_instructions"
                                            (buffer-substring-no-properties
                                             (point-min) dsh-emacs--input-marker)))))
            ;; an evidence pass over an already-chipped token keeps the richer
            ;; catalog tooltip
            (dsh-emacs-render-event
             '((type . "user/message") (seq . 3)
               (data . ((content . [((type . "text") (text . "<skill_instructions…"))])
                        (source . ((kind . "skill-invocation")
                                   (name . "probe")))))))
            (ert-info ((format "%s" "skill-invocation-keeps-catalog-tooltip"))
              (should (string= "Skill /probe — Probe it"
                               (get-text-property probe-pos 'help-echo))))))
      (setq dsh-emacs--command-catalogs old-commands
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; Host skill evidence wins over a same-named command, with or without a
;; cached skill catalog.  Digit-leading names follow both render paths too.
(ert-deftest dsh-emacs-test-completion-digit-leading-skill-styled-from-catalog ()
  :tags '(dsh-unit)
  (dolist (name '("plan" "3d-review"))
    (dolist (cached '(nil t))
      (let ((dsh-emacs--command-catalogs nil)
            (dsh-emacs--skill-catalogs nil)
            (sid "sess-gesture-evidence"))
        (with-temp-buffer
          (dsh-emacs-mode)
          (setq-local dsh-emacs--buffer-session sid)
          (dsh-emacs-command--cache-catalog
           sid (mapcar #'dsh-protocol-command--from-alist
                       '(((name . "plan") (description . "Plan command"))
                         ((name . "goal") (description . "Goal command")))))
          (when cached
            (dsh-emacs-skill--cache-catalog
             sid (list (dsh-protocol-skill--from-alist
                        `((name . ,name) (description . "Review skill")
                          (modelInvocable . t))))))
          (dsh-emacs-render-event
           `((type . "user/message") (seq . 1)
             (data . ((content . [((type . "text")
                                   (text . ,(format "please /%s and /goal" name)))])))))
          (goto-char (point-min))
          (search-forward (concat "/" name))
          (let* ((start (match-beginning 0))
                 (end (point))
                 (text (buffer-string))
                 (help (if cached
                           (format "Skill /%s — Review skill" name)
                         (format "Skill /%s" name))))
            (when (and cached (equal name "3d-review"))
              (ert-info ((format "%s" "digit-leading-skill-styled-from-catalog"))
                (should (memq 'dsh-emacs-slash-skill-face (dsh-test--faces-at start)))
                (should (equal help (get-text-property start 'help-echo)))))
            (dotimes (repeat 2)
              (dsh-emacs-render-event
               `((type . "user/message") (seq . ,(+ repeat 2))
                 (data . ((content . [((type . "text")
                                       (text . "hidden skill instructions"))])
                          (source . ((kind . "skill-invocation")
                                     (name . ,name)))))))
              (ert-info ((format "%s" (format "skill-evidence-%s-cached-%s-repeat-%d" name cached repeat)))
                (should (cl-loop for pos from start below end
                                 always (and
                                         (equal (dsh-test--faces-at pos)
                                                '(dsh-emacs-slash-skill-face
                                                  dsh-emacs-user-block-face))
                                         (equal name (get-text-property
                                                      pos 'dsh-emacs-slash-gesture))
                                         (equal help (get-text-property pos 'help-echo)))))
                (should (equal text (buffer-string)))
                (should (save-excursion
                          (goto-char end)
                          (search-forward "/goal")
                          (equal (dsh-test--faces-at (match-beginning 0))
                                 '(dsh-emacs-slash-command-face
                                   dsh-emacs-user-block-face)))))
              ;; A repeated injection must keep the tooltip even if the
              ;; catalog has since been invalidated.
              (setq dsh-emacs--skill-catalogs nil))))))))

;; --- Test 100: input area /name completion (commands + skills) ---
(ert-deftest dsh-emacs-test-completion-command-capf-bare-slash-lists-commands-and-skills ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-capf*"))
        (old dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-command--cache-catalog
           "sess-cap"
           (list (dsh-protocol-command--from-alist
                  '((name . "goal") (description . "d")))
                 (dsh-protocol-command--from-alist
                  '((name . "compact") (description . "d")))))
          (dsh-emacs-skill--cache-catalog
           "sess-cap"
           (list (dsh-protocol-skill--from-alist
                  '((name . "review") (description . "Review a diff")
                    (modelInvocable . t)))
                 (dsh-protocol-skill--from-alist
                  '((name . "notes") (description . "Private notes")
                    (modelInvocable . :json-false)))))
          (setq dsh-emacs--current-session "sess-cap")
          ;; A bare "/" also returns the whole directory (web's trigger behavior);
          ;; the skill catalog rides the same list, user-only skills marked
          (goto-char dsh-emacs--input-marker)
          (insert "/")
          (let* ((comp (dsh-emacs-command-completion-at-point))
                 (cands (dsh-test-completion-items (nth 2 comp)))
                 (ann (plist-get (nthcdr 3 comp) :annotation-function)))
            (ert-info ((format "%s" "command-capf-bare-slash-lists-commands-and-skills"))
              (should (and comp
                           (member "/goal" cands)
                           (member "/compact" cands)
                           (member "/review" cands)
                           (member "/notes" cands))))
            (ert-info ((format "%s" "command-capf-marks-user-only-skill"))
              (should (and (functionp ann)
                           (string= "Review a diff" (funcall ann "/review"))
                           (string= "user-only · Private notes" (funcall ann "/notes"))))))
          ;; After clearing, the "/go" prefix still returns all candidates
          ;; (filtering is left to the completion framework)
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "/go")
          (let* ((comp (dsh-emacs-command-completion-at-point))
                 (cands (dsh-test-completion-items (nth 2 comp))))
            (ert-info ((format "%s" "command-capf-completes-prefix"))
              (should (and comp
                           (member "/goal" cands)
                           (member "/compact" cands)))))
          (goto-char dsh-emacs--input-marker)
          (insert "/goal ")
          (ert-info ((format "%s" "command-capf-off-after-space"))
            (should (null (dsh-emacs-command-completion-at-point))))
          (goto-char (point-min))
          (ert-info ((format "%s" "command-capf-off-in-transcript"))
            (should (null (dsh-emacs-command-completion-at-point)))))
      (setq dsh-emacs--command-catalogs old
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; --- Test 100b: the /name token completes mid-sentence too ---
;; The host's gesture grammar accepts `/name' after any whitespace, not only at
;; the start of the message, so completion follows it: the slash token ending at
;; point completes in place.  Mid-sentence the source is catalog-confirmed — a
;; name no catalog has (`see /usr') is prose or a path and stays out of the way
;; of path and word completion.
(ert-deftest dsh-emacs-test-completion-command-capf-completes-mid-sentence-token ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-capf-mid*"))
        (old dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-command--cache-catalog
           "sess-mid"
           (list (dsh-protocol-command--from-alist
                  '((name . "goal") (description . "Set and track goals.")))))
          (dsh-emacs-skill--cache-catalog
           "sess-mid"
           (list (dsh-protocol-skill--from-alist
                  '((name . "review") (description . "Review a diff")
                    (modelInvocable . t)))))
          (setq dsh-emacs--current-session "sess-mid")
          (goto-char dsh-emacs--input-marker)
          (insert "please /rev")
          (let* ((comp (dsh-emacs-command-completion-at-point))
                 (cands (dsh-test-completion-items (nth 2 comp))))
            (ert-info ((format "%s" "command-capf-completes-mid-sentence-token"))
              (should (and comp
                           (= (nth 0 comp)
                              (+ (marker-position dsh-emacs--input-marker) 7))
                           (= (nth 1 comp) (point-max))
                           (equal '("/goal" "/review") cands)))))
          (ert-info ((format "%s" "command-capf-mid-sentence-completion-replaces-token"))
            (should (progn
                      (let ((completion-styles '(basic)))
                        (completion-at-point))
                      (equal "please /review "
                             (buffer-substring-no-properties
                              dsh-emacs--input-marker (point-max))))))
          ;; catalog-confirmed: `/usr' is not a command or skill here, so this
          ;; source declines and path/word completion keep their chance at it
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "see /usr")
          (ert-info ((format "%s" "command-capf-declines-unknown-mid-sentence-token"))
            (should (null (dsh-emacs-command-completion-at-point))))
          ;; a slash inside a word is not a token (same boundary as the host)
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "and/or")
          (ert-info ((format "%s" "command-capf-declines-slash-inside-a-word"))
            (should (null (dsh-emacs-command-completion-at-point)))))
      (setq dsh-emacs--command-catalogs old
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; --- Test 100c: the "/" catalog matches with the flex style by category ---
;; A chat buffer maps the `dsh-emacs-command' completion category to the
;; built-in `flex' style, the way `@' references do, so a word inside a long
;; skill name completes even though the user's own `completion-styles' are only
;; `basic'.  The category rides the candidate table, and the capf's claim gate
;; reads that same table — which is what lets a mid-sentence `/probe' claim the
;; token under flex while `basic' alone cannot.
(ert-deftest dsh-emacs-test-completion-command-capf-flex-matches-inside-a-name ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-capf-flex*"))
        (old dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-command--cache-catalog
           "sess-flex"
           (list (dsh-protocol-command--from-alist
                  '((name . "goal") (description . "Set and track goals.")))
                 (dsh-protocol-command--from-alist
                  '((name . "plan") (description . "Plan it.")))
                 (dsh-protocol-command--from-alist
                  '((name . "permission") (description . "Set a preset.")))))
          (dsh-emacs-skill--cache-catalog
           "sess-flex"
           (list (dsh-protocol-skill--from-alist
                  '((name . "dsh-emacs-skill-probe") (description . "Probe it")
                    (modelInvocable . t)))
                 (dsh-protocol-skill--from-alist
                  '((name . "review") (description . "Review a diff")
                    (modelInvocable . t)))))
          (setq dsh-emacs--current-session "sess-flex")
          (goto-char dsh-emacs--input-marker)
          (insert "/probe")
          (let ((completion-styles '(basic)))
            (completion-at-point))
          (ert-info ((format "%s" "command-capf-flex-matches-inside-a-name"))
            (should (equal "/dsh-emacs-skill-probe "
                           (buffer-substring-no-properties
                            dsh-emacs--input-marker (point-max)))))
          ;; mid-sentence the token is claimed only when the catalogs complete
          ;; it: `/probe' is not a prefix of any name, so this passes only when
          ;; the gate matches under the table's own category
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "please /probe")
          (let ((comp (dsh-emacs-command-completion-at-point)))
            (ert-info ((format "%s" "command-capf-flex-claims-mid-sentence-token"))
              (should (and comp
                           (= (nth 0 comp)
                              (+ (marker-position dsh-emacs--input-marker) 7))))))
          ;; a name no catalog matches is still declined, flex or not
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "see /usr")
          (ert-info ((format "%s" "command-capf-flex-still-declines-unknown-token"))
            (should (null (dsh-emacs-command-completion-at-point))))
          ;; flex sits after prefix matching: with flex first, flex's PCM merge
          ;; treats an ambiguous or bare pattern as finished and TAB inserts
          ;; "pattern + space" instead of listing — assert both stay untouched
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "please /")
          (let ((completion-styles '(basic)))
            (completion-at-point))
          (ert-info ((format "%s" "command-capf-bare-slash-lists-without-inserting"))
            (should (equal "please /"
                           (buffer-substring-no-properties
                            dsh-emacs--input-marker (point-max)))))
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "please /p")
          (let ((completion-styles '(basic)))
            (completion-at-point))
          (ert-info ((format "%s" "command-capf-ambiguous-prefix-lists-without-inserting"))
            (should (equal "please /p"
                           (buffer-substring-no-properties
                            dsh-emacs--input-marker (point-max)))))
          ;; The styles above are package defaults, not a buffer-local override,
          ;; so the user's own `completion-category-overrides' wins (the standard
          ;; knob): with `basic' only, no prefix matches `/probe' and flex is out
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (insert "/probe")
          (let ((completion-category-overrides
                 '((dsh-emacs-command (styles basic))))
                (completion-styles '(basic)))
            (completion-at-point))
          (ert-info ((format "%s" "command-capf-user-style-override-wins"))
            (should (equal "/probe"
                           (buffer-substring-no-properties
                            dsh-emacs--input-marker (point-max))))))
      (setq dsh-emacs--command-catalogs old
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; An ambiguous infix must stay a token until a complete name is chosen.
;; A shared trailing space in the candidates used to make flex insert
;; `/review ' even though neither catalog contains a skill called `review'.
(ert-deftest dsh-emacs-test-completion-command-capf-ambiguous-infix-keeps-token ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs--buffer-session "sess-flex-ambiguous")
    (let ((dsh-emacs--command-catalogs nil)
          (dsh-emacs--skill-catalogs nil)
          (completion-styles '(basic)))
      (dsh-emacs-command--cache-catalog
       "sess-flex-ambiguous"
       (list (dsh-protocol-command--from-alist '((name . "goal")))))
      (dsh-emacs-skill--cache-catalog
       "sess-flex-ambiguous"
       (mapcar #'dsh-protocol-skill--from-alist
               '(((name . "code-review")) ((name . "design-review")))))
      (goto-char dsh-emacs--input-marker)
      (insert "please /review")
      (completion-at-point)
      (ert-info ((format "%s" "command-capf-ambiguous-infix-keeps-token"))
        (should (equal "please /review"
                       (buffer-substring-no-properties
                        dsh-emacs--input-marker (point-max)))))
      ;; Narrowing to one real name still leaves the cursor ready for arguments.
      (delete-region dsh-emacs--input-marker (point-max))
      (goto-char dsh-emacs--input-marker)
      (insert "please /code")
      (completion-at-point)
      (ert-info ((format "%s" "command-capf-unique-name-adds-separator"))
        (should (equal "please /code-review "
                       (buffer-substring-no-properties
                        dsh-emacs--input-marker (point-max))))
        (should (= (point) (point-max))))
      ;; Completing in front of existing arguments consumes their separator.
      (delete-region dsh-emacs--input-marker (point-max))
      (goto-char dsh-emacs--input-marker)
      (insert "please /code check this")
      (backward-char (length " check this"))
      (completion-at-point)
      (ert-info ((format "%s" "command-capf-reuses-existing-separator"))
        (should (equal "please /code-review check this"
                       (buffer-substring-no-properties
                        dsh-emacs--input-marker (point-max))))
        (should (looking-at-p "check this")))
      ;; An exact match may still grow; accepting it explicitly finishes it.
      (delete-region dsh-emacs--input-marker (point-max))
      (goto-char dsh-emacs--input-marker)
      (insert "/goal")
      (let* ((capf (dsh-emacs-command-completion-at-point))
             (finish (plist-get (nthcdr 3 capf) :exit-function)))
        (funcall finish "/goal" 'exact)
        (ert-info ((format "%s" "command-capf-exact-match-keeps-token-editable"))
          (should (equal "/goal" (buffer-substring-no-properties
                                  dsh-emacs--input-marker (point-max)))))
        (funcall finish "/goal" 'finished)
        (ert-info ((format "%s" "command-capf-accepted-command-adds-separator"))
          (should (equal "/goal " (buffer-substring-no-properties
                                   dsh-emacs--input-marker (point-max)))))))))

;; Both token sources register their styles as package defaults at load time
;; (the way `eglot-capf' / `ecomplete' do), not as buffer-local overrides.
(ert-deftest dsh-emacs-test-completion-completion-categories-registered-as-defaults ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "completion-categories-registered-as-defaults"))
    (should (and (equal '(basic flex)
                        (cdr (assq 'styles (cdr (assq 'dsh-emacs-command
                                                      completion-category-defaults)))))
                 (equal '(flex)
                        (cdr (assq 'styles (cdr (assq 'dsh-emacs-reference
                                                      completion-category-defaults)))))))))

;; Candidates are plain strings, descriptions go through standard metadata
;; (annotation-function / company-kind): the corfu popup lays out at real
;; width (same style as other modes), no display property to pad the width
(ert-deftest dsh-emacs-test-completion-command-capf-metadata-annotation-kind ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-capf-meta*"))
        (old dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-command--cache-catalog
           "sess-cap-meta"
           (list (dsh-protocol-command--from-alist
                  '((name . "goal") (description . "Set and track goals.")))
                 (dsh-protocol-command--from-alist
                  '((name . "compact") (description . "Condense context.")))
                 (dsh-protocol-command--from-alist
                  '((name . "export") (description . "Export this session.")))))
          ;; fetched-but-empty skills: the capf must not fall back to a sync fetch
          (dsh-emacs-skill--cache-catalog "sess-cap-meta" nil)
          (setq dsh-emacs--current-session "sess-cap-meta")
          (goto-char dsh-emacs--input-marker)
          (insert "/")
          (let* ((comp (dsh-emacs-command-completion-at-point))
                 (cands (dsh-test-completion-items (nth 2 comp)))
                 (raw (all-completions "" (nth 2 comp)))
                 (meta (nthcdr 3 comp))
                 (ann (plist-get meta :annotation-function)))
            (ert-info ((format "%s" "command-capf-metadata-annotation-kind"))
              (should (and comp
                           (= 3 (length cands))
                           (cl-every (lambda (c) (null (text-properties-at 0 c)))
                                     raw)
                           (functionp ann)
                           (string= "Set and track goals." (funcall ann "/goal"))
                           (string= "Condense context." (funcall ann "/compact"))
                           ;; `:company-kind' is a "candidate → kind symbol" function
                           ;; (nerd-icons-corfu's kindfunc convention, a bare symbol gets
                           ;; funcalled)
                           (let ((kindf (plist-get meta :company-kind)))
                             (and (functionp kindf)
                                  (eq 'command (funcall kindf "/goal")))))))))
      (setq dsh-emacs--command-catalogs old
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; When a catalog has not been fetched, the first trigger also fills it
;; synchronously (otherwise "/" pops an empty list) — both catalogs, each with
;; its own wire shape
(ert-deftest dsh-emacs-test-completion-command-capf-sync-fetches-uncached-catalog ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-capf-sync*"))
        (old dsh-emacs--command-catalogs)
        (old-skills dsh-emacs--skill-catalogs)
        (rpc-calls nil))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (setq dsh-emacs--current-session "sess-sync")
          (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                     (lambda (method params)
                       (push (cons method params) rpc-calls)
                       (if (string= "skills/list" method)
                           (cons t '((skills . [((name . "review")
                                                 (description . "R")
                                                 (modelInvocable . t))])))
                         (cons t [((name . "compact") (description . "c"))
                                  ((name . "goal") (description . "g"))])))))
            (goto-char dsh-emacs--input-marker)
            (insert "/")
            (let* ((comp (dsh-emacs-command-completion-at-point))
                   (cands (dsh-test-completion-items (nth 2 comp))))
              (ert-info ((format "%s" "command-capf-sync-fetches-uncached-catalog"))
                (should (and comp
                             (= 2 (length rpc-calls))
                             (member "/goal" cands)
                             (member "/compact" cands)
                             (member "/review" cands)
                             ;; each catalog keeps its own wire shape: skills/list
                             ;; wraps the session in a request object, commands/list
                             ;; carries it as the agentId scope lookup
                             (equal '((request (sessionId . "sess-sync")))
                                    (cdr (assoc "skills/list" rpc-calls)))
                             (equal '((agentId . "sess-sync"))
                                    (cdr (assoc "commands/list" rpc-calls)))))))))
      (setq dsh-emacs--command-catalogs old
            dsh-emacs--skill-catalogs old-skills)
      (kill-buffer buf))))

;; TAB in a chat buffer must land on completion-at-point (the keyboard
;; entry for slash completion)
(ert-deftest dsh-emacs-test-completion-chat-mode-tab-bound-to-completion-at-point ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "chat-mode-tab-bound-to-completion-at-point"))
    (should (eq (lookup-key dsh-emacs-mode-map (kbd "TAB"))
                #'completion-at-point))))

;; --- Test 100b: input word completion (draft + transcript) ---
;; A word already written above the input completes: the transcript is a
;; source, the region is the word before point, and the frontend still
;; filters by the typed prefix.
(ert-deftest dsh-emacs-test-completion-word-capf-region-and-transcript-word ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-word-capf*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char (point-max))
          (insert "earlier: discard-stream rendered the dsh-emacs-mode output\n")
          (setq-local dsh-emacs--input-marker (point-marker))
          (insert "please dis")
          (goto-char (point-max))
          (let* ((res (dsh-emacs-word-completion-at-point))
                 (cands (all-completions "dis" (nth 2 res))))
            (ert-info ((format "%s" "word-capf-region-and-transcript-word"))
              (should (= (nth 0 res) (- (point) 3)))
              (should (= (nth 1 res) (point)))
              (should (member "discard-stream" cands))
              (should (not (member "dsh-emacs-mode" cands)))
              (should (eq (plist-get (nthcdr 3 res) :exclusive) 'no))))
          ;; Point right after a non-word character has no token to complete.
          (insert " ")
          (ert-info ((format "%s" "word-capf-empty-token-nil"))
            (should (null (dsh-emacs-word-completion-at-point)))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; A word earlier in the same draft is a source too.
(ert-deftest dsh-emacs-test-completion-word-capf-draft-word ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-word-draft*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char (point-max))
          (setq-local dsh-emacs--input-marker (point-marker))
          (insert "omega beta omeg")
          (goto-char (point-max))
          (ert-info ((format "%s" "word-capf-draft-word"))
            (should (equal (all-completions
                            "omeg" (nth 2 (dsh-emacs-word-completion-at-point)))
                           '("omega")))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; The nearest occurrence wins and duplicates collapse.
(ert-deftest dsh-emacs-test-completion-word-capf-nearest-first-deduped ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-word-nearest*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char (point-max))
          (insert "zulu zebra and zebra again\n")
          (setq-local dsh-emacs--input-marker (point-marker))
          (insert "z")
          (goto-char (point-max))
          (ert-info ((format "%s" "word-capf-nearest-first-deduped"))
            (should (equal (all-completions
                            "z" (nth 2 (dsh-emacs-word-completion-at-point)))
                           '("zebra" "zulu")))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; Identifier words: a hyphen or underscore joins one candidate.
(ert-deftest dsh-emacs-test-completion-word-capf-hyphen-token ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-word-chars*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char (point-max))
          (insert "snake_case read-only\n")
          (setq-local dsh-emacs--input-marker (point-marker))
          (insert "read-o")
          (goto-char (point-max))
          (ert-info ((format "%s" "word-capf-hyphen-token"))
            (should (equal (all-completions
                            "read-o" (nth 2 (dsh-emacs-word-completion-at-point)))
                           '("read-only"))))
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char (point-max))
          (insert "snake_c")
          (ert-info ((format "%s" "word-capf-underscore-token"))
            (should (equal (all-completions
                            "snake_c" (nth 2 (dsh-emacs-word-completion-at-point)))
                           '("snake_case")))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; Case follows `completion-ignore-case', the option the front-end filters
;; the returned candidates with, so the two never disagree.
(ert-deftest dsh-emacs-test-completion-word-capf-case-sensitive-by-default ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-word-case*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char (point-max))
          (insert "Streamed\n")
          (setq-local dsh-emacs--input-marker (point-marker))
          (insert "stre")
          (goto-char (point-max))
          (let ((completion-ignore-case nil))
            (ert-info ((format "%s" "word-capf-case-sensitive-by-default"))
              (should (null (dsh-emacs-word-completion-at-point)))))
          (let ((completion-ignore-case t))
            (ert-info ((format "%s" "word-capf-ignore-case-option"))
              (should (equal (all-completions
                              "stre" (nth 2 (dsh-emacs-word-completion-at-point)))
                             '("Streamed")))))
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char (point-max))
          (insert "Stre")
          (let ((completion-ignore-case nil))
            (ert-info ((format "%s" "word-capf-uppercase-prefix-matches"))
              (should (equal (all-completions
                              "Stre" (nth 2 (dsh-emacs-word-completion-at-point)))
                             '("Streamed"))))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; `dsh-emacs-word-completion-limit' bounds the backward search; nil scans the
;; whole buffer.
(ert-deftest dsh-emacs-test-completion-word-capf-limit-hides-old-word ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-word-limit*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char (point-max))
          (insert "needle " (make-string 40 ?x) "\n")
          (setq-local dsh-emacs--input-marker (point-marker))
          (insert "nee")
          (goto-char (point-max))
          (let ((dsh-emacs-word-completion-limit 8))
            (ert-info ((format "%s" "word-capf-limit-hides-old-word"))
              (should (null (dsh-emacs-word-completion-at-point)))))
          (let ((dsh-emacs-word-completion-limit nil))
            (ert-info ((format "%s" "word-capf-limit-nil-scans-buffer"))
              (should (equal (all-completions
                              "nee" (nth 2 (dsh-emacs-word-completion-at-point)))
                             '("needle"))))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; No matching word, point in the transcript, and an empty input area all
;; decline (the last one even when the transcript word abuts the marker).
(ert-deftest dsh-emacs-test-completion-word-capf-no-match-nil ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-word-none*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (goto-char (point-max))
          (insert "alpha")
          (setq-local dsh-emacs--input-marker (point-marker))
          (insert "zzzq")
          (goto-char (point-max))
          (ert-info ((format "%s" "word-capf-no-match-nil"))
            (should (null (dsh-emacs-word-completion-at-point))))
          (goto-char (point-min))
          (ert-info ((format "%s" "word-capf-transcript-nil"))
            (should (null (dsh-emacs-word-completion-at-point))))
          (delete-region dsh-emacs--input-marker (point-max))
          (goto-char dsh-emacs--input-marker)
          (ert-info ((format "%s" "word-capf-empty-input-nil"))
            (should (null (dsh-emacs-word-completion-at-point)))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;; Completing inside a word replaces its suffix as part of the same region.
(ert-deftest dsh-emacs-test-completion-word-capf-mid-word-case ()
  :tags '(dsh-unit)
  (dolist (draft '("rendered" "rened"))
    (with-temp-buffer
      (dsh-emacs-mode)
      (goto-char (point-max))
      (insert "rendered\n")
      (setq-local dsh-emacs--input-marker (point-marker))
      (insert draft)
      (goto-char (+ dsh-emacs--input-marker 3))
      (let ((completion-styles '(basic)))
        (completion-at-point))
      (ert-info ((format "%s" (format "word-capf-mid-word-%s" draft)))
        (should (equal (buffer-substring-no-properties dsh-emacs--input-marker (point-max))
                       "rendered"))))))

;; Empty command/reference results must not fall through to transcript words.
(ert-deftest dsh-emacs-test-completion-word-capf-reserves-token-case ()
  :tags '(dsh-unit)
  (dolist (draft '("/ren" "@ren" "please @src/ren" "please @\"my files/ren"))
    (with-temp-buffer
      (dsh-emacs-mode)
      (goto-char (point-max))
      (insert "rendered\n")
      (setq-local dsh-emacs--input-marker (point-marker)
                  dsh-emacs--buffer-session "word-capf-empty-catalog")
      (insert draft)
      (let ((dsh-emacs--command-catalogs nil))
        (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                   (lambda (_method _params) (cons t []))))
          (completion-at-point)))
      (ert-info ((format "%s" (format "word-capf-reserves-token-%s" draft)))
        (should (null (dsh-emacs-word-completion-at-point)))
        (should (equal (buffer-substring-no-properties dsh-emacs--input-marker (point-max))
                       draft))))))

;; Command arguments, non-command slash text and embedded @ stay ordinary.
(ert-deftest dsh-emacs-test-completion-word-capf-ordinary-token-case ()
  :tags '(dsh-unit)
  (dolist (example '(("/goal ren" . "/goal rendered")
                     ("/Ren" . "/Rendered")
                     ("/foo.ren" . "/foo.rendered")
                     ("user@ren" . "user@rendered")))
    (with-temp-buffer
      (dsh-emacs-mode)
      (goto-char (point-max))
      (insert "rendered Rendered\n")
      (setq-local dsh-emacs--input-marker (point-marker))
      (insert (car example))
      (let ((completion-styles '(basic))
            (completion-ignore-case nil))
        (completion-at-point))
      (ert-info ((format "%s" (format "word-capf-ordinary-token-%s" (car example))))
        (should (equal (buffer-substring-no-properties dsh-emacs--input-marker (point-max))
                       (cdr example)))))))

;; The actual stock completion display must preserve nearest-first ordering.
(ert-deftest dsh-emacs-test-completion-word-capf-stock-display-nearest-first ()
  :tags '(dsh-unit)
  (save-window-excursion
    (with-temp-buffer
      (dsh-emacs-mode)
      (goto-char (point-max))
      (insert "zebra zulu\n")
      (setq-local dsh-emacs--input-marker (point-marker))
      (insert "z")
      (let ((completion-styles '(basic))
            (completion-auto-help t)
            (completion-cycle-threshold nil))
        (completion-at-point))
      (ert-info ((format "%s" "word-capf-stock-display-nearest-first"))
        (should (with-current-buffer "*Completions*"
                  (let ((text (buffer-substring-no-properties (point-min) (point-max))))
                    (and (string-match "zulu" text)
                         (string-match "zebra" text)
                         (< (string-match "zulu" text) (string-match "zebra" text)))))))
      (let* ((table (nth 2 (dsh-emacs-word-completion-at-point)))
             (metadata (completion-metadata "z" table nil))
             (sort-fn (completion-metadata-get metadata 'cycle-sort-function)))
        (ert-info ((format "%s" "word-capf-cycle-nearest-first"))
          (should (and sort-fn
                       (equal (funcall sort-fn (all-completions "z" table))
                              '("zulu" "zebra"))))))
      (kill-buffer "*Completions*"))))

;; --- Test 100c: local file path completion ---
;; A token that carries a separator completes against the chat buffer's
;; default-directory (the session workspace) through the stock file-name
;; completer; a bare name stays with word completion.
(ert-deftest dsh-emacs-test-completion-path-capf-region-and-style-case ()
  :tags '(dsh-unit)
  (let* ((root (file-name-as-directory (make-temp-file "dsh-path-capf-" t)))
         (sub (file-name-as-directory (expand-file-name "sub" root))))
    (unwind-protect
        (progn
          (make-directory sub t)
          (with-temp-file (expand-file-name "sub/report.md" root)
            (insert "x"))
          (with-temp-file (expand-file-name "sub/notes.txt" root)
            (insert "x"))
          ;; Use the real completion path, including suffixes and abbreviated
          ;; directory components under the standard partial-completion style.
          (dolist (example '(("sub/report.md," 6 "sub/report.md,")
                             ("sub/re.md," 6 "sub/report.md,")
                             ("./s/re" 6 "./sub/report.md")
                             ("./su/report.md" 4 "./sub/report.md")))
            (pcase-let ((`(,draft ,offset ,expected) example))
              (with-temp-buffer
                (dsh-emacs-mode)
                (setq default-directory root)
                (goto-char (point-max))
                (setq-local dsh-emacs--input-marker (point-marker))
                (insert draft)
                (goto-char (+ dsh-emacs--input-marker offset))
                (let ((completion-styles '(basic partial-completion))
                      (completion-category-defaults nil)
                      (completion-category-overrides nil))
                  (completion-at-point))
                (ert-info ((format "%s" (format "path-capf-region-and-style-%s" draft)))
                  (should (equal (buffer-substring-no-properties
                                  dsh-emacs--input-marker (point-max))
                                 expected))))))
          (with-temp-buffer
            (dsh-emacs-mode)
            (setq default-directory root)
            (goto-char (point-max))
            (setq-local dsh-emacs--input-marker (point-marker))
            (insert "please see sub/rep")
            (goto-char (point-max))
            (let ((completion-styles '(basic)))
              (completion-at-point))
            (ert-info ((format "%s" "path-capf-completes-relative-path"))
              (should (equal (buffer-substring-no-properties dsh-emacs--input-marker
                                                             (point-max))
                             "please see sub/report.md")))
            ;; A directory prefix claims the token and keeps its candidates for
            ;; the next level.
            (delete-region dsh-emacs--input-marker (point-max))
            (goto-char (point-max))
            (insert "sub/")
            (let ((res (dsh-emacs-path-completion-at-point)))
              (ert-info ((format "%s" "path-capf-directory-drill-down"))
                (should (and res
                             (= (nth 0 res) (marker-position dsh-emacs--input-marker))
                             (= (nth 1 res) (point))
                             (eq (nth 2 res) #'completion-file-name-table)
                             (member "report.md"
                                     (all-completions "sub/" (nth 2 res)))))))
            ;; The separator is the signal: a bare name is a word, not a path,
            ;; and a lone tilde is not a path token either.
            (delete-region dsh-emacs--input-marker (point-max))
            (goto-char (point-max))
            (insert "report")
            (ert-info ((format "%s" "path-capf-requires-a-separator"))
              (should (null (dsh-emacs-path-completion-at-point))))
            (delete-region dsh-emacs--input-marker (point-max))
            (goto-char (point-max))
            (insert "~")
            (ert-info ((format "%s" "path-capf-lone-tilde-is-not-a-path"))
              (should (null (dsh-emacs-path-completion-at-point))))
            ;; An @ token belongs to the reference source even when its own
            ;; catalog is empty (there is no session here).
            (delete-region dsh-emacs--input-marker (point-max))
            (goto-char (point-max))
            (insert "@sub/rep")
            (ert-info ((format "%s" "path-capf-declines-reference-token"))
              (should (null (dsh-emacs-path-completion-at-point))))
            ;; Prose with a slash is not a path unless such a directory exists.
            (delete-region dsh-emacs--input-marker (point-max))
            (goto-char (point-max))
            (insert "and/or")
            (ert-info ((format "%s" "path-capf-declines-non-directory-slash"))
              (should (null (dsh-emacs-path-completion-at-point))))
            ;; Absolute paths complete too, and the token boundary keeps
            ;; trailing punctuation out of the region.
            (delete-region dsh-emacs--input-marker (point-max))
            (goto-char (point-max))
            (insert (concat root "sub/re"))
            (let ((completion-styles '(basic)))
              (completion-at-point))
            (ert-info ((format "%s" "path-capf-completes-absolute-path"))
              (should (equal (buffer-substring-no-properties dsh-emacs--input-marker
                                                             (point-max))
                             (concat root "sub/report.md"))))
            (delete-region dsh-emacs--input-marker (point-max))
            (goto-char (point-max))
            (insert "sub/report.md,")
            (goto-char (1- (point-max)))
            (let ((res (dsh-emacs-path-completion-at-point)))
              (ert-info ((format "%s" "path-capf-region-stops-at-punctuation"))
                (should (and res
                             (= (nth 1 res) (point))
                             (equal (buffer-substring-no-properties (nth 0 res)
                                                                    (nth 1 res))
                                    "sub/report.md")
                             (eq (char-after (point)) ?,)))))))
      (delete-directory root t))))

;; A matching local path must not take over a command prefix, even when
;; commands/list returns an empty catalog or fails.  The file table supplies
;; a deterministic match without depending on directories under system root.
(ert-deftest dsh-emacs-test-completion-path-capf-reserves-command-case-case ()
  :tags '(dsh-unit)
  (dolist (rpc-ok '(t nil))
    (dolist (draft '("/" "/ren"))
      (with-temp-buffer
        (dsh-emacs-mode)
        (goto-char (point-max))
        (setq-local dsh-emacs--input-marker (point-marker)
                    dsh-emacs--buffer-session "path-capf-empty-catalog")
        (insert draft)
        (let ((dsh-emacs--command-catalogs nil)
              (completion-styles '(basic)))
          (cl-letf (((symbol-function 'dsh-emacs--rpc-request)
                     (lambda (_method _params) (cons rpc-ok [])))
                    ((symbol-function 'completion-file-name-table)
                     (lambda (string pred action)
                       (complete-with-action action '("/rendered/")
                                             string pred))))
            (completion-at-point)))
        (ert-info ((format "%s" (format "path-capf-reserves-command-%s-%s" rpc-ok draft)))
          (should (equal (buffer-substring-no-properties
                          dsh-emacs--input-marker (point-max))
                         draft)))))))

;; Mode wiring: commands and references own their tokens, a path token
;; completes locally, and word completion is the last fallback.
(ert-deftest dsh-emacs-test-completion-chat-mode-input-completion-sources ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (ert-info ((format "%s" "chat-mode-input-completion-sources"))
      (should (equal completion-at-point-functions
                     '(dsh-emacs-command-completion-at-point
                       dsh-emacs-reference-completion-at-point
                       dsh-emacs-path-completion-at-point
                       dsh-emacs-word-completion-at-point))))))

;; Cooperative "/" auto-trigger: dsh-emacs-mode adds "/" to the buffer-local
;; `corfu-auto-trigger' only when the user already enabled corfu-auto, letting
;; corfu's own engine pop the list.  dsh-emacs never enables corfu-auto itself
;; and never hooks corfu-auto--post-command into post-command-hook (that hook is
;; corfu-mode's job when corfu-auto is on; dsh-emacs only contributes a trigger).
(ert-deftest dsh-emacs-test-completion-slash-auto-corfu-coop-trigger-added ()
  :tags '(dsh-unit)
  (let ((corfu-auto t)
        (corfu-auto-trigger "")
        (buf (generate-new-buffer " *dsh-corfu-coop*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'require) (lambda (&rest _) t)))
            (dsh-emacs-mode)
            (ert-info ((format "%s" "slash-auto-corfu-coop-trigger-added"))
              (should (string-match-p "/" (buffer-local-value 'corfu-auto-trigger buf)))
              (should (string-match-p "@" (buffer-local-value 'corfu-auto-trigger buf)))
              (should (not (memq 'corfu-auto--post-command
                                 (buffer-local-value 'post-command-hook buf)))))))
      (kill-buffer buf))))

;; corfu-auto off (user did not enable auto): no trigger contributed (TAB-only)
(ert-deftest dsh-emacs-test-completion-slash-auto-corfu-coop-off-no-trigger ()
  :tags '(dsh-unit)
  (let ((corfu-auto nil)
        (corfu-auto-trigger "")
        (buf (generate-new-buffer " *dsh-corfu-coop-off*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'require) (lambda (&rest _) t)))
            (dsh-emacs-mode)
            (ert-info ((format "%s" "slash-auto-corfu-coop-off-no-trigger"))
              (should (string= "" (buffer-local-value 'corfu-auto-trigger buf))))))
      (kill-buffer buf))))

;; all auto options off: nothing contributed even when corfu-auto is on
(ert-deftest dsh-emacs-test-completion-slash-auto-corfu-coop-off-when-options-off ()
  :tags '(dsh-unit)
  (let ((corfu-auto t)
        (corfu-auto-trigger "")
        (buf (generate-new-buffer " *dsh-corfu-coop-offopt*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                    (dsh-emacs-slash-auto-complete nil)
                    (dsh-emacs-reference-auto-complete nil))
            (dsh-emacs-mode)
            (ert-info ((format "%s" "slash-auto-corfu-coop-off-when-options-off"))
              (should (string= "" (buffer-local-value 'corfu-auto-trigger buf))))))
      (kill-buffer buf))))

;; idempotent: running setup again does not append "/" twice
(ert-deftest dsh-emacs-test-completion-slash-auto-corfu-coop-idempotent ()
  :tags '(dsh-unit)
  (let ((corfu-auto t)
        (corfu-auto-trigger "")
        (buf (generate-new-buffer " *dsh-corfu-coop-idem*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'require) (lambda (&rest _) t)))
            (dsh-emacs-command-auto-trigger-setup)
            (dsh-emacs-command-auto-trigger-setup)
            (ert-info ((format "%s" "slash-auto-corfu-coop-idempotent"))
              (should (string= "/" (buffer-local-value 'corfu-auto-trigger buf))))))
      (kill-buffer buf))))

(provide 'dsh-test-completion)
;;; dsh-test-completion.el ends here

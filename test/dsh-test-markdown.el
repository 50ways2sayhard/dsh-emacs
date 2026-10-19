;;; dsh-test-markdown.el --- Markdown tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

;; --- Test 11: Markdown functions exist ---
(ert-deftest dsh-emacs-test-markdown-markdown-render-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "markdown-render function exists"))
    (should (fboundp 'dsh-emacs-markdown-render))))

(ert-deftest dsh-emacs-test-markdown-markdown-render-applies-faces ()
  :tags '(dsh-unit)
  (let ((rendered (dsh-emacs-markdown-render "# title\n**bold** `code`")))
    (ert-info ((format "%s" "markdown-render-applies-faces"))
      (should (and (string= rendered "title\nbold code\n")
                   (eq (get-text-property 0 'face rendered)
                       'dsh-emacs-markdown-header-1)
                   (eq (get-text-property 6 'face rendered)
                       'dsh-emacs-markdown-bold)
                   (eq (get-text-property 11 'face rendered)
                       'dsh-emacs-markdown-inline-code))))))

(ert-deftest dsh-emacs-test-markdown-markdown-nested-and-alternate-markup ()
  :tags '(dsh-unit)
  (let ((rendered (dsh-emacs-markdown-render
                   "__bold__ _italic_ ~~gone~~ **_both_**")))
    (let ((both-face (get-text-property 17 'face rendered)))
      (ert-info ((format "%s" "markdown-nested-and-alternate-markup"))
        (should (and (string= rendered "bold italic gone both\n")
                     (eq (get-text-property 0 'face rendered)
                         'dsh-emacs-markdown-bold)
                     (eq (get-text-property 5 'face rendered)
                         'dsh-emacs-markdown-italic)
                     (eq (get-text-property 12 'face rendered)
                         'dsh-emacs-markdown-strikethrough)
                     (listp both-face)
                     (memq 'dsh-emacs-markdown-bold both-face)
                     (memq 'dsh-emacs-markdown-italic both-face)))))))

(ert-deftest dsh-emacs-test-markdown-markdown-table-render ()
  :tags '(dsh-unit)
  (let ((rendered (dsh-emacs-markdown-render
                   "| Name | Value |\n| --- | ---: |\n| **foo** | `bar` |")))
    (ert-info ((format "%s" "markdown-table-render"))
      (should (and (string-match-p "│ Name │ Value │" rendered)
                   (string-match-p "├" rendered)
                   (string-match-p "foo" rendered)
                   (not (string-match-p "\\*\\*" rendered))
                   (not (string-match-p "`" rendered)))))))

;; Pixel paths use the target frame even when it is not the selected frame.
(ert-deftest dsh-emacs-test-markdown-table-pixel-paths-use-the-destination-frame ()
  :tags '(dsh-unit)
  (let* ((window (selected-window))
         (frame (window-frame window)))
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional target) (eq target frame)))
              ((symbol-function 'dsh-emacs-markdown--table-measure-string)
               (lambda (str _window)
                 (cond ((equal str " ") 10)
                       ((equal str "MMMMMMMMMM")
                        (if (get-text-property 0 'face str) 200 100))
                       (t 30)))))
      (ert-info ((format "%s" "table-pixel-paths-use-the-destination-frame"))
        (should (= (dsh-emacs-markdown--table-display-width :str "中" :window window) 3))
        (should (= (dsh-emacs-markdown--table-wrap-char-width
                    (propertize "a" 'face 'bold) 0 window) 2.0))
        (should (equal (dsh-emacs-markdown--pad-table-string
                        :str "中" :width 4 :window window) "中 "))))))

;; Font measurements are shared within one table, never across renders.
(ert-deftest dsh-emacs-test-markdown-table-metrics-use-current-render-fonts ()
  :tags '(dsh-unit)
  (save-window-excursion
    (with-temp-buffer
      (let* ((window (split-window-right))
             (source (concat "| " (propertize "AAAA" 'face 'bold)
                             " | 中文 |\n|---|---|\n| plain | 中文 |\n"))
             (default-height 16)
             (spaces 0)
             (faces 0)
             height-windows first second)
        (set-window-buffer window (current-buffer))
        (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                  ((symbol-function 'dsh-emacs-markdown--table-measure-line-height)
                   (lambda (win str)
                     (push win height-windows)
                     (if (equal str "A") default-height 20)))
                  ((symbol-function 'dsh-emacs-markdown--table-measure-string)
                   (lambda (str _window)
                     (when (equal str " ") (cl-incf spaces))
                     (when (and (equal str "MMMMMMMMMM")
                                (get-text-property 0 'face str))
                       (cl-incf faces))
                     (* 10 (string-width str)))))
          (setq first (dsh-emacs-markdown--render-table-source
                       :source source :window window)
                default-height 18
                second (dsh-emacs-markdown--render-table-source
                        :source source :window window)))
        (ert-info ((format "%s" "table-metrics-use-current-render-fonts"))
          (should (equal (get-text-property (string-match "中" first) 'display first)
                         '(height 0.8)))
          (should (equal (get-text-property (string-match "中" second) 'display second)
                         '(height 0.9)))
          (should (= spaces 2))
          (should (= faces 2))
          (should (cl-every (lambda (win) (eq win window)) height-windows)))))))

;; The compatibility pixel probe must measure beyond the window's width.
(ert-deftest dsh-emacs-test-markdown-table-measure-full-width-on-emacs-27 ()
  :tags '(dsh-unit)
  (save-window-excursion
    (with-temp-buffer
      (set-window-buffer (selected-window) (current-buffer))
      (let ((emacs-major-version 27)
            measured)
        (cl-letf (((symbol-function 'window-text-pixel-size)
                   (lambda (_window _from _to &optional x-limit &rest _)
                     (setq measured x-limit)
                     (cons (if (eq x-limit t) 3500 560) 10))))
          (ert-info ((format "%s" "table-measure-full-width-on-emacs-27"))
            (should (= (dsh-emacs-markdown--table-measure-string
                        (make-string 500 ?W) (selected-window)) 3500))
            (should (eq measured t))))))))

;; Emacs 31 can measure in the destination's font context without editing it.
(ert-deftest dsh-emacs-test-markdown-table-measure-without-destination-edits ()
  :tags '(dsh-unit)
  (save-window-excursion
    (with-temp-buffer
      (insert "draft")
      (let* ((source (current-buffer))
             (window (split-window-right))
             (selected (selected-window))
             (tick (buffer-modified-tick))
             (emacs-major-version 31)
             measured)
        (set-window-buffer window source)
        (cl-letf (((symbol-function 'string-pixel-width)
                   (lambda (str buffer)
                     (setq measured (list str buffer (selected-window)))
                     3500)))
          (let ((width (dsh-emacs-markdown--table-measure-string
                        (make-string 500 ?W) window)))
            (ert-info ((format "%s" "table-measure-without-destination-edits"))
              (should (= width 3500))
              (should (equal measured (list (make-string 500 ?W) source window)))
              (should (= tick (buffer-modified-tick)))
              (should (eq selected (selected-window))))))))))

;; Pixel measurement is temporary even when the display primitive fails.
(ert-deftest dsh-emacs-test-markdown-table-measure-result-case-case ()
  :tags '(dsh-unit)
  (dolist (fail '(nil t))
    (dolist (modified '(nil t))
      (save-window-excursion
        (with-temp-buffer
          (buffer-enable-undo)
          (insert (propertize "draft 草稿" 'face 'italic))
          (goto-char 3)
          (setq-local face-remapping-alist '((default (:height 1.5) default)))
          (set-buffer-modified-p modified)
          (setq buffer-undo-list nil)
          (let* ((emacs-major-version 27)
                 (selected (selected-window))
                 (window (split-window-right))
                 (source (current-buffer))
                 (tick (buffer-chars-modified-tick))
                 (before (buffer-string))
                 (end (copy-marker (point-max) t))
                 (buffer-read-only t)
                 result caught)
            (set-window-buffer window (current-buffer))
            (cl-letf (((symbol-function 'window-text-pixel-size)
                       (lambda (_window from to &rest _)
                         (unless (and (not (eq (current-buffer) source))
                                      (equal face-remapping-alist
                                             (buffer-local-value
                                              'face-remapping-alist source))
                                      (equal (buffer-substring-no-properties from to)
                                             "probe 中文"))
                           (error "Wrong measurement range"))
                         (if fail (error "Measurement failed") '(42 . 10)))))
              (condition-case err
                  (setq result (dsh-emacs-markdown--table-measure-string
                                "probe 中文" window))
                (error (setq caught err))))
            (ert-info ((format "%s" (format "table-measure-result-%s-%s" fail modified)))
              (should (if fail (equal caught '(error "Measurement failed"))
                        (and (null caught) (= result 42)))))
            (ert-info ((format "%s" (format "table-measure-restores-draft-%s-%s" fail modified)))
              (should (equal-including-properties before (buffer-string)))
              (should (= tick (buffer-chars-modified-tick)))
              (should (eq (window-buffer window) source))
              (should (eq (selected-window) selected))
              (should (= (point) 3))
              (should (= end (1+ (length before))))
              (should (eq (buffer-modified-p) modified))
              (should (null buffer-undo-list))
              (should buffer-read-only))
            (set-marker end nil)))))))

(ert-deftest dsh-emacs-test-markdown-emphasis-keeps-real-left-context-case ()
  :tags '(dsh-unit)
  (dolist (text '("word*literal*" "word_underscore_" "word**literal**"))
    (with-temp-buffer
      (insert text)
      (dsh-emacs-markdown-replace-markup)
      (ert-info ((format "%s" (format "emphasis-keeps-real-left-context-%s" text)))
        (should (equal (buffer-substring-no-properties (point-min) (point-max)) text))))))

;; Plain text needs no emphasis passes, and repeated formatting is write-free.
(ert-deftest dsh-emacs-test-markdown-markdown-plain-text-skips-emphasis-passes ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (insert "plain 中文 text\nnext line")
    (let ((calls 0))
      (cl-letf (((symbol-function 'dsh-emacs-markdown--replace-bolds)
                 (lambda (&rest _) (cl-incf calls) nil))
                ((symbol-function 'dsh-emacs-markdown--replace-italics)
                 (lambda (&rest _) (cl-incf calls) nil))
                ((symbol-function 'dsh-emacs-markdown--replace-strikethroughs)
                 (lambda (&rest _) (cl-incf calls) nil)))
        (dsh-emacs-markdown-replace-markup))
      (ert-info ((format "%s" "markdown-plain-text-skips-emphasis-passes"))
        (should (= calls 0))
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       "plain 中文 text\nnext line"))))
    (let ((tick (buffer-modified-tick)))
      (dsh-emacs-markdown-replace-markup)
      (ert-info ((format "%s" "markdown-unchanged-plain-text-does-not-write"))
        (should (= tick (buffer-modified-tick)))))))

(ert-deftest dsh-emacs-test-markdown-markdown-yank-handler-inserts-plain-text ()
  :tags '(dsh-unit)
  (let ((styled (with-temp-buffer
                  (insert "**bold**")
                  (dsh-emacs-markdown-replace-markup)
                  (buffer-string))))
    (with-temp-buffer
      (insert-for-yank styled)
      (ert-info ((format "%s" "markdown-yank-handler-inserts-plain-text"))
        (should (equal (buffer-string) "bold"))
        (should (null (text-properties-at (point-min))))))))

;; --- Test 71: pure-function coverage reinforcement (markdown tables /
;; render-trim / tokens / http hint) ---
;; Pure-logic blind spots exposed by the coverage report
;; (scripts/check-coverage.el): markdown table allocation, display width,
;; longest word, render--trim boundaries, format-cost branches, usage-p,
;; http-error-hint.
(ert-deftest dsh-emacs-test-markdown-table-allocate-keeps-when-no-shrink ()
  :tags '(dsh-unit)
  (let ((pass-n 0))
    ;; markdown table: width allocation (verbatim when there is slack)
    (ert-info ((format "%s" "table-allocate-keeps-when-no-shrink"))
      (should (equal '(5 5) (dsh-emacs-markdown--table-allocate-widths '(5 5) '(2 2) 18))))
    ;; when compression is needed, allocate by shrinkable ratio, never below
    ;; min-widths
    (ert-info ((format "%s" "table-allocate-shrinks-to-fit"))
      (should (equal '(3 3 3) (dsh-emacs-markdown--table-allocate-widths '(10 10 10) '(3 3 3) 20))))
    ;; return min-widths directly when the shrinkable amount is 0
    (ert-info ((format "%s" "table-allocate-min-bound"))
      (should (equal '(10 3) (dsh-emacs-markdown--table-allocate-widths '(10 3) '(10 3) 10))))
    ;; total width = each column + 3 (padding both sides + separator pipe),
    ;; plus the leading pipe
    (ert-info ((format "%s" "table-total-width-counts-borders"))
      (should (= 15 (dsh-emacs-markdown--table-total-width '(4 4)))))
    ;; longest word (no window: the string-width path)
    (ert-info ((format "%s" "table-longest-word-ascii"))
      (should (= 9 (dsh-emacs-markdown--table-longest-word :str "alpha beta-long gamma"))))
    ;; longest word of an empty string = 0
    (ert-info ((format "%s" "table-longest-word-empty"))
      (should (= 0 (dsh-emacs-markdown--table-longest-word :str ""))))
    ;; display width: ASCII goes through string-width; Chinese counted by character
    (ert-info ((format "%s" "table-display-width-char-count"))
      (should (and (= 7 (dsh-emacs-markdown--table-display-width :str "abc def"))
                   (= 8 (dsh-emacs-markdown--table-display-width :str "中文测试")))))
    ;; render--trim: collapse whitespace + truncate with an ellipsis
    (ert-info ((format "%s" "render-trim-folds-and-ellipsizes"))
      (should (equal "hello …" (dsh-emacs-render--trim "  hello   world  " 6))))
    ;; render--trim: multi-line/tab collapsing
    (ert-info ((format "%s" "render-trim-folds-newlines"))
      (should (equal "…" (dsh-emacs-render--trim "a\nb\tc" 0))))
    ;; format-cost branches
    (ert-info ((format "%s" "format-cost-branches"))
      (should (and (equal "$0.000" (dsh-emacs-format-cost nil))
                   (equal "<$0.001" (dsh-emacs-format-cost 0.0005))
                   (equal "$0.000" (dsh-emacs-format-cost "x"))
                   (equal "$1.234" (dsh-emacs-format-cost 1.234)))))
    ;; http-error-hint: 4xx/5xx hint that the RPC does not exist, other codes
    ;; short form, non-error empty
    (ert-info ((format "%s" "http-error-hint-branches"))
      (should (and (string-match-p "HTTP 404" (dsh-emacs--http-error-hint '(error http 404)))
                   (string-match-p "HTTP 500" (dsh-emacs--http-error-hint '(error http 500)))
                   (equal " (HTTP 302)" (dsh-emacs--http-error-hint '(error http 302)))
                   (equal "" (dsh-emacs--http-error-hint nil)))))
    pass-n))

;; Code blocks reuse one fontification buffer per mode: the mode is set up
;; once, and a previous block's text or faces never leak into the next.
(ert-deftest dsh-emacs-test-markdown-markdown-highlight-reuses-mode-buffer ()
  :tags '(dsh-unit)
  (let* ((buffer (get-buffer " *dsh-emacs-markdown-fontify:emacs-lisp-mode*"))
         (setups 0)
         (count (lambda (&rest _) (cl-incf setups))))
    (when buffer (kill-buffer buffer))
    (advice-add 'emacs-lisp-mode :before count)
    (unwind-protect
        (let* ((first (dsh-emacs-markdown--highlight-code "\"open string" "elisp"))
               (second (dsh-emacs-markdown--highlight-code "(foo)" "elisp")))
          (ert-info ((format "%s" "markdown-highlight-reuses-mode-buffer"))
            (should (= setups 1))
            (should (memq 'font-lock-string-face
                          (ensure-list (get-text-property 1 'face first))))
            (should (equal-including-properties
                     second (dsh-emacs-markdown--highlight-code "(foo)" "emacs-lisp")))
            (should (string= second "(foo)"))
            (should (not (memq 'font-lock-string-face
                               (ensure-list (get-text-property 1 'face second)))))))
      (advice-remove 'emacs-lisp-mode count))))

;; Emacs draws adjacent characters whose `display' values are `eq' once, so
;; nested `>>' would collapse into a single bar if both shared one object.
(ert-deftest dsh-emacs-test-markdown-markdown-nested-blockquote-bars-stay-distinct ()
  :tags '(dsh-unit)
  (let* ((rendered (dsh-emacs-markdown-render ">> nested\n"))
         (first (get-text-property 0 'display rendered))
         (second (get-text-property 1 'display rendered)))
    (ert-info ((format "%s" "markdown-nested-blockquote-bars-stay-distinct"))
      (should (stringp first))
      (should (equal first second))
      (should (not (eq first second))))))

;; Extensions are deliberately prefix-distinct: `regexp-opt' factors a common
;; prefix ("aaaimg" "bbimg" compile to \(?:aaa\|bb\)img), so a literal
;; extension must survive in the compiled regexp for the checks below.
(ert-deftest dsh-emacs-test-markdown-markdown-image-path-regexp-cache ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-markdown--image-path-regexp nil)
        (image-file-name-extensions (list "zzimg")))
    (with-temp-buffer
      (dsh-emacs-markdown--replace-image-file-paths)
      (let ((cached dsh-emacs-markdown--image-path-regexp))
        (dsh-emacs-markdown--replace-image-file-paths)
        (let ((reused (eq cached dsh-emacs-markdown--image-path-regexp)))
          (setq image-file-name-extensions (list "yyimg"))
          (dsh-emacs-markdown--replace-image-file-paths)
          (ert-info ((format "%s" "markdown-image-path-regexp-cache"))
            (should reused)
            (should (string-match-p "zzimg" (cdr cached)))
            (should (string-match-p "yyimg" (cdr dsh-emacs-markdown--image-path-regexp)))
            (should (not (string-match-p
                          "zzimg" (cdr dsh-emacs-markdown--image-path-regexp))))))))))

(ert-deftest dsh-emacs-test-markdown-markdown-image-path-regexp-cache-tracks-edits ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-markdown--image-path-regexp nil)
        (image-file-name-extensions (list "qqimg" "wwimg")))
    (dsh-emacs-markdown--replace-image-file-paths)   ; warm the cache
    (let ((first (cdr dsh-emacs-markdown--image-path-regexp)))
      ;; Ordinary configuration: a new list object with the same contents.
      (setq image-file-name-extensions (list "qqimg" "wwimg"))
      (dsh-emacs-markdown--replace-image-file-paths)
      ;; In-place mutation of the very list the cache was built from: the
      ;; variable still reads `qqimg', so keying the cache on identity would
      ;; serve the regexp above and never learn about `eeimg'.
      (setcar (cdr image-file-name-extensions) "eeimg")
      (dsh-emacs-markdown--replace-image-file-paths)
      (let ((rebuilt (cdr dsh-emacs-markdown--image-path-regexp)))
        (ert-info ((format "%s" "markdown-image-path-regexp-cache-tracks-edits"))
          (should (and (string-match-p rebuilt "/tmp/pic.qqimg") t))
          (should (not (string-match-p rebuilt "/tmp/pic.wwimg")))
          (should (and (string-match-p rebuilt "/tmp/pic.eeimg") t)))))))

;; --- Test 72: markdown parsing layer pure-function reinforcement (coverage
;; report class A blind spots) ---
;; Target: deconstruct / highlight-code / table-min-widths / shorten-cwd /
;; insert-read-only / resolve-image-url / parse-local-link (needs temp files).
(ert-deftest dsh-emacs-test-markdown-markdown-deconstruct-splits-face-runs ()
  :tags '(dsh-unit)
  (let ((tmpdir (make-temp-file "dsh-cov" t)))
    (unwind-protect
        (progn
          ;; markdown--deconstruct: splitting into contiguous face runs
          (ert-info ((format "%s" "markdown-deconstruct-splits-face-runs"))
            (should (equal '(("my" (dsh-emacs-markdown-italic))
                             (" " nil)
                             ("text" (dsh-emacs-markdown-bold)))
                           (dsh-emacs-markdown--deconstruct
                            (dsh-emacs-markdown-convert "_my_ **text**")))))
          ;; highlight-code: a real mode (elisp) font-locks the face,
          ;; unknown language verbatim
          (let ((hl (dsh-emacs-markdown--highlight-code "(defun f () 1)" "elisp")))
            (ert-info ((format "%s" "markdown-highlight-elisp-applies-face"))
              (should (and (string= hl "(defun f () 1)")
                           (get-text-property 1 'face hl)))))
          (ert-info ((format "%s" "markdown-highlight-unknown-lang-pass-through"))
            (should (equal "abc" (dsh-emacs-markdown--highlight-code "abc" "nolangxyz"))))
          ;; table-min-widths: longest word per column
          (ert-info ((format "%s" "markdown-table-min-widths-longest-word"))
            (should (equal '(6 3)
                           (dsh-emacs-markdown--table-min-widths
                            :processed-rows '(("hdr" "a b" "ccc")
                                              ("row" "longer" "dd"))))))
          ;; shorten-cwd: home prefix -> ~, deep path -> ../last two segments
          (ert-info ((format "%s" "shorten-cwd-home-prefix"))
            (should (equal "~/src/foo"
                           (dsh-emacs-session--shorten-cwd
                            (format "%s/src/foo" (expand-file-name "~"))))))
          (ert-info ((format "%s" "shorten-cwd-deep-path"))
            (should (equal "../d/e" (dsh-emacs-session--shorten-cwd "/a/b/c/d/e"))))
          ;; insert-read-only: text carries read-only + face properties
          (with-temp-buffer
            (dsh-emacs-render--insert-read-only "hi" 'dsh-emacs-test-face)
            (ert-info ((format "%s" "render-insert-read-only-props"))
              (should (and (equal t (get-text-property 1 'read-only))
                           (eq 'dsh-emacs-test-face (get-text-property 1 'face))))))
          ;; resolve-image-url: local file in its various forms,
          ;; nil when it does not exist
          (let ((f (expand-file-name "img.png" tmpdir)))
            (with-temp-file f)
            (ert-info ((format "%s" "resolve-image-url-file-uri"))
              (should (equal f (dsh-emacs-markdown--resolve-image-url
                                (concat "file://" f)))))
            (ert-info ((format "%s" "resolve-image-url-absolute"))
              (should (equal f (dsh-emacs-markdown--resolve-image-url f))))
            (ert-info ((format "%s" "resolve-image-url-missing-nil"))
              (should (null (dsh-emacs-markdown--resolve-image-url
                             (concat tmpdir "/missing.png"))))))
          ;; parse-local-link: file:// URI, file: prefix,
          ;; relative path + line number, nil for non-local
          (let ((f (expand-file-name "foo.el" tmpdir)))
            (with-temp-file f)
            (let ((parsed (dsh-emacs-markdown--parse-local-link
                           (concat f "#L10"))))
              (ert-info ((format "%s" "parse-local-link-hash-line"))
                (should (and (equal (expand-file-name f) (car parsed))
                             (equal 10 (cdr parsed))))))
            (let ((parsed (dsh-emacs-markdown--parse-local-link
                           (concat "file://" f ":5"))))
              (ert-info ((format "%s" "parse-local-link-file-colon"))
                (should (and (equal (expand-file-name f) (car parsed))
                             (equal 5 (cdr parsed))))))
            (ert-info ((format "%s" "parse-local-link-remote-nil"))
              (should (null (dsh-emacs-markdown--parse-local-link
                             "https://example.com/path"))))))
      (delete-directory tmpdir t))))

;; Markdown destinations in angle brackets are syntax, not part of the path.
;; Exercise the rendered RET command, including a destination containing `)'.
(ert-deftest dsh-emacs-test-markdown-markdown-angle-link-label-case ()
  :tags '(dsh-unit)
  (let ((directory (make-temp-file "dsh-link" t)))
    (unwind-protect
        (dolist (name '("source.el" "source (draft).el"))
          (let ((file (expand-file-name name directory)))
            (with-temp-file file (insert "first\nsecond\nthird\n"))
            (with-temp-buffer
              (insert (dsh-emacs-markdown-convert
                       (format "[source](<%s#L2>)" file)))
              (goto-char (point-min))
              (let ((command (lookup-key (get-text-property (point) 'keymap)
                                         (kbd "RET")))
                    opened browsed)
                (ert-info ((format "%s" (format "markdown-angle-link-label-%s" name)))
                  (should (equal (buffer-string) "source")))
                (cl-letf (((symbol-function 'find-file)
                           (lambda (path &rest _)
                             (setq opened path)
                             (erase-buffer)
                             (insert-file-contents path)))
                          ((symbol-function 'browse-url)
                           (lambda (url &rest _) (setq browsed url))))
                  (call-interactively command))
                (ert-info ((format "%s" (format "markdown-angle-link-ret-%s" name)))
                  (should (equal opened file))
                  (should (null browsed))
                  (should (= (line-number-at-pos) 2)))))))
      (delete-directory directory t))))

(ert-deftest dsh-emacs-test-markdown-line-range-links-open-locally ()
  :tags '(dsh-unit)
  (let* ((directory (make-temp-file "dsh-link-range" t))
         (file (expand-file-name "source.el" directory)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "first\nsecond\nthird\nfourth\n"))
          (dolist (target (list "source.el#L2-L3" "source.el#L2-3"
                                "source.el:2-3" "file:source.el#L2-L3"
                                (concat file "#L2-L3")
                                (concat "file://" file "#L2-L3")
                                (concat "file://" file ":2-3")))
            (ert-info ((format "line-range target: %s" target))
              (with-temp-buffer
                (setq default-directory (file-name-as-directory directory))
                (insert (dsh-emacs-markdown-convert
                         (format "[`some-function`](<%s>)" target)))
                (goto-char (point-min))
                (should (equal (buffer-string) "some-function"))
                (let ((command (lookup-key
                                (get-text-property (point) 'keymap)
                                (kbd "RET")))
                      opened browsed)
                  (should (commandp command))
                  (cl-letf (((symbol-function 'find-file)
                             (lambda (path &rest _)
                               (setq opened path)
                               (erase-buffer)
                               (insert-file-contents path)))
                            ((symbol-function 'browse-url)
                             (lambda (url &rest _) (setq browsed url))))
                    (call-interactively command))
                  (should (equal opened file))
                  (should-not browsed)
                  (should (= (line-number-at-pos) 2))
                  (should (equal (buffer-substring
                                  (line-beginning-position) (line-end-position))
                                 "second")))))))
      (delete-directory directory t))))

;; Table wrapping must measure each character once, retaining layout and faces.
(ert-deftest dsh-emacs-test-markdown-table-wrap-single-measure-case ()
  :tags '(dsh-unit)
  (dolist (case '(("alpha beta gamma" 8 ("alpha" "beta" "gamma"))
                  ("你好世界 hello" 5 ("你好" "世界" "hello"))
                  ("a⚠️ b" 3 ("a⚠️" "b"))
                  ("abcdefgh" 3 ("abc" "def" "gh"))
                  ("a\tb" 4 ("a" "b"))
                  ("á b" 2 ("á" "b"))
                  ("ab  " 10 ("ab  "))
                  ("界" 1 ("界"))
                  ("" 4 (""))))
    (pcase-let ((`(,text ,width ,expected) case))
      (let ((calls 0)
            (measure (symbol-function 'dsh-emacs-markdown--table-wrap-char-width)))
        (cl-letf (((symbol-function 'dsh-emacs-markdown--table-wrap-char-width)
                   (lambda (&rest args)
                     (setq calls (1+ calls))
                     (apply measure args))))
          (ert-info ((format "%s" (format "table-wrap-single-measure-%S" text)))
            (should (equal (dsh-emacs-markdown--table-wrap-text text width) expected))
            (should (= calls (length text)))))))))

(ert-deftest dsh-emacs-test-markdown-table-wrap-preserves-face-dependent-width-and-properties ()
  :tags '(dsh-unit)
  (let* ((styled (propertize "WW" 'face 'bold))
         (text (concat styled " xx")))
    (cl-letf (((symbol-function 'dsh-emacs-markdown--table-wrap-char-width)
               (lambda (str pos &optional _window)
                 (if (get-text-property pos 'face str) 2 1))))
      (ert-info ((format "%s" "table-wrap-preserves-face-dependent-width-and-properties"))
        (should (equal-including-properties
                 (dsh-emacs-markdown--table-wrap-text text 4)
                 (list styled "xx")))))))

(provide 'dsh-test-markdown)
;;; dsh-test-markdown.el ends here

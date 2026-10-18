;;; dsh-test-runner-test.el --- ERT runner contract tests -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "28.1"))
;;; Usage: emacs -Q --batch -l test/dsh-test-runner-test.el

(require 'cl-lib)
(require 'ert)

(defconst dsh-emacs-test-runner--root
  (expand-file-name ".." (file-name-directory load-file-name)))

(defun dsh-emacs-test-runner--probe (source &optional before after coverage)
  "Run the real runner against SOURCE in a fresh Emacs and temporary tree.
BEFORE and AFTER are lists of forms evaluated around loading the runner.
With COVERAGE, load the real coverage entry point instead of the runner.
Return (EXIT-STATUS . OUTPUT); never load or run the real unit suite."
  (let* ((root (make-temp-file "dsh-runner-test-" t))
         (test-dir (expand-file-name "test/" root))
         (runner (expand-file-name "dsh-test.el" test-dir))
         (output (generate-new-buffer " *dsh-runner-test*")))
    (unwind-protect
        (progn
          (make-directory test-dir)
          (copy-file (expand-file-name "test/dsh-test.el"
                                       dsh-emacs-test-runner--root)
                     runner)
          (with-temp-file (expand-file-name "dsh-test-support.el" test-dir)
            (insert ";;; -*- lexical-binding: t; -*-\n"
                    "(require 'cl-lib)\n(require 'ert)\n")
            (prin1 `(defconst dsh-emacs-test-directory ,test-dir)
                   (current-buffer))
            (insert "\n")
            (prin1 `(defconst dsh-emacs-test-root ,root) (current-buffer))
            (insert "\n(provide 'dsh-test-support)\n"))
          (with-temp-file (expand-file-name "dsh-test-probe.el" test-dir)
            (insert ";;; -*- lexical-binding: t; -*-\n"
                    "(require 'dsh-test-support)\n" source
                    "\n(provide 'dsh-test-probe)\n"))
          (dolist (file '("dsh-test-runner-test.el" "dsh-e2e.el"))
            (with-temp-file (expand-file-name file test-dir)
              (insert "(error \"Not a unit subsystem\")\n")))
          (when coverage
            (setq before
                  (append `((setq dsh-cov:root ,root
                                  dsh-cov:product-files nil))
                          before)))
          (let ((status
                 (apply #'call-process
                        (expand-file-name invocation-name invocation-directory)
                        nil (list output t) nil
                        (append
                         '("-Q" "--batch")
                         (when before
                           (list "--eval" (prin1-to-string (cons 'progn before))))
                         (list "-l" (if coverage
                                        (expand-file-name "scripts/check-coverage.el"
                                                          dsh-emacs-test-runner--root)
                                      runner))
                         (when after
                           (list "--eval" (prin1-to-string (cons 'progn after))))))))
            (cons status (with-current-buffer output (buffer-string)))))
      (kill-buffer output)
      (delete-directory root t))))

(ert-deftest dsh-emacs-test-runner-batch-pass ()
  :tags '(dsh-runner)
  (pcase-let ((`(,status . ,output)
               (dsh-emacs-test-runner--probe
                "(ert-deftest dsh-emacs-test-probe ()
  :tags '(dsh-unit)
  (should (= (+ 1 2) 3))
  (princ \"PROBE-PASSED\\n\"))")))
    (should (equal status 0))
    (should (string-match-p "PROBE-PASSED" output))))

(ert-deftest dsh-emacs-test-runner-failure-survives-later-pass ()
  :tags '(dsh-runner)
  (dolist (failure '("(should nil)" "(error \"probe error\")"))
    (ert-info ((format "Failure form: %s" failure))
      (pcase-let ((`(,status . ,output)
                   (dsh-emacs-test-runner--probe
                    (concat
                     "(ert-deftest dsh-emacs-test-probe-a-fail ()
  :tags '(dsh-unit) " failure ")
(ert-deftest dsh-emacs-test-probe-z-pass ()
  :tags '(dsh-unit) (princ \"LATER-PASSED\\n\") (should t))"))))
        (should (equal status 1))
        (should (string-match-p "LATER-PASSED" output))
        (should (string-match-p "dsh-emacs-test-probe-a-fail" output))))))

(ert-deftest dsh-emacs-test-runner-empty-or-broken-suite-fails ()
  :tags '(dsh-runner)
  (dolist (source '("" "(require 'dsh-missing-runner-probe-library)"))
    (ert-info ((format "Subsystem source: %S" source))
      (pcase-let ((`(,status . ,output)
                   (dsh-emacs-test-runner--probe source)))
        (should (integerp status))
        (should-not (zerop status))
        (should-not (string-match-p "0 unexpected" output))))))

(ert-deftest dsh-emacs-test-runner-load-and-select ()
  :tags '(dsh-runner)
  (pcase-let ((`(,status . ,output)
               (dsh-emacs-test-runner--probe
                "(ert-deftest dsh-emacs-test-probe-selected ()
  :tags '(dsh-unit) (princ \"SELECTED-RAN\\n\") (should t))
(ert-deftest dsh-emacs-test-probe-not-selected ()
  :tags '(dsh-unit) (error \"Unselected body ran\"))"
                '((setq dsh-emacs-test-no-run t))
                '((unless (ert-test-boundp 'dsh-emacs-test-probe-selected)
                    (error "No-run did not register tests"))
                  (setq dsh-emacs-test-no-run nil)
                  (let ((noninteractive nil))
                    (load (expand-file-name "dsh-test.el"
                                            dsh-emacs-test-directory) nil t))
                  (princ "INTERACTIVE-LOAD-RETURNED\n")
                  (let ((stats (dsh-emacs-test-run
                                'dsh-emacs-test-probe-selected)))
                    (unless (and (= (ert-stats-completed-expected stats) 1)
                                 (= (ert-stats-completed-unexpected stats) 0))
                      (error "Incorrect selected-test statistics")))
                  (princ "RUN-RETURNED\n")))))
    (should (equal status 0))
    (should (string-match-p "INTERACTIVE-LOAD-RETURNED" output))
    (should (string-match-p "SELECTED-RAN" output))
    (should (string-match-p "RUN-RETURNED" output))
    (should-not (string-match-p "Unselected body ran" output))))

(ert-deftest dsh-emacs-test-runner-empty-selector-fails ()
  :tags '(dsh-runner)
  (pcase-let ((`(,status . ,output)
               (dsh-emacs-test-runner--probe
                "(ert-deftest dsh-emacs-test-probe () :tags '(dsh-unit) (should t))"
                '((setq dsh-emacs-test-no-run t))
                '((dsh-emacs-test-run "^dsh-no-such-test-")
                  (princ "EMPTY-SELECTION-RETURNED\n")))))
    (should (integerp status))
    (should-not (zerop status))
    (should-not (string-match-p "^EMPTY-SELECTION-RETURNED$" output))))

(ert-deftest dsh-emacs-test-runner-coverage-reports-before-exit ()
  :tags '(dsh-runner)
  (dolist (case '(("(should t)" . 0)
                  ("(should nil)" . 1)
                  ("(error \"coverage probe error\")" . 1)))
    (ert-info ((format "Coverage test body: %s" (car case)))
      (pcase-let ((`(,status . ,output)
                   (dsh-emacs-test-runner--probe
                    (concat
                     "(ert-deftest dsh-emacs-test-probe-a-first ()
  :tags '(dsh-unit) " (car case) ")
(ert-deftest dsh-emacs-test-probe-z-last ()
  :tags '(dsh-unit) (princ \"COVERAGE-TEST-RAN\\n\") (should t))")
                    nil nil t)))
        (should (equal status (cdr case)))
        (should (string-match-p "COVERAGE-TEST-RAN" output))
        (should (string-match-p "=== coverage report (all defs) ===" output))
        (should (string-match-p "TOTAL: 0/0 points covered" output))))))

(when noninteractive
  (ert-run-tests-batch-and-exit '(tag dsh-runner)))

;;; dsh-test-runner-test.el ends here

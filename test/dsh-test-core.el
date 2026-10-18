;;; dsh-test-core.el --- Core tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

;; --- Test 1: module loading ---
(ert-deftest dsh-emacs-test-core-dsh-emacs-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs loaded"))
    (should (featurep 'dsh-emacs))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-faces-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-faces loaded"))
    (should (featurep 'dsh-emacs-faces))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-tokens-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-tokens loaded"))
    (should (featurep 'dsh-emacs-tokens))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-render-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-render loaded"))
    (should (featurep 'dsh-emacs-render))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-modeline-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-modeline loaded"))
    (should (featurep 'dsh-emacs-modeline))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-session-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-session loaded"))
    (should (featurep 'dsh-emacs-session))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-markdown-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-markdown loaded"))
    (should (featurep 'dsh-emacs-markdown))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-command-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-command loaded"))
    (should (featurep 'dsh-emacs-command))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-skill-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-skill loaded"))
    (should (featurep 'dsh-emacs-skill))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-reference-loaded ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-reference loaded"))
    (should (featurep 'dsh-emacs-reference))))

;; --- Test 12: main entry functions ---
(ert-deftest dsh-emacs-test-core-dsh-emacs-main-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs main function exists"))
    (should (fboundp 'dsh-emacs))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-new-session-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-new-session function exists"))
    (should (fboundp 'dsh-emacs-new-session))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-open-session-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-open-session function exists"))
    (should (fboundp 'dsh-emacs-open-session))))

(ert-deftest dsh-emacs-test-core-dsh-emacs-health-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "dsh-emacs-health function exists"))
    (should (fboundp 'dsh-emacs-health))))

;; --- Test 13: RPC functions ---
(ert-deftest dsh-emacs-test-core-rpc-request-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "rpc-request function exists"))
    (should (fboundp 'dsh-emacs--rpc-request))))

(ert-deftest dsh-emacs-test-core-rpc-async-function-exists ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "rpc-async function exists"))
    (should (fboundp 'dsh-emacs--rpc-async))))

(provide 'dsh-test-core)
;;; dsh-test-core.el ends here

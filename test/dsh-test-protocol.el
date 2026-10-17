;;; dsh-test-protocol.el --- Protocol tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))

(require 'dsh-test-support)

;; --- Test 57: protocol layer workspace baseline / workspace-result
;; / model-selection-result ---
;; workspace/follow baseline top-level values: items array->list,
;; archivedSessionIds array->list
(ert-deftest dsh-emacs-test-protocol-protocol-workspace-list-conversion ()
  :tags '(dsh-unit)
  (let* ((value '((items . [((workspaceId . "w1") (title . "WS A")
                             (path . "/tmp/a") (sessionIds . ["s1" "s2"])
                             (createdAt . "2026-08-25T00:00:00Z")
                             (updatedAt . "2026-08-25T01:00:00Z"))
                            ((workspaceId . "w2") (title . "WS B")
                             (path . "/tmp/b") (sessionIds . []))])
                  (archivedSessionIds . ["s9"])))
         (wl (dsh-protocol-workspace-list--from-alist value))
         (items (dsh-protocol-workspace-list-items wl))
         (w1 (car items)))
    (ert-info ((format "%s" "protocol-workspace-list-conversion"))
      (should (and (= (length items) 2)
                   (equal (dsh-protocol-workspace-list-archived-session-ids wl)
                          '("s9"))
                   ;; items converted inline + arrays normalized to lists
                   (dsh-protocol-workspace-p w1)
                   (equal (dsh-protocol-workspace-session-ids w1) '("s1" "s2"))
                   ;; WorkspaceView official fields complete
                   (string= (dsh-protocol-workspace-title w1) "WS A")
                   (string= (dsh-protocol-workspace-created-at w1)
                            "2026-08-25T00:00:00Z")
                   (string= (dsh-protocol-workspace-updated-at w1)
                            "2026-08-25T01:00:00Z")
                   (string= (dsh-protocol-workspace-path w1) "/tmp/a")
                   (string= (dsh-protocol-workspace-workspace-id
                             (car (dsh-protocol-workspace-list-items
                                   (dsh-protocol-workspace-list--from-alist
                                    '((items . [((workspaceId . "w2"))]))))))
                            "w2"))))))

;; workspace/create response: {workspace, created}
(ert-deftest dsh-emacs-test-protocol-protocol-workspace-create-result ()
  :tags '(dsh-unit)
  (let* ((value '((workspace . ((workspaceId . "w3") (title . "New")
                                (path . "/tmp/new") (sessionIds . [])
                                (createdAt . "x") (updatedAt . "y")))
                  (created . t)))
         (r (dsh-protocol-workspace-result--from-alist value)))
    (ert-info ((format "%s" "protocol-workspace-create-result"))
      (should (and (dsh-protocol-workspace-p (dsh-protocol-workspace-result-workspace r))
                   (eq (dsh-protocol-workspace-result-created r) t)
                   (string= (dsh-protocol-workspace-title
                             (dsh-protocol-workspace-result-workspace r))
                            "New"))))))

;; workspace/rename / insertSessionBefore response: only {workspace},
;; created is nil
(ert-deftest dsh-emacs-test-protocol-protocol-workspace-rename-result ()
  :tags '(dsh-unit)
  (let* ((r (dsh-protocol-workspace-result--from-alist
             '((workspace . ((workspaceId . "w1") (title . "Renamed"))))))
         (d (dsh-protocol-workspace-result-created r)))
    (ert-info ((format "%s" "protocol-workspace-rename-result"))
      (should (and (string= (dsh-protocol-workspace-title
                             (dsh-protocol-workspace-result-workspace r))
                            "Renamed")
                   (null d))))))

;; session/selectModel response: {selected}
(ert-deftest dsh-emacs-test-protocol-protocol-model-selection-result ()
  :tags '(dsh-unit)
  (let* ((r (dsh-protocol-model-selection-result--from-alist
             '((selected . ((provider . "deepseek")
                            (model . "deepseek-chat")
                            (reasoningEffort . "high"))))))
         (sel (dsh-protocol-model-selection-result-selected r)))
    (ert-info ((format "%s" "protocol-model-selection-result"))
      (should (and (dsh-protocol-model-selection-p sel)
                   (string= (dsh-protocol-model-selection-provider sel) "deepseek")
                   (string= (dsh-protocol-model-selection-model sel) "deepseek-chat")
                   (string= (dsh-protocol-model-selection-reasoning-effort sel)
                            "high"))))))

(provide 'dsh-test-protocol)
;;; dsh-test-protocol.el ends here

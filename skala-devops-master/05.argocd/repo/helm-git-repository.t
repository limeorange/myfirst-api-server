apiVersion: v1
kind: Secret
metadata:
  name: {{USER_NAME}}-helm-myapp-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  name: {{USER_NAME}}-myapp-helm
  type: git
  url: https://{{GIT_REPO_URL}}
  username: {{GIT_USERNAME}}
  project: {{NAMESPACE}}
  password: {{GIT_PASSWORD}}

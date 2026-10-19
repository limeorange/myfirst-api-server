apiVersion: v1
kind: Secret
metadata:
  name: {{USER_NAME}}-myapp-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  name: {{USER_NAME}}-myapp
  type: git
  url: https://{{GIT_REPO_URL}}
  username: {{GIT_USERNAME}}
  project: {{NAMESPACE}}
  password: {{GIT_PASSWORD}}

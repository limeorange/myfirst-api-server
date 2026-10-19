apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{USER_NAME}}-myapp-helm
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io/foreground
spec:
  destination:
    namespace: {{NAMESPACE}}
    server: https://{{EKS_SERVER_URL}}
  project: {{NAMESPACE}}
  source:
    repoURL: https://{{GIT_REPO_URL}}
    targetRevision: HEAD
    path: .
    helm:
      valueFiles:
        - custom-values.yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - PrunePropagationPolicy=background

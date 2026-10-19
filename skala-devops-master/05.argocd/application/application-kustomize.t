apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{USER_NAME}}-myapp-kustomize
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io/foreground
spec:
  destination:
    namespace: {{NAMESPACE}}
    server: https://{{EKS_SERVER_URL}}
  project: {{NAMESPACE}}
  source:
    path: kustomize/overlays/dev
    repoURL: https://{{GIT_REPO_URL}}
    targetRevision: gitops        # 예: HEAD, main, gitops 등
    kustomize: {}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - PrunePropagationPolicy=background

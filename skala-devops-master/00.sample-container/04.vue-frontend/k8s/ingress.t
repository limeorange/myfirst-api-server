apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
#  annotations:
#    cert-manager.io/cluster-issuer: letsencrypt-prod
  name: {{USER_NAME}}-cert-ingress
  namespace: {{NAMESPACE}}
  labels:
    app: {{USER_NAME}}-cert-ingress
spec:
  ingressClassName: {{INGRESS_CLASS_NAME}}
  rules:
    - host: {{USER_NAME}}-ingress.{{NAMESPACE}}.skala-{{LOCATION}}.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: {{USER_NAME}}-myfirst-api-server
                port:
                  number: 8080
          - path: /python
            pathType: Prefix
            backend:
              service:
                name: {{USER_NAME}}-myfirst-api-server
                port:
                  number: 8080
          - path: /actuator
            pathType: Prefix
            backend:
              service:
                name: {{USER_NAME}}-myfirst-api-server
                port:
                  number: 8080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{USER_NAME}}-frontend
                port:
                  number: 8080
  tls:
  - hosts:
    - '{{USER_NAME}}-cert-ingress.{{NAMESPACE}}.skala-{{LOCATION}}.com'
    secretName: wildcard-{{NAMESPACE}}-skala-{{LOCATION}}-com-tls

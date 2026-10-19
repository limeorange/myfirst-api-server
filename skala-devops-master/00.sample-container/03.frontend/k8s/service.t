# 03.frontend Service
# - Ingress가 트래픽을 전달할 대상. 클러스터 내부용 ClusterIP로 충분하다.
apiVersion: v1
kind: Service
metadata:
  name: {{USER_NAME}}-frontend
  namespace: {{NAMESPACE}}
spec:
  type: ClusterIP
  selector:
    app: {{USER_NAME}}-frontend
  ports:
    - name: http
      port: 8080
      targetPort: 80

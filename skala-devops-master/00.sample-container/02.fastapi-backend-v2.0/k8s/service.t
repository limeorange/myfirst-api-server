# 02.fastapi-backend-v2.0 Service
# - 01.spring-backend-v1.0/k8s/service.yaml과 동일한 ClusterIP 구성이며, 이름(라벨)만 "backend-v2"로 다르게 한다.
# - 참고: 03.frontend의 system.html은 이 Service를 거치지 않고 브라우저가 02를 "직접" 호출한다(CORS 방식).
#   이 Service는 클러스터 내부의 다른 컴포넌트가 02를 호출할 때 backend-v2:8080 으로 사용하면 된다.
apiVersion: v1
kind: Service
metadata:
  name: {{USER_NAME}}-myfirst-api-server
  namespace: {{NAMESPACE}}
spec:
  type: ClusterIP
  selector:
    app: {{USER_NAME}}-myfirst-api-server
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: mgmt
      port: 8081
      targetPort: 8081
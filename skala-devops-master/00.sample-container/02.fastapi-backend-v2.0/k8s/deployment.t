# 02.fastapi-backend-v2.0 Deployment
# - REST API 서버(FastAPI)를 k8s에 배포하기 위한 정의
# - 구조는 01.spring-backend-v1.0/k8s/deployment.yaml과 동일하고, 이름(라벨)만 "backend-v2"로 다르게 한다.
# - image 값은 docker-push.sh로 올린 이미지 주소로 바꿔서 사용한다.
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    prometheus.io/scrape: 'true'
    prometheus.io/port: '8080'
    prometheus.io/path: '/python/prometheus'
    update: {{HASHCODE}}
  name: {{USER_NAME}}-myfirst-api-server
  namespace: {{NAMESPACE}}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{USER_NAME}}-myfirst-api-server
  template:
    metadata:
      labels:
        app: {{USER_NAME}}-myfirst-api-server
    spec:
      containers:
        - name: fastapi
          image: {{DOCKER_REGISTRY}}/{{PROJECT_NAME}}/{{USER_NAME}}-webserver:2.0
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          # 준비(readiness)가 끝나기 전에는 Service가 트래픽을 보내지 않는다.
          readinessProbe:
            httpGet:
              path: /python/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          # 살아있는지(liveness) 계속 실패하면 컨테이너를 재시작한다.
          livenessProbe:
            httpGet:
              path: /python/health/liveness
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 10

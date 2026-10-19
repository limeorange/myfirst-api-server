#!/bin/bash

IMAGE_NAME="webserver"
VERSION=2.0
IMG_TAG=kaniko

USER_NAME=${STUDENT_NUM}
PROJECT_NAME=${CLASS_NAME}
DOCKER_REGISTRY=${DOCKER_REGISTRY}
IMAGE_REF="${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${VERSION}.${IMG_TAG}"


# 인증 설정 파일 생성
mkdir -p auth
cat > auth/config.json <<EOF
{
  "auths": {
    "${DOCKER_REGISTRY}": {
      "username": "${DOCKER_REGISTRY_USER}",
      "password": "${DOCKER_REGISTRY_PASSWORD}",
      "auth": "$(echo -n "$DOCKER_REGISTRY_USER:$DOCKER_REGISTRY_PASSWORD" | base64)"
    }
  }
}
EOF


# docker run으로 kaniko 실행
# gcr.io/kaniko-project/executor:latest \
docker run --rm \
  -v "$(pwd):/workspace" \
  -v "$(pwd)/auth/config.json:/kaniko/.docker/config.json" \
  gcr.io/kaniko-project/executor:latest \
  --dockerfile=/workspace/Dockerfile \
  --context=dir:///workspace \
  --destination="${IMAGE_REF}" \
  --custom-platform=linux/amd64

# 정리
#rm -rf auth

#!/usr/bin/env bash

set -euo pipefail

IMAGE_NAME="webserver"
VERSION=2.0
IMG_TAG=buildkit

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

echo "BuildKit 멀티 플랫폼 빌드 및 푸시: ${IMAGE_REF} (linux/arm64, linux/amd64)"
docker run --rm \
  --privileged \
  --security-opt seccomp=unconfined \
  -e DOCKER_CONFIG=/home/user/.docker \
  -v "$(pwd):/workspace:ro" \
  -v "$(pwd)/auth:/home/user/.docker:ro" \
  --entrypoint buildctl-daemonless.sh \
  moby/buildkit:latest \
    build \
    --frontend dockerfile.v0 \
    --local context=/workspace \
    --local dockerfile=/workspace \
    --opt platform=linux/arm64,linux/amd64 \
    --output "type=image,name=${IMAGE_REF},push=true"

# 정리
rm -rf auth

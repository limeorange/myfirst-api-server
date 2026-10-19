#!/bin/bash
USER_NAME=${STUDENT_NUM}
IMAGE_NAME="custom-jenkins"
VERSION="1.0"
IS_CACHE="--no-cache"

# Kubernetes 설정 파일 복사
cp $HOME/.kube/config kube-config

# Docker 이미지 빌드
docker buildx build \
  --tag ${USER_NAME}-${IMAGE_NAME}:${VERSION} \
  --file Dockerfile \
  --platform linux/amd64,linux/arm64 \
  ${IS_CACHE} .

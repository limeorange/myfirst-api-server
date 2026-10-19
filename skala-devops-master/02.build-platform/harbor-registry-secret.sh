#!/bin/bash

NAMESPACE=${CLASS_NAME}

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=${DOCKER_REGISTRY} \
  --docker-username=${DOCKER_REGISTRY_USER} \
  --docker-password=${DOCKER_REGISTRY_PASSWORD} \
  --docker-email=dev@skala.ai \
  --namespace ${NAMESPACE}
#!/bin/bash

USER_NAME=${STUDENT_NUM}
NAMESPACE=${CLASS_NAME}

kubectl create configmap ${USER_NAME}-app-workspace \
  --from-file=Dockerfile=./Dockerfile \
  --from-file=fastserver.py=./fastserver.py \
  --namespace ${NAMESPACE}

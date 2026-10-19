#!/bin/bash

# 사용법 체크
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <class-1 | class-2 | class-3 | class-cloud> <student-num (예: sk0199)>"
  if [ -z "$1" ]; then
    echo "Error: class 값이 누락되었습니다."
  fi
  if [ -z "$2" ]; then
    echo "Error: 교육생 번호(student-num) 값이 누락되었습니다."
  fi
  exit 1
fi

CLASS="$1"
STUDENT_NUM="$2"
SRC_CONFIG="./kube-config/${CLASS}-skala-admin-sa.config"
SRC_ENV="cloud.env"

# 파일 존재 확인
if [ ! -f "$SRC_CONFIG" ]; then
  echo "Error: $SRC_CONFIG not found"
  exit 1
fi

if [ ! -f "$SRC_ENV" ]; then
  echo "Error: $SRC_ENV not found"
  exit 1
fi

# ~/.kube 생성
mkdir -p "$HOME/.kube"

# kube config 복사
cp "$SRC_CONFIG" "$HOME/.kube/config"

# gen-yaml.sh 복사
cp gen-yaml.sh "$HOME/.kube/gen-yaml.sh"
chmod +x "$HOME/.kube/gen-yaml.sh"

# cloud.env 복사
cp "$SRC_ENV" "$HOME/.cloud.env"

# OS 판별 (macOS vs Linux/WSL)
SHELL_RC=""
if uname | grep -qi darwin; then
  SHELL_RC="$HOME/.zshrc"
else
  SHELL_RC="$HOME/.bashrc"
fi

# source ~/.cloud.env 삽입 (중복 방지)
if ! grep -q "source ~/.cloud.env" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "source ~/.cloud.env" >> "$SHELL_RC"
  echo "export CLASS_NAME=$CLASS" >> "$SHELL_RC"
  echo "export STUDENT_NUM=$STUDENT_NUM" >> "$SHELL_RC"
fi

# 즉시 적용
source "$HOME/.cloud.env"
export CLASS_NAME="$CLASS"
export STUDENT_NUM="$STUDENT_NUM"

# 확인 출력
echo "==== Environment Variables Loaded ===="
env | grep -E '^[A-Z_]+='


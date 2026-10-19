#!/bin/bash
# ============================================================
# 목적: 기존 릴리즈를 2.0.0으로 업그레이드
#       values-2.0.0.yaml을 -f 옵션으로 오버라이드
# 조건: 01.install-1.0.0.sh 실행 이후에 동작
# 사용: bash 02.upgrade-2.0.0.sh
# ============================================================

set -xeu

USER_NAME="${STUDENT_NUM}"           # 리소스 이름 prefix
RELEASE_NAME="${USER_NAME}-myfirst-helm"
NAMESPACE="${CLASS-NAME}"
CHART_DIR="./myfirst-helmchart"    # 로컬 chart 경로

# ── 1) 업그레이드 전 현재 릴리즈 히스토리 확인 ──────────────
echo "=== 업그레이드 전 히스토리 ==="
helm history ${RELEASE_NAME} -n ${NAMESPACE}

# ── 2) 2.0.0 업그레이드 ──────────────────────────────────────
# -f values-2.0.0.yaml → image.tag=2.0.0, replicaCount=2 오버라이드
helm upgrade ${RELEASE_NAME} ${CHART_DIR} \
  --namespace ${NAMESPACE} \
  --atomic \
  --reuse-values \
  --timeout 3m \
  -f ./skala-value/skala-values-2.0.yaml

# ── 3) 업그레이드 후 확인 ────────────────────────────────────
echo ""
echo "=== 업그레이드 후 히스토리 (revision 1=1.0.0, revision 2=2.0.0) ==="
helm history ${RELEASE_NAME} -n ${NAMESPACE}

echo ""
echo "=== 현재 실행 중인 이미지 태그 확인 ==="
kubectl get deploy -n ${NAMESPACE} \
  -l app.kubernetes.io/instance=${RELEASE_NAME} \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'


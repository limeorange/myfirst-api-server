#!/bin/bash
# ============================================================
# 목적: Helm chart를 Harbor Helm Chart Repository에 push
#       → Harbor UI에서 "Helm Charts" 탭에서 확인 가능
# 프로토콜: https:// / ChartMuseum API (helm cm-push 플러그인 사용)
# 엔드포인트: https://<host>/chartrepo/<project>
# 사용: bash 04-2.push-harbor.sh
# ============================================================

set -xeu

USER_NAME="${STUDENT_NUM}"           # 리소스 이름 prefix
CHART_NAME="${USER_NAME}-myfirst-helm"
RELEASE_NAME="${USER_NAME}-myfirst-helm"
CHART_VERSION="0.0.1"
CHART_DIR="./myfirst-helmchart"    # 로컬 chart 경로
NAMESPACE="${CLASS-NAME}"

HARBOR_HOST="${DOCKER_REGISTRY}"
HARBOR_USER="${DOCKER_REGISTRY_USER}"
HARBOR_PASSWORD="${DOCKER_REGISTRY_PASSWORD}"
HARBOR_PROJECT="${CLASS_NAME}"

# ChartMuseum 엔드포인트 (OCI가 아닌 Helm Chart Repository)
CHART_REPO_URL="https://${HARBOR_HOST}/chartrepo/${HARBOR_PROJECT}"
REPO_NAME="${HARBOR_PROJECT}-charts"

# ── 1) helm cm-push 플러그인 확인 및 자동 설치 ───────────────
if ! helm plugin list | grep -q "^cm-push"; then
  echo "cm-push 플러그인 설치 중..."
  helm plugin install https://github.com/chartmuseum/helm-push
fi

# ── 2) Helm repo 등록 (없으면 추가, 있으면 재등록) ───────────
if helm repo list 2>/dev/null | grep -q "^${REPO_NAME}"; then
  helm repo remove ${REPO_NAME}
fi

helm repo add ${REPO_NAME} ${CHART_REPO_URL} \
  --username "${HARBOR_USER}" \
  --password "${HARBOR_PASSWORD}" \
  --insecure-skip-tls-verify

# ── 3) 차트 패키징 ────────────────────────────────────────────
helm package ${CHART_DIR} --version ${CHART_VERSION}
CHART_PKG="${CHART_NAME}-${CHART_VERSION}.tgz"

# ── 4) Helm Chart Repository에 push ─────────────────────────
helm cm-push ${CHART_PKG} ${REPO_NAME} \
  --username "${HARBOR_USER}" \
  --password "${HARBOR_PASSWORD}" \
  --insecure

echo ""
echo "=== Push 완료 ==="
echo "위치: ${CHART_REPO_URL} (Harbor → Helm Charts 탭)"

# ── 5) repo 업데이트 후 업로드 확인 ─────────────────────────
helm repo update ${REPO_NAME}
helm search repo ${REPO_NAME}/${CHART_NAME} --versions

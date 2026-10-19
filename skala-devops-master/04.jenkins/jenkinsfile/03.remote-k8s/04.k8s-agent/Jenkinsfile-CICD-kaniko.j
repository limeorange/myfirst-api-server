// ============================================================
// Jenkinsfile-CICD with Kaniko (PVC로 파일 공유, 독립된 빌드 에이전트)
// [Stage 흐름 및 Pod 배치]
//   1. Clone Repository            : maven Pod   → PVC에 소스 클론
//   2. Build with Maven            : maven Pod   → PVC에서 빌드, target/*.jar 생성
//   3. Image Build & Push (Kaniko) : kaniko Pod  → PVC의 소스+jar로 이미지 빌드 후 Harbor 푸시
//   4. Update K8s Manifests        : maven Pod   → kustomize/overlays/dev 이미지 태그를 kustomize edit set image로 갱신 후 렌더링
//   5. Deploy to Kubernetes        : kubectl Pod → 렌더링된 매니페스트를 kubectl apply + rollout 대기
// ============================================================
pipeline {
  // stage별로 독립 Pod 사용 (PVC로 파일 공유)
  agent none

  environment {
    // === 사용자 수정 영역 ===
    GIT_URL                = 'https://{{GIT_REPO_URL}}'
    GIT_BRANCH             = '{{GIT_BRANCH}}'
    GIT_ID                 = 'skala-github-id'
    IMAGE_NAME             = '{{USER_NAME}}-{{IMAGE_NAME}}'
    // =======================
    IMAGE_TAG              = '1.0'
    IMAGE_REGISTRY_URL     = '{{DOCKER_REGISTRY}}'
    IMAGE_REGISTRY_PROJECT = '{{PROJECT_NAME}}'
    DOCKER_CREDENTIAL_ID   = 'skala-image-registry-id'
    K8S_NAMESPACE          = '{{NAMESPACE}}'
    DEPLOYMENT_NAME        = '{{USER_NAME}}-{{SERVICE_NAME}}'  // kustomize/base/deployment.yaml의 metadata.name과 동일해야 함
  }

  options {
    disableConcurrentBuilds()
    timestamps()
  }

  stages {

    // ── 소스 클론 ── [maven Pod + PVC] ───────────────────────────────────────
    // ※ JENKINS-30600: git step은 container() 블록을 무시하고 항상 jnlp에서 실행됨
    //    → git config safe.directory도 jnlp에서 설정해야 함 (container 래퍼 제거)
    stage('Clone Repository') {
      agent { label 'maven' }       // maven Pod 생성, PVC → /home/jenkins/agent
      steps {
        sh 'git config --global --add safe.directory "*"'
        echo 'Clone Repository'
        git branch: "${GIT_BRANCH}", url: "${GIT_URL}", credentialsId: "${GIT_ID}"
        sh 'ls -al'
      }
    }

    // ── Maven 빌드 ── [maven Pod + PVC] ───────────────────────────────────────
    stage('Build with Maven') {
      agent { label 'maven' }       // 새 maven Pod, PVC에서 소스 읽어 빌드
      steps {
        container('maven') {
          echo 'Build with Maven'
          sh 'mvn clean package -DskipTests'
          sh 'ls -al'
        }
      }
    }

    // ── 이미지 빌드 & 푸시 ── [kaniko Pod + PVC] ──────────────────────────────
    //      PVC에 있는 소스코드 + target/*.jar + Dockerfile을 kaniko Pod에서 직접 사용
    //      인증: Jenkins credential(skala-image-registry-id) → /kaniko/.docker/config.json 생성
    stage('Image Build & Push (Kaniko)') {
      agent { label 'kaniko' }      // kaniko Pod 생성, PVC → /home/jenkins/agent
      steps {
        withCredentials([usernamePassword(
          credentialsId: "${DOCKER_CREDENTIAL_ID}",
          usernameVariable: 'REG_USER',
          passwordVariable: 'REG_PASS'
        )]) {
          container('kaniko') {
            sh '''
              set -eux
              IMAGE_REF="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}-${BUILD_NUMBER}"

              # 인증: Jenkins credential(skala-image-registry-id)에서 가져온 username/password로 config.json 생성
              # kaniko는 DOCKER_CONFIG=/kaniko/.docker 의 config.json을 읽어 레지스트리 인증
              mkdir -p /kaniko/.docker
              AUTH=$(printf '%s:%s' "${REG_USER}" "${REG_PASS}" | base64 | tr -d '\n')
              cat > /kaniko/.docker/config.json << EOF
{"auths":{"${IMAGE_REGISTRY_URL}":{"auth":"${AUTH}"}}}
EOF

              /kaniko/executor \
                --dockerfile=Dockerfile \
                --context=dir://${WORKSPACE} \
                --destination="${IMAGE_REF}" \
                --force
              # --dockerfile=Dockerfile   : context 루트 기준 상대 경로
              # --context=dir://$WORKSPACE: PVC의 실제 소스 경로 (Jenkins가 설정한 workspace)
              # TLS 오류 발생 시 아래 옵션 추가:
              #   --skip-tls-verify-registry=${IMAGE_REGISTRY_URL}
            '''
          }
        }
      }
    }

    // ── k8s 매니페스트 이미지 태그 업데이트 ── [maven Pod + PVC] ───────────────
    //      kustomize/overlays/dev 이미지 태그 갱신 후, kubectl Pod에서 kustomize 없이도 적용 가능하도록 미리 렌더링
    //      (해당 Pod 이미지에 kustomize CLI 필요)
    stage('Update K8s Manifests') {
      agent { label 'maven' }
      steps {
        container('maven') {
          sh '''
            set -eux
            test -d ./kustomize/overlays/dev

            FINAL_IMAGE_TAG="${IMAGE_TAG}-${BUILD_NUMBER}"
            IMAGE_BASE="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}"

            # 1. 이미지 태그 업데이트 (이후 명령은 원래 디렉토리에서 실행해야 하므로 서브셸 사용)
            (cd ./kustomize/overlays/dev && kustomize edit set image "${IMAGE_BASE}=${IMAGE_BASE}:${FINAL_IMAGE_TAG}")

            # 2. kubectl Pod에서 그대로 적용할 수 있도록 렌더링 결과를 PVC에 저장
            kustomize build ./kustomize/overlays/dev > ./rendered-manifest.yaml

            # ===== DEBUG:START =====
            echo "--- rendered-manifest.yaml ---"
            cat ./rendered-manifest.yaml
            # ===== DEBUG:END =====
          '''
        }
      }
    }

    // ── Kubernetes 직접 배포 ── [kubectl Pod + PVC] ────────────────────────────
    //      PVC에 렌더링된 매니페스트(rendered-manifest.yaml)를 kubectl apply로 배포
    //      [주의] skala-admin-sa ServiceAccount에 deployments 쓰기 권한 필요
    //             (01-rbac.yaml 업데이트 필요)
    stage('Deploy to Kubernetes') {
      agent { label 'kubectl' }     // kubectl Pod, serviceAccount: skala-admin-sa
      steps {
        container('kubectl') {
          sh '''
            set -eux

            # ===== DEBUG:START =====
            echo "=== [DEBUG] Deploy to Kubernetes stage ==="
            echo "K8S_NAMESPACE=${K8S_NAMESPACE}"
            echo "DEPLOYMENT_NAME=${DEPLOYMENT_NAME}"
            kubectl version --client 2>&1 | head -1 || echo "kubectl not found!"
            # ===== DEBUG:END =====

            echo "=== rendered manifest 적용 ==="
            kubectl apply -n "${K8S_NAMESPACE}" -f ./rendered-manifest.yaml

            echo "=== 배포 롤아웃 대기 ==="
            kubectl rollout status deployment/"${DEPLOYMENT_NAME}" \
              -n "${K8S_NAMESPACE}" \
              --timeout=180s

            echo "=== 배포 완료 ==="
            kubectl get pods -n "${K8S_NAMESPACE}" -l "app=${DEPLOYMENT_NAME}"
          '''
        }
      }
    }

  } // stages

  post {
    always {
      // PVC 워크스페이스 정리: git clone, target/, 빌드 아티팩트 삭제
      // agent none 파이프라인은 post에 node() 블록이 필요, workspace 루트 자체는 유지(rm -rf ${WORKSPACE} 시 durable task 상태파일 손실)
      node('maven') {
        sh 'rm -rf "${WORKSPACE}"/* 2>/dev/null || true'
      }
    }
  }
}


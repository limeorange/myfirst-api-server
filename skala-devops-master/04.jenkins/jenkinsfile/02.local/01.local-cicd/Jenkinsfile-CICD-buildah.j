pipeline {
  agent any

  environment {
    // === 사용자 수정 영역 ===
    GIT_URL                = 'https://{{GIT_REPO_URL}}'
    GIT_BRANCH             = '{{GIT_BRANCH}}'            // 또는 main
    GIT_ID                 = 'skala-github-id'   // GitHub PAT credential ID
    IMAGE_NAME             = '{{USER_NAME}}-{{IMAGE_NAME}}'    
    // =======================
    IMAGE_TAG              = '1.0'    
    IMAGE_REGISTRY_URL     = '{{DOCKER_REGISTRY}}'
    IMAGE_REGISTRY_PROJECT = '{{PROJECT_NAME}}'

    DOCKER_CREDENTIAL_ID   = 'skala-image-registry-id'  // Harbor 인증 정보 ID
    K8S_NAMESPACE          = '{{NAMESPACE}}'
    DEPLOYMENT_NAME        = '{{USER_NAME}}-{{SERVICE_NAME}}'  // kustomize/base/deployment.yaml의 metadata.name과 동일해야 함
  }

  options {
    disableConcurrentBuilds()
    timestamps()
  }

  stages {
    stage('Clone Repository') {
      steps {
        echo 'Clone Repository'
        git branch: "${GIT_BRANCH}", url: "${GIT_URL}", credentialsId: "${GIT_ID}"
        sh 'ls -al'
      }
    }

    stage('Build with Maven') {
      steps {
        echo 'Build with Maven'
        sh 'mvn clean package -DskipTests'
        sh 'ls -al'
      }
    }

    // 로그인/빌드/푸시/정리
    stage('Image Build & Push (Buildah)') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: "${DOCKER_CREDENTIAL_ID}",
          usernameVariable: 'REG_USER',
          passwordVariable: 'REG_PASS'
        )]) {
        sh '''
            set -eux
            REG_HOST="${IMAGE_REGISTRY_URL}"
            IMAGE_REF="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}-${BUILD_NUMBER}"

            # 1. 로그인
            echo "Login to $REG_HOST as $REG_USER"
            sudo buildah login -u "$REG_USER" -p "$REG_PASS" "$REG_HOST"

            # 2. 빌드
            sudo buildah bud --storage-driver=vfs --platform "linux/amd64" -t "${IMAGE_REF}" .
            # 3. 푸시
            sudo buildah push --storage-driver=vfs "${IMAGE_REF}"
            # 4. 정리
            sudo buildah rmi -a || true
        '''
        }
      }
    }

    // kustomize/overlays/dev 이미지 태그 업데이트 (git에 올라간 00.spring-backend-v1.0을 clone한 워크스페이스 기준) ───────────────
    stage('Update K8s Manifests') {
      steps {
        sh '''
          set -eux
          test -d ./kustomize/overlays/dev
          cd ./kustomize/overlays/dev

          FINAL_IMAGE_TAG="${IMAGE_TAG}-${BUILD_NUMBER}"
          IMAGE_BASE="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}"

          kustomize edit set image "${IMAGE_BASE}=${IMAGE_BASE}:${FINAL_IMAGE_TAG}"

          # ===== DEBUG:START =====
          echo "--- AFTER ---"
          cat ./kustomization.yaml
          # ===== DEBUG:END =====
        '''
      }
    }

    // ── Kubernetes 배포 (kustomize build | kubectl apply) ───────────────
    stage('Deploy to Kubernetes') {
      steps {
        sh '''
          set -eux

          FINAL_IMAGE_TAG="${IMAGE_TAG}-${BUILD_NUMBER}"
          IMAGE_BASE="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}"

          # ===== DEBUG:START =====
          echo "=== [DEBUG] Deploy to Kubernetes stage ==="
          echo "K8S_NAMESPACE=${K8S_NAMESPACE}"
          echo "DEPLOYMENT_NAME=${DEPLOYMENT_NAME}"
          kubectl version --client 2>&1 | head -1 || echo "kubectl not found!"
          kustomize version 2>&1 | head -1 || echo "kustomize not found!"
          # ===== DEBUG:END =====

          echo "=== kustomize build 결과 적용 ==="
          kustomize build ./kustomize/overlays/dev | kubectl apply -n "${K8S_NAMESPACE}" -f -

          echo "=== 배포 롤아웃 대기 ==="
          kubectl rollout status deployment/"${DEPLOYMENT_NAME}" \
            -n "${K8S_NAMESPACE}" \
            --timeout=180s

          echo "=== 배포 완료: ${IMAGE_BASE}:${FINAL_IMAGE_TAG} ==="
          kubectl get pods -n "${K8S_NAMESPACE}" -l "app=${DEPLOYMENT_NAME}"
        '''
      }
    }

  }

  post {
    always {
      deleteDir()  // 워크스페이스 정리 (git clone, target/, 빌드 아티팩트)
    }
  }
}


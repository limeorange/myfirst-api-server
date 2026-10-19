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
    GITOPS_BRANCH          = 'gitops'
    GITOPS_MANIFEST_DIR    = 'kustomize/overlays/dev'
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

    // 로그인/빌드+푸시/정리 (docker buildx = BuildKit 기반, 빌드와 동시에 push)
    stage('Image Build & Push (BuildKit)') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: "${DOCKER_CREDENTIAL_ID}",
          usernameVariable: 'REG_USER',
          passwordVariable: 'REG_PASS'
        )]) {
        script {
          // 이미지 태그 = IMAGE_TAG-빌드번호-커밋해시(7자리), GitOps 스테이지에서도 동일 값 사용
          def shortCommit = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.FINAL_IMAGE_TAG = "${env.IMAGE_TAG}-dk${env.BUILD_NUMBER}-${shortCommit}"
        }
        sh '''
            set -eux
            REG_HOST="${IMAGE_REGISTRY_URL}"
            IMAGE_REF="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}:${FINAL_IMAGE_TAG}"

            # 1. 로그인
            echo "Login to $REG_HOST as $REG_USER"
            echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin "$REG_HOST"

            # 2. 빌드 + 푸시 (buildx build --push는 별도 push 단계 없이 한 번에 수행)
            docker buildx build --platform "linux/amd64" -t "${IMAGE_REF}" --push .

            # 3. 정리
            docker rmi "${IMAGE_REF}" || true
            docker logout "$REG_HOST" || true
        '''
        }
      }
    }

    // GitOps 업데이트 (ArgoCD CD 트리거) ────────────────
    // kustomize/overlays/dev 이미지 태그 수정 후 gitops 브랜치에 push
    stage('GitOps Update') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: "${GIT_ID}",
          usernameVariable: 'GIT_USER',
          passwordVariable: 'GIT_PASS'
        )]) {
          script {
            env.REPO_PATH = env.GIT_URL.replaceFirst(/^https?:\/\//, '')
          }
          sh '''
            set -eux
            git config --global user.name  "skala-gitops"
            git config --global user.email "skala@skala-ai.com"
            git config --global --add safe.directory '*'
            git remote set-url origin "https://${GIT_USER}:${GIT_PASS}@${REPO_PATH}"

            IMAGE_BASE="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}"

            # 1. GIT_BRANCH(현재 체크아웃된 소스) 기준으로 kustomize 이미지 태그 업데이트
            (cd "${GITOPS_MANIFEST_DIR}" && kustomize edit set image "${IMAGE_BASE}=${IMAGE_BASE}:${FINAL_IMAGE_TAG}")

            # 2. 커밋 후 GITOPS_BRANCH로 push (GIT_BRANCH 기준으로 덮어쓰므로 --force 필요)
            git add "${GITOPS_MANIFEST_DIR}/kustomization.yaml"
            git commit -m "[AUTO] image: ${IMAGE_NAME}:${FINAL_IMAGE_TAG}"
            git push --force origin "HEAD:refs/heads/${GITOPS_BRANCH}"
            echo "[DONE] gitops 브랜치 업데이트 완료: ${IMAGE_BASE}:${FINAL_IMAGE_TAG}"
          '''
        }
      }
    }

  }

  post {
    always {
      deleteDir()  // 워크스페이스 정리 (git clone, target/, 빌드 아티팩트)
    }
  }
}


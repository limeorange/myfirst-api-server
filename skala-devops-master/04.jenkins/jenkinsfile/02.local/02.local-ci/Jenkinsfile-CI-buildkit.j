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

    // 빌드+푸시 (docker buildx 대신 BuildKit(buildctl)을 직접 사용, docker 데몬 불필요)
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
          env.FINAL_IMAGE_TAG = "${env.IMAGE_TAG}-bk${env.BUILD_NUMBER}-${shortCommit}"
        }
        sh '''
            set -eux
            IMAGE_REF="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}:${FINAL_IMAGE_TAG}"

            # 1. 인증: username/password로 config.json 생성 (buildkit은 DOCKER_CONFIG의 config.json으로 레지스트리 인증)
            mkdir -p ~/.docker
            AUTH=$(printf '%s:%s' "${REG_USER}" "${REG_PASS}" | base64 | tr -d '\n')
            cat > ~/.docker/config.json << EOF
{"auths":{"${IMAGE_REGISTRY_URL}":{"auth":"${AUTH}"}}}
EOF

            # 2. 빌드 + 푸시 (buildctl-daemonless.sh: rootless buildkitd를 즉석에서 띄워 한 번에 수행)
            # overlayfs 스냅샷터는 현재 파일시스템에서 trusted.overlay xattr을 지원하지 않아
            # "failed to get xattr" 에러 발생 → xattr에 의존하지 않는 native 스냅샷터 사용
            export BUILDKITD_FLAGS="--oci-worker-snapshotter=native"
            buildctl-daemonless.sh build \
              --frontend dockerfile.v0 \
              --local context=. \
              --local dockerfile=. \
              --opt platform=linux/amd64 \
              --output type=image,name="${IMAGE_REF}",push=true
            # TLS 오류 발생 시 --output 뒤에 ,registry.insecure=true 추가
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

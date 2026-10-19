// ============================================================
// Jenkinsfile-CI-kaniko (PVC로 파일 공유, 독립된 빌드 에이전트)
// ※ ArgoCD GitOps 방식으로 배포 (Jenkins는 gitops 브랜치만 업데이트)
//
// [Stage 흐름 및 Pod 배치]
//   1. Clone Repository            : maven Pod  → PVC에 소스 클론
//   2. Build with Maven            : maven Pod  → PVC에서 빌드, target/*.jar 생성
//   3. Image Build & Push (Kaniko) : kaniko Pod → PVC의 소스+jar로 이미지 빌드 후 Harbor 푸시
//   4. GitOps Update                : maven Pod  → kustomize/overlays/dev 이미지 태그 수정 후 gitops 브랜치 푸시
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
    GITOPS_BRANCH          = 'gitops'
    GITOPS_MANIFEST_DIR    = 'kustomize/overlays/dev'
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
        script {
          // 이미지 태그 = IMAGE_TAG-빌드번호-커밋해시(7자리), 이후 스테이지(이미지 빌드/GitOps)에서 동일 값 사용
          // ※ kaniko/buildkit 등 빌드 컨테이너에는 git이 없을 수 있으므로 클론 직후 여기서 계산
          def shortCommit = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.FINAL_IMAGE_TAG = "${env.IMAGE_TAG}-${env.BUILD_NUMBER}-${shortCommit}"
        }
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
              IMAGE_REF="${IMAGE_REGISTRY_URL}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_NAME}:${FINAL_IMAGE_TAG}"

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

    // ── GitOps 업데이트 (ArgoCD CD 트리거) ── [maven Pod + PVC] ──────────────────
    // kustomize/overlays/dev 이미지 태그 수정 후 gitops 브랜치에 push
    stage('GitOps Update') {
      agent { label 'maven' }       // maven Pod, PVC에 있는 kustomize/overlays/dev 직접 수정 (해당 Pod 이미지에 kustomize CLI 필요)
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


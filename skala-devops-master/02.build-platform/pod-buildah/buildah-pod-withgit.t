apiVersion: v1
kind: Pod
metadata:
  name: {{USER_NAME}}-buildah-pod
  namespace: {{NAMESPACE}}
  labels:
    app: {{USER_NAME}}
spec:
  # Init Container: Maven 
  initContainers:
  - name: maven
    image: maven:3.9-eclipse-temurin-21
    workingDir: /workspace
    command: ["/bin/bash"]
    args:
      - -c
      - |
        echo "=== Git Clone 시작 ==="
        git clone https://{{GIT_USERNAME}}:{{GIT_PASSWORD}}@{{GIT_REPO_URL}} .
        echo "=== Maven 빌드 시작 ==="
        mvn clean install -DskipTests
        echo "=== 빌드 완료 ==="
        ls -al

    volumeMounts:
      - name: workspace
        mountPath: /workspace

  # Main Container: Buildah
  containers:
  - name: buildah
    image: quay.io/buildah/stable:latest
    workingDir: /workspace
    command: ["/bin/bash", "-ec"]
    args:
      - |
        IMAGE_REF="{{DOCKER_REGISTRY}}/{{PROJECT_NAME}}/{{USER_NAME}}-{{IMAGE_NAME}}:1.0.buildah-pod"
        mkdir -p /etc/containers/registries.conf.d
        echo 'unqualified-search-registries = ["docker.io"]' \
          > /etc/containers/registries.conf.d/my-registries.conf
        buildah bud --storage-driver=overlay \
          --platform linux/arm64,linux/amd64 \
          --manifest "$IMAGE_REF" \
          /workspace
        buildah manifest push --storage-driver=overlay \
          --authfile /auth/config.json \
          --all "$IMAGE_REF" "docker://$IMAGE_REF"
    securityContext:
      privileged: true
    volumeMounts:
      - name: workspace
        mountPath: /workspace
      - name: buildah-secret
        mountPath: /auth
        readOnly: true

  restartPolicy: Never
  volumes:
    - name: workspace
      emptyDir: {}
    - name: buildah-secret
      secret:
        secretName: harbor-registry-secret
        items:
          - key: .dockerconfigjson
            path: config.json

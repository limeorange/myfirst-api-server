apiVersion: v1
kind: Pod
metadata:
  name: {{USER_NAME}}-buildah-pod
  namespace: {{NAMESPACE}}
  labels:
    app: {{USER_NAME}}
spec:
  containers:
    - name: buildah
      image: quay.io/buildah/stable:latest
      workingDir: /workspace
      command: ["/bin/bash", "-ec"]
      args:
        - |
          IMAGE_REF="{{DOCKER_REGISTRY}}/{{PROJECT_NAME}}/{{USER_NAME}}-{{IMAGE_NAME}}:2.0.buildah-pod"
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
        - name: buildah-secret
          mountPath: /auth
          readOnly: true
        - name: workspace
          mountPath: /workspace
  restartPolicy: Never
  volumes:
    - name: buildah-secret
      secret:
        secretName: harbor-registry-secret
        items:
          - key: .dockerconfigjson
            path: config.json
    - name: workspace
      configMap:   # 또는 PVC, emptyDir
        name: {{USER_NAME}}-app-workspace

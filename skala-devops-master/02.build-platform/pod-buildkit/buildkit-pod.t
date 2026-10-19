apiVersion: v1
kind: Pod
metadata:
  name: {{USER_NAME}}-buildkit-pod
  namespace: {{NAMESPACE}}
  labels:
    app: {{USER_NAME}}
spec:
  containers:
    - name: buildkit
      image: moby/buildkit:rootless
      command: ["buildctl-daemonless.sh"]
      args:
        - build
        - --frontend=dockerfile.v0
        - --local=context=/workspace
        - --local=dockerfile=/workspace
        - --opt=platform=linux/arm64,linux/amd64
        - --output=type=image,name={{DOCKER_REGISTRY}}/{{PROJECT_NAME}}/{{USER_NAME}}-{{IMAGE_NAME}}:2.0.buildkit-pod,push=true
      env:
        - name: DOCKER_CONFIG
          value: /home/user/.docker
        - name: BUILDKITD_FLAGS
          value: --oci-worker-no-process-sandbox
      # rootless BuildKit의 user namespace 작업에 필요
      securityContext:
        seccompProfile:
          type: Unconfined
      volumeMounts:
        - name: buildkit-secret
          mountPath: /home/user/.docker
        - name: workspace
          mountPath: /workspace
  restartPolicy: Never
  volumes:
    - name: buildkit-secret
      secret:
        secretName: harbor-registry-secret
        items:
          - key: .dockerconfigjson
            path: config.json
    - name: workspace
      configMap:   # 또는 PVC, emptyDir
        name: {{USER_NAME}}-app-workspace

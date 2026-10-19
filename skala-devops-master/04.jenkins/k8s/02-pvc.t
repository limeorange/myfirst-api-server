apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{USER_NAME}}-jenkins-pvc
  namespace: {{NAMESPACE}}
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
  storageClassName: efs-sc-shared

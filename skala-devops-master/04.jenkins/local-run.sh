#!/bin/bash

set -eux
cp ~/.kube/config ./kube-config

docker run -d \
  --name skala-custom-jenkins \
  -p 8888:8080 \
  -p 50000:50000 \
  -v ${HOME}/.m2:/root/.m2 \
  -v $(pwd)/jenkins_home:/var/jenkins_home \
  -v $(pwd)/jenkins.yaml:/var/jenkins_config/jenkins.yaml \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd)/kube-config:/usr/share/jenkins/ref/kube-config \
  -e CASC_JENKINS_CONFIG=/var/jenkins_config/jenkins.yaml \
  -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
  -e BUILDAH_ISOLATION=chroot \
  -e STORAGE_DRIVER=vfs \
  -e TMPDIR=/tmp \
  -e XDG_DATA_HOME=/tmp \
  --group-add 0 \
  --privileged \
  ${DOCKER_REGISTRY}/library/skala-custom-jenkins:1.0


#!/usr/bin/env bash

# https://github.com/stefanprodan/gitops-istio/blob/master/scripts/flux-init.sh

set -e

if [[ ! -x "$(command -v kubectl)" ]]; then
    echo "kubectl not found"
    exit 1
fi

if [[ ! -x "$(command -v helm)" ]]; then
    echo "helm not found"
    exit 1
fi

###########################################################
# https://github.com/fluxcd/flux/tree/master/chart/flux
###########################################################
helm repo add fluxcd https://charts.fluxcd.io
echo ">>> Installing Flux"
kubectl create ns flux-system || true
helm upgrade -i flux fluxcd/flux \
--wait \
--values flux-values.yaml \
--namespace flux-system

###################################################################################
# https://github.com/fluxcd/helm-operator/tree/master/chart/helm-operator
###################################################################################
echo ">>> Installing Helm Operator"
kubectl apply -f https://raw.githubusercontent.com/fluxcd/helm-operator/1.1.0/deploy/crds.yaml
helm upgrade -i helm-operator fluxcd/helm-operator \
--wait \
--set git.ssh.secretName=flux-git-deploy \
--set helm.versions=v3 \
--namespace flux-system

echo ">>> GitHub deploy key"
kubectl -n flux-system logs deployment/flux | grep identity.pub | cut -d '"' -f2

# wait until flux is able to sync with repo
echo ">>> Waiting on user to add above deploy key to Github with write access"
until kubectl logs -n flux-system deployment/flux | grep event=refreshed
do
  sleep 5
done
echo ">>> Github deploy key is ready"

echo ">>> installing bitnami sealdSecret"
curl -o kubeseal -L https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.12.4/kubeseal-darwin-amd64
kubectl create namespace sealed-secrets
mkdir sealed-secrets
openssl req -x509 -nodes -newkey rsa:4096 -keyout sealed-secrets/sealed-secret.key -out sealed-secrets/sealed-secret.crt -subj "/CN=sealed-secret/O=sealed-secret"
kubectl -n sealed-secrets create secret tls ss-default --cert=sealed-secrets/sealed-secret.crt --key=sealed-secrets/sealed-secret.key
kubectl -n sealed-secrets label secret ss-default sealedsecrets.bitnami.com/sealed-secrets-key=active

echo ">>> Cluster bootstrap done!"

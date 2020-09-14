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
kubectl create ns flux-teams || true

################################################################################################################################
kubectl create secret generic -n flux-system flux-git-deploy --from-file=identity=secrets/flux-deploy-key
kubectl create secret generic -n flux-system flux-git-deploy --from-file=identity=secrets/flux-deploy-key --dry-run -o json | \
	./kubeseal --format=yaml --cert=secrets/ss.pem --scope=strict --namespace=flux-system | \
	kubectl apply -f -

kubectl label -n flux-system secret/flux-git-deploy app.kubernetes.io/managed-by=Helm	
kubectl annotate -n flux-system secret/flux-git-deploy meta.helm.sh/release-name=flux
kubectl annotate -n flux-system secret/flux-git-deploy meta.helm.sh/release-namespace=flux-system
################################################################################################################################
kubectl create secret generic -n flux-teams team-1-deploy --from-file=identity=secrets/flux-team-1 --dry-run -o json | \
	./kubeseal --format=yaml --cert=secrets/ss.pem --scope=strict --namespace=flux-teams | \
	kubectl apply -f -
kubectl create secret generic -n flux-teams team-2-deploy --from-file=identity=secrets/flux-team-2 --dry-run -o json | \
	./kubeseal --format=yaml --cert=secrets/ss.pem --scope=strict --namespace=flux-teams | \
	kubectl apply -f -
################################################################################################################################

helm upgrade -i flux fluxcd/flux \
--wait \
--values flux-values.yaml \
--namespace flux-system

###################################################################################
# https://github.com/fluxcd/helm-operator/tree/master/chart/helm-operator
###################################################################################
echo ">>> Installing Helm Operator"
kubectl apply -f https://raw.githubusercontent.com/fluxcd/helm-operator/1.2.0/deploy/crds.yaml
helm upgrade -i helm-operator fluxcd/helm-operator \
--wait \
--set helm.versions=v3 \
--namespace flux-system # \
# --set git.ssh.secretName=flux-ssh \

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
kubectl -n sealed-secrets create secret tls sealed-secrets-key --cert=sealed-secrets/sealed-secret.crt --key=sealed-secrets/sealed-secret.key
kubectl -n sealed-secrets label secret sealed-secrets-key sealedsecrets.bitnami.com/sealed-secrets-key=active

echo ">>> Cluster bootstrap done!"

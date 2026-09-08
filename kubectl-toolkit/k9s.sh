#!/bin/bash

if [[ ! -f "$HOME/.kube/config" && ! -f "$KUBECONFIG" ]]; then
    export KUBECONFIG=/dev/shm/kubeconfig
    kubectl config set-credentials default-user --token=PLACEHOLDER
    kubectl config set-cluster default-cluster --server=https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS} --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    kubectl config set-context default-context --cluster=default-cluster --user=default-user --namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    kubectl config use-context default-context
    sed -i 's|token: PLACEHOLDER|tokenFile: /run/secrets/kubernetes.io/serviceaccount/token|' "$KUBECONFIG"
fi

exec /bin/k9s-bin "$@"

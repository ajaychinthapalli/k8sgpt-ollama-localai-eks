#!/bin/bash
# Installs Ollama (CPU-only, Karpenter-provisioned) + the K8sGPT operator.
#
# Usage: ./scripts/install.sh <environment>
#   e.g. ./scripts/install.sh ajay-workspace

set -e

ENV_NAME="${1:?Usage: ./scripts/install.sh <environment-name> (e.g. ajay-workspace)}"
ENV_DIR="environments/${ENV_NAME}"

if [ ! -d "$ENV_DIR" ]; then
  echo "No environment directory found at $ENV_DIR"
  echo "Available environments:"
  ls environments/
  exit 1
fi

CLUSTER_NAME="ajay-workspace"
REGION="us-east-2"
ACCOUNT_ID="573631993187"

echo "== Step 1: EBS CSI driver =="
echo "Required for PVC provisioning — without it, the Ollama pod's PVC"
echo "will hang in Pending forever (see docs/TROUBLESHOOTING.md)."

if kubectl get pods -n kube-system 2>/dev/null | grep -q ebs-csi; then
  echo "EBS CSI driver already present, skipping."
else
  eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" --region "$REGION" --approve

  eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve

  eksctl create addon \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name aws-ebs-csi-driver \
    --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole" \
    --force

  echo "Waiting for EBS CSI driver pods to be ready..."
  kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=aws-ebs-csi-driver -n kube-system --timeout=180s
fi

echo "== Step 2: Karpenter EC2NodeClass + NodePool for Ollama =="
kubectl apply -f "${ENV_DIR}/ec2nodeclass.yaml"
kubectl apply -f "${ENV_DIR}/nodepool.yaml"

echo "== Step 3: Deploy Ollama via Helm =="
helm repo add ollama-helm https://otwld.github.io/ollama-helm/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install ollama ollama-helm/ollama \
  --namespace ollama --create-namespace \
  -f "${ENV_DIR}/ollama-values.yaml"

echo "Waiting for the Ollama pod to be scheduled and running (this includes"
echo "Karpenter launching a new node, which can take a few minutes)..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=ollama -n ollama --timeout=600s

echo "== Step 4: Install the K8sGPT operator =="
helm repo add k8sgpt https://charts.k8sgpt.ai/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm install k8sgpt-operator k8sgpt/k8sgpt-operator -n k8sgpt-operator-system --create-namespace \
  || echo "Operator already installed, skipping."

kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=k8sgpt-operator -n k8sgpt-operator-system --timeout=180s

echo "== Step 5: Apply the K8sGPT custom resource =="
kubectl apply -f manifests/k8sgpt-ollama-cr.yaml

echo
echo "Done. Check status with:"
echo "  kubectl get pods -n ollama"
echo "  kubectl get pods -n k8sgpt-operator-system"
echo "  kubectl get results -n k8sgpt-operator-system"

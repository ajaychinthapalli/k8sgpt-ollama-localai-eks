#!/bin/bash
# Tears down K8sGPT + Ollama and lets Karpenter reclaim the CPU node,
# returning the cluster to its original 3x t3.small baseline.
#
# Usage: ./scripts/cleanup.sh

set -e

echo "== Removing K8sGPT CR and operator =="
kubectl delete k8sgpt k8sgpt-ollama -n k8sgpt-operator-system --ignore-not-found
helm uninstall k8sgpt-operator -n k8sgpt-operator-system || true
kubectl delete namespace k8sgpt-operator-system --ignore-not-found

echo "== Removing Ollama =="
helm uninstall ollama -n ollama || true
kubectl delete pvc --all -n ollama --ignore-not-found
kubectl delete namespace ollama --ignore-not-found

echo "== Removing Karpenter NodePool and EC2NodeClass (this terminates the CPU node) =="
kubectl delete nodepool ollama-cpu --ignore-not-found
kubectl delete ec2nodeclass ollama-cpu --ignore-not-found

echo "== Waiting briefly for Karpenter to begin node termination =="
sleep 30

echo "== Current nodes =="
kubectl get nodes -o wide

echo
echo "Done. The ollama-cpu node will finish terminating within a few minutes."
echo "You should be left with your original 3x t3.small nodes."

# Contributing

Thanks for contributing to this project.

## Scope

This repository manages an EKS-based deployment that combines:

- Karpenter for on-demand EC2 node provisioning
- Ollama running in the `ollama` namespace
- K8sGPT configured with the `localai` backend against Ollama's `/v1` endpoint
- Environment-specific manifests under `environments/`

## Before you change anything

- Do not commit secrets, AWS credentials, tokens, or cluster kubeconfig files.
- Keep environment-specific values in `environments/<name>/` and avoid
  hard-coding cluster names in shared manifests.
- Review `docs/TROUBLESHOOTING.md` if you are changing storage or Karpenter
  configuration.

## Workflow

1. Fork or create a feature branch from the default branch.
2. Keep changes focused and directly related to the deployment or documentation.
3. Validate YAML and install behavior in a non-production or disposable cluster
   before merging.
4. Update docs when behavior or prerequisites change.

## Pull request expectations

- Provide a short description of the problem and the fix.
- Reference any affected files and environment values.
- Include validation notes, especially when changing install scripts, Helm
  values, or Karpenter manifests.

## Security

Never commit:

- AWS access keys or secret keys
- kubeconfig files
- personal or production cluster details that should remain private

## Local validation

Useful checks before submitting:

```bash
kubectl get nodes -o wide
kubectl get pods -n ollama
kubectl get pods -n k8sgpt-operator-system
helm list -A
```

If you are modifying install or cleanup flow, verify the script still matches
the cluster assumptions in `scripts/install.sh` and `scripts/cleanup.sh`.

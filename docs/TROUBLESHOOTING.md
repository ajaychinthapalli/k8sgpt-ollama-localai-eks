# Troubleshooting log

Every issue actually hit while setting this up on `ajay-workspace`, in the order
encountered, with root cause and fix. Kept here so the next person (or the next
environment) doesn't have to re-debug the same things.

---

### 1. `EC2NodeClass "ollama-cpu" is invalid: spec.amiSelectorTerms: Required value`

**Cause:** Karpenter's v1 CRD requires an explicit `amiSelectorTerms` in
addition to `amiFamily` — `amiFamily` alone isn't enough on the version
installed.

**Fix:** Add an alias term:

```yaml
amiFamily: AL2023
amiSelectorTerms:
  - alias: al2023@latest
```

---

### 2. `helm upgrade` fails with `"ollama" has no deployed releases`

**Cause:** `helm upgrade` requires an existing release; it won't create one
implicitly.

**Fix:** Use `--install`:

```bash
helm upgrade --install ollama ollama-helm/ollama --namespace ollama --create-namespace -f environments/ajay-workspace/ollama-values.yaml
```

---

### 3. Ollama pod stuck `Pending`: `StorageClass.storage.k8s.io "gp3" not found`

**Cause:** The original values file requested `storageClass: gp3`, but the
cluster only has `gp2` (no `gp3` StorageClass was ever created). Confirmed with:

```bash
kubectl get storageclass
```

**Fix:** Changed `environments/ajay-workspace/ollama-values.yaml` to
`storageClass: gp2`. Since the PVC had already been created against the
(nonexistent) `gp3` class, it also had to be deleted so it could be recreated
correctly:

```bash
kubectl delete pvc ollama -n ollama
helm upgrade ollama ollama-helm/ollama --namespace ollama -f environments/ajay-workspace/ollama-values.yaml
```

---

### 4. PVC still stuck `Pending` after switching to `gp2`

**Symptom:**

```
Waiting for a volume to be created either by the external provisioner
'ebs.csi.aws.com' or manually by the system administrator.
```

**Cause:** This cluster's Kubernetes version has EBS CSI migration enabled by
default, meaning even the "in-tree" `gp2` StorageClass
(`provisioner: kubernetes.io/aws-ebs`) actually routes volume requests through
the **AWS EBS CSI driver**. The driver was not installed on this cluster (no
`ebs-csi-controller` pods in `kube-system`), so the request just waited forever.

**Fix:** Install the EBS CSI driver addon via `eksctl` (handles the IAM
role/IRSA wiring automatically):

```bash
eksctl utils associate-iam-oidc-provider --cluster ajay-workspace --region us-east-2 --approve

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster ajay-workspace \
  --region us-east-2 \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

eksctl create addon \
  --cluster ajay-workspace \
  --region us-east-2 \
  --name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::573631993187:role/AmazonEKS_EBS_CSI_DriverRole \
  --force
```

Once the driver pods are `Running`, the existing PVC bound on its own — no need
to delete/recreate it again.

**Note:** This addon is cluster-wide infrastructure, not specific to this
project. `scripts/cleanup.sh` intentionally does not remove it.

---

### 5. `The K8sGPT "k8sgpt-ollama" is invalid: spec.ai.backend: Unsupported value: "ollama"`

**Cause:** The installed version of the K8sGPT operator's CRD does not include
`ollama` in its supported backend enum (only: `ibmwatsonxai`, `openai`,
`deepseek`, `localai`, `azureopenai`, `amazonbedrock`, `cohere`,
`amazonsagemaker`, `google`, `googlevertexai`, `customrest`). The native
`ollama` backend exists in newer K8sGPT CLI versions but hadn't landed in this
operator's CRD yet.

**Fix:** Since Ollama exposes an OpenAI-compatible API, use the `localai`
backend pointed at Ollama's `/v1` path instead:

```yaml
spec:
  ai:
    backend: localai
    baseUrl: http://ollama.ollama.svc.cluster.local:11434/v1
```

(Note the `/v1` suffix — this is required for the OpenAI-compatible endpoint and
is easy to miss.)

---

### 6. Same CRD validation error persists after "fixing" the CR

**Cause:** Not a real re-occurrence — a stale local copy of
`manifests/k8sgpt-ollama-cr.yaml` (downloaded before the fix) was being applied
instead of the corrected file.

**Fix:** Always verify the file content before reapplying:

```bash
grep backend manifests/k8sgpt-ollama-cr.yaml
```

should print `backend: localai`. If it doesn't match what you expect, re-fetch
or manually `sed`/edit the file rather than assuming a previous fix "didn't
take."

---

### 7. `kubectl get results` empty right after triggering a broken pod

**Cause:** Not an error — the operator's reconcile loop runs on a timer
(`RequeueTime: 30s` in the logs) and each analysis pass calls Ollama for an
explanation per finding, which takes real wall-clock time on a CPU-only model
(tens of seconds to a couple minutes depending on load). Checking too early just
sees an empty result set.

**Fix:** Wait 1–2 minutes after creating the broken resource, or use
`kubectl get results -n k8sgpt-operator-system -w` to watch live rather than
polling once.

---

## General lesson

Most of the friction here was in the platform layer (StorageClass / EBS CSI
driver / Karpenter CRD API details) rather than in Ollama or K8sGPT themselves —
worth checking `kubectl get storageclass`,
`kubectl get pods -n kube-system | grep ebs`, and the Karpenter CRD version
(`kubectl explain ec2nodeclass.spec`) up front on any new cluster before
assuming a guide's YAML will apply cleanly as-is.

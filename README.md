# Distributed Inference with llm-d on Red Hat OpenShift AI 3.x

**From Static Pods to Intelligent, Cache-Aware Routing**

> **The Problem:** Single-pod inference locks expensive GPUs to one workload; round-robin routing ignores cache affinity and burns GPU cycles on redundant prefill.  
> **The Solution:** Deploy **Distributed Inference with `llm-d`**—intelligent scheduling, Gateway API integration, and vLLM workers—so requests are routed to the right GPU and you maximize ROI.

This repository contains a complete **course-in-a-box** for **Distributed Inference (llm-d)** on Red Hat OpenShift AI 3.x. It guides platform engineers from business value and architecture through hands-on deployment, observability, and troubleshooting.

---

## Prerequisites

* **Cluster:** Red Hat OpenShift AI 3.x installed (OpenShift 4.19+, 4.20 recommended)
* **Access:** Permissions to create projects, apply `LLMInferenceService` CRs, and use the Gateway API (e.g. cluster-admin for operator install)
* **CLI:** `oc` installed and authenticated; `curl` for testing the inference API
* **Hardware:** At least one GPU node (NVIDIA; L40S, A100, H100 typical). NVIDIA GPU Operator and Node Feature Discovery (NFD) installed. Leader Worker Set (LWS) Operator for llm-d pod fleets

---

## Quick Start: Deploy llm-d Without Reading the Course

If you already have a GPU-enabled OpenShift AI 3.x cluster and want to get a distributed inference endpoint running quickly, follow these steps.

### 1. Clone the deployment repository

```bash
git clone https://github.com/RedHatQuickCourses/rhoai3-llmd-deploy.git
cd rhoai3-llmd-deploy
```

### 2. Run the environment setup

This script creates the namespace, deploys MinIO as a model vault, configures Data Connections, and stages the `granite-3.3-2b-instruct` model.

```bash
chmod u+x deploy/setup-llmd-env.sh
./deploy/setup-llmd-env.sh
```

Wait for the script to report **SUCCESS** (namespace, vault, and model staged).

### 3. Deploy the LLMInferenceService (llm-d)

Apply the distributed inference workload. This creates vLLM worker pods and the Inference Scheduler; the Gateway API will route traffic based on scheduler decisions.

```bash
oc apply -f deploy/llmd-deployment.yaml
oc wait --for=condition=Ready llminferenceservice/granite-distributed -n llmd-deploy-lab --timeout=300s
```

### 4. Verify and test

Confirm the HTTPRoute is created and get the inference URL:

```bash
oc get httproute -n llmd-deploy-lab
export INFERENCE_URL=$(oc get gateway openshift-ai-inference -n openshift-ingress -o jsonpath='{.status.addresses[0].value}')
echo "Gateway: http://$INFERENCE_URL/llmd-deploy-lab/granite-distributed/v1"
```

Test the endpoint:

```bash
curl -k -X POST "http://$INFERENCE_URL/llmd-deploy-lab/granite-distributed/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "granite-3.3-2b-instruct",
    "messages": [
      {"role": "user", "content": "Explain intelligent load balancing in 50 words."}
    ],
    "max_tokens": 80
  }'
```

Once you see a valid JSON response, llm-d is deployed and routing requests. For architecture, tuning, observability, and troubleshooting, use the full course below.

---

## Course structure (Antora)

| Part | Content |
|------|--------|
| **Introduction & value** | Business problem (idle GPUs, latency, Shadow AI); three pillars (TCO, performance, sovereignty); stack overview and prerequisites |
| **Architecture deep dive** | Control vs. execution plane; Gateway API, Inference Scheduler, vLLM workers; request lifecycle; observability (Golden Signals) |
| **Lab: Deploy llm-d** | GitOps deployment with `LLMInferenceService`; verify Gateway and test inference |
| **Day 2: Observability** | Golden Signals (TTFT, TPOT, GPU utilization); workload metrics; Kueue alerts and runbooks |
| **Troubleshooting** | Pods pending, Gateway address pending, 403 Forbidden, status false positives |
| **Summary** | Outcomes, implementation caveats, next steps |

---

## Build the full course

**Docker (recommended):**

```bash
docker run -u $(id -u) -v $PWD:/antora:Z --rm -t antora/antora antora-playbook.yml
# open build/site/index.html
```

**NPM:**

```bash
npm install
npx antora antora-playbook.yml
# open build/site/index.html
```

---

## Repository structure

```
/
├── modules/
│   ├── ROOT/
│   │   ├── nav.adoc
│   │   └── pages/
│   │       └── index.adoc          # Home (includes chapter1 intro)
│   └── chapter1/
│       ├── nav.adoc
│       └── pages/
│           ├── index.adoc         # Introduction & business value
│           ├── section1.adoc     # Architecture deep dive
│           ├── section2.adoc     # Lab: Deploy llm-d
│           ├── section3.adoc     # Day 2: Observability
│           ├── section4.adoc     # Troubleshooting
│           ├── section5.adoc     # Simulator (optional)
│           └── section6.adoc     # Summary
├── antora.yml
├── antora-playbook.yml
└── README.md
```

---

## Troubleshooting (quick reference)

| Symptom | Likely cause | Action |
|--------|----------------|--------|
| Pods stuck in **Pending** | Missing tolerations for GPU nodes | Add matching toleration to deployment or use a Hardware Profile that includes it |
| **Gateway address** empty | Load balancer not ready | Check `oc get svc -n istio-system` and cloud LB quota |
| **403 Forbidden** on inference | Auth (e.g. Authorino) requiring token | Pass a valid token: `curl -H "Authorization: Bearer $(oc create token default -n <namespace>)" ...` |
| Dashboard shows **Failed** while pods run | UI sync delay during init | Check pod logs; status often flips to *Started* when ready |

---

## See also

* [README-TRAINING.md](./README-TRAINING.md) — Template and repo setup
* [Development using devspace](./DEVSPACE.md)
* [Guideline for editing content](./USAGEGUIDE.adoc)
* Red Hat OpenShift AI: [Red Hat Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai/)

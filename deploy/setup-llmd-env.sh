#!/bin/bash

# =================================================================================
# SCRIPT: setup-llmd-env.sh
# DESCRIPTION: Sets up the prerequisites for the llm-d Distributed Inference Lab.
#              1. Deploys MinIO (The Vault).
#              2. Creates the RHOAI Data Connection (storage-config).
#              3. Downloads a model (Granite-3.3-2B) and uploads to MinIO via K8s Job.
# =================================================================================

set -e

# --- CONFIGURATION ---
NAMESPACE="llmd-deploy-lab"
MODEL_ID="ibm-granite/granite-3.3-2b-instruct"
S3_BUCKET="models"
S3_FOLDER="granite3"
MINIO_ACCESS_KEY="minio"
MINIO_SECRET_KEY="minio123"
SERVICE_ACCOUNT="fast-track-sa"

echo "🚀 Starting Distributed Inference Setup..."
echo "🎯 Target Model: $MODEL_ID"
echo "📂 Target Storage: s3://$S3_BUCKET/$S3_FOLDER"

# ---------------------------------------------------------------------------------
# 1. Namespace & MinIO (The Vault)
# ---------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo "Step 1: Checking Infrastructure..."

if ! oc get project "$NAMESPACE" > /dev/null 2>&1; then
    echo "➤ Creating namespace $NAMESPACE..."
    oc new-project "$NAMESPACE"
else
    echo "✔ Namespace $NAMESPACE exists."
fi

echo "➤ Deploying MinIO Object Storage (The Vault)..."
if [ -d "deploy/infrastructure" ]; then
    oc apply -f deploy/infrastructure/minio-backend.yaml -n "$NAMESPACE"
    oc apply -f deploy/infrastructure/s3ui-deployment.yaml -n "$NAMESPACE"
    echo "⏳ Waiting for MinIO to be ready..."
    oc wait --for=condition=available deployment/minio -n "$NAMESPACE" --timeout=300s || {
        echo "⚠️ MinIO deployment not ready after 5 minutes, continuing anyway..."
    }
else
    echo "❌ Error: Infrastructure YAML directory not found!"
    exit 1
fi

# ---------------------------------------------------------------------------------
# 2. Data Connection (The Wiring)
# ---------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo "Step 2: Wiring RHOAI Data Connection..."

# Create storage-config secret (required by KServe for InferenceService deployments)
oc create secret generic storage-config \
    --from-literal=AWS_ACCESS_KEY_ID="$MINIO_ACCESS_KEY" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$MINIO_SECRET_KEY" \
    --from-literal=AWS_S3_ENDPOINT="http://minio-service.$NAMESPACE.svc.cluster.local:9000" \
    --from-literal=AWS_DEFAULT_REGION="us-east-1" \
    --from-literal=AWS_S3_BUCKET="$S3_BUCKET" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | oc apply -f -

oc label secret storage-config \
    "opendatahub.io/dashboard=true" \
    "opendatahub.io/managed=true" \
    -n "$NAMESPACE" \
    --overwrite

# Create 'models' secret for the ingestion job
oc create secret generic models \
    --from-literal=AWS_ACCESS_KEY_ID="$MINIO_ACCESS_KEY" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$MINIO_SECRET_KEY" \
    --from-literal=AWS_S3_ENDPOINT="http://minio-service.$NAMESPACE.svc.cluster.local:9000" \
    --from-literal=AWS_DEFAULT_REGION="us-east-1" \
    --from-literal=AWS_S3_BUCKET="$S3_BUCKET" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | oc apply -f -

oc label secret models \
    "opendatahub.io/dashboard=true" \
    "opendatahub.io/managed=true" \
    -n "$NAMESPACE" \
    --overwrite

echo "✔ Data Connection secrets created."

# ---------------------------------------------------------------------------------
# 3. The Ingestion Job (The Loader)
# ---------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo "Step 3: Creating Ingestion Job..."

oc create sa $SERVICE_ACCOUNT -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
oc adm policy add-scc-to-user anyuid -z $SERVICE_ACCOUNT -n "$NAMESPACE" > /dev/null 2>&1

cat <<EOF > /tmp/fast_ingest.py
import os
import boto3
from huggingface_hub import snapshot_download
from botocore.client import Config

MODEL_ID = "${MODEL_ID}"
S3_BUCKET = "${S3_BUCKET}"
S3_FOLDER = "${S3_FOLDER}"
S3_ENDPOINT = os.getenv("AWS_S3_ENDPOINT")
AWS_ACCESS_KEY = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")

def main():
    print(f"\n=== DOWNLOADING {MODEL_ID} ===")
    local_dir = snapshot_download(repo_id=MODEL_ID, allow_patterns=["*.json", "*.safetensors", "*.model", "tokenizer*"])

    print(f"\n=== UPLOADING TO MINIO ===")
    s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT,
                      aws_access_key_id=AWS_ACCESS_KEY,
                      aws_secret_access_key=AWS_SECRET_KEY,
                      config=Config(signature_version='s3v4'))
    try:
        s3.create_bucket(Bucket=S3_BUCKET)
    except:
        pass

    for root, dirs, files in os.walk(local_dir):
        for file in files:
            local_path = os.path.join(root, file)
            relative_path = os.path.relpath(local_path, local_dir)
            s3_key = os.path.join(S3_FOLDER, relative_path)
            
            if relative_path == "config.json":
                 print(f"Uploading Config: s3://{S3_BUCKET}/{s3_key}")
            s3.upload_file(local_path, S3_BUCKET, s3_key)
            
    print(f"\n✅ SUCCESS: Model ready in s3://{S3_BUCKET}/{S3_FOLDER}")

if __name__ == "__main__":
    main()
EOF

oc create configmap fast-track-code --from-file=/tmp/fast_ingest.py -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -

oc delete job fast-track-loader -n "$NAMESPACE" --ignore-not-found

cat <<YAML | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: fast-track-loader
  namespace: $NAMESPACE
spec:
  backoffLimit: 1
  template:
    spec:
      serviceAccountName: $SERVICE_ACCOUNT
      containers:
      - name: loader
        image: registry.access.redhat.com/ubi9/python-311:latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            pip install boto3 huggingface-hub --quiet --no-cache-dir && \
            python /scripts/fast_ingest.py
        volumeMounts:
        - name: code-volume
          mountPath: /scripts
        env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom: { secretKeyRef: { name: models, key: AWS_ACCESS_KEY_ID } }
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom: { secretKeyRef: { name: models, key: AWS_SECRET_ACCESS_KEY } }
        - name: AWS_S3_ENDPOINT
          valueFrom: { secretKeyRef: { name: models, key: AWS_S3_ENDPOINT } }
      restartPolicy: Never
      volumes:
      - name: code-volume
        configMap:
          name: fast-track-code
YAML

echo "⏳ Job submitted. Waiting for model download and upload to complete (takes ~5-10 mins)..."

TIMEOUT=1200 
if oc wait --for=condition=complete job/fast-track-loader -n "$NAMESPACE" --timeout=${TIMEOUT}s; then
    echo "✅ SUCCESS: Namespace, Vault, and Model Staged."
else
    echo "❌ Job failed or timed out."
    exit 1
fi
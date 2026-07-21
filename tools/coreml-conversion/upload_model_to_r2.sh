#!/usr/bin/env bash
# Upload a converted .mlpackage to the models R2 bucket in the exact layout the
# apps' ModelDownloader fetches: v1/<Name>/{Manifest.json, model.mlmodel, weight.bin}
# (served from https://models-data.hakobs.com/v1/<Name>/…).
#
# Requires Cloudflare R2 S3-compatible credentials in the environment:
#   R2_ENDPOINT             https://<account-id>.r2.cloudflarestorage.com
#   R2_BUCKET               the bucket bound to models-data.hakobs.com
#   AWS_ACCESS_KEY_ID       an R2 API token's access key id
#   AWS_SECRET_ACCESS_KEY   its secret
#
# Usage:
#   R2_ENDPOINT=… R2_BUCKET=… AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… \
#     ./upload_model_to_r2.sh ./out/AuraSR.mlpackage AuraSR
set -euo pipefail

PKG="${1:?path to the .mlpackage}"
NAME="${2:?model name (the folder under v1/, e.g. AuraSR)}"
: "${R2_ENDPOINT:?set R2_ENDPOINT}"
: "${R2_BUCKET:?set R2_BUCKET}"
: "${AWS_ACCESS_KEY_ID:?set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?set AWS_SECRET_ACCESS_KEY}"

put() {
  echo "  → v1/${NAME}/$2"
  aws s3 cp "$1" "s3://${R2_BUCKET}/v1/${NAME}/$2" \
    --endpoint-url "$R2_ENDPOINT" --no-progress
}

echo "Uploading ${PKG} as ${NAME}…"
put "${PKG}/Manifest.json" "Manifest.json"
put "${PKG}/Data/com.apple.CoreML/model.mlmodel" "model.mlmodel"
put "${PKG}/Data/com.apple.CoreML/weights/weight.bin" "weight.bin"
echo "Done. ${NAME} is live at https://models-data.hakobs.com/v1/${NAME}/"

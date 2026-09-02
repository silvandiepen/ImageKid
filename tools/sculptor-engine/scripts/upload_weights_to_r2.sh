#!/usr/bin/env bash
# Upload Sculptor reconstruction weights to the models R2 bucket, in the exact
# layout SculptorModelDownloader fetches:
#
#   v1/<Name>/<version>/{config.yaml, model.ckpt}
#
# served from https://models-data.hakobs.com/v1/<Name>/<version>/…
#
# The app's in-app "Install Model" button cannot work until this has been run:
# without it the download 404s. This is the Sculptor equivalent of
# tools/coreml-conversion/upload_model_to_r2.sh.
#
# Requires Cloudflare R2 S3-compatible credentials in the environment:
#   R2_ENDPOINT             https://<account-id>.r2.cloudflarestorage.com
#   R2_BUCKET               the bucket bound to models-data.hakobs.com
#   AWS_ACCESS_KEY_ID       an R2 API token's access key id
#   AWS_SECRET_ACCESS_KEY   its secret
#
# Usage, after scripts/fetch_weights.py has installed them locally:
#   R2_ENDPOINT=… R2_BUCKET=… AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… \
#     ./scripts/upload_weights_to_r2.sh TripoSR v1
#
# Check the licence before publishing any weights. TripoSR is MIT, which permits
# redistribution with its notice; SPAR3D's Community License does not grant the
# same freedom, so do not mirror it without reading the terms.
set -euo pipefail

NAME="${1:-TripoSR}"
VERSION="${2:-v1}"
: "${R2_ENDPOINT:?set R2_ENDPOINT}"
: "${R2_BUCKET:?set R2_BUCKET}"
: "${AWS_ACCESS_KEY_ID:?set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?set AWS_SECRET_ACCESS_KEY}"

group_container="$HOME/Library/Group Containers/group.com.hakobs.imagekid"
source_dir="${SCULPTOR_MODELS_DIR:-$group_container/Models/Sculptor}/$NAME/$VERSION"

if [ ! -d "$source_dir" ]; then
  echo "no weights at $source_dir — run scripts/fetch_weights.py first" >&2
  exit 1
fi

case "$NAME" in
  TripoSR) files=("config.yaml" "model.ckpt") ;;
  SPAR3D)  files=("config.yaml" "model.safetensors") ;;
  *) echo "unknown model: $NAME" >&2; exit 2 ;;
esac

for file in "${files[@]}"; do
  if [ ! -f "$source_dir/$file" ]; then
    echo "missing $source_dir/$file" >&2
    exit 1
  fi
done

echo "Uploading $NAME $VERSION from $source_dir…"
for file in "${files[@]}"; do
  echo "  → v1/$NAME/$VERSION/$file"
  aws s3 cp "$source_dir/$file" \
    "s3://${R2_BUCKET}/v1/${NAME}/${VERSION}/${file}" \
    --endpoint-url "$R2_ENDPOINT" --no-progress
done

echo "Done. Live at https://models-data.hakobs.com/v1/${NAME}/${VERSION}/"
echo "Verify with: curl -sI https://models-data.hakobs.com/v1/${NAME}/${VERSION}/config.yaml"

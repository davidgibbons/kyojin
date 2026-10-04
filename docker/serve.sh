#!/usr/bin/env bash
# Container entrypoint: kyojin-serve <glm|mimo> [server args...]
#
#   MODEL_DIR   model pack directory (required)
#   MODEL_REPO  Hugging Face repo to download into MODEL_DIR when it has no
#               config.json yet (optional)
#   LANE_STATE  writable scratch dir: tune cache, slots, tmp (default /tmp/lane)
#   PORT        listen port (default 8000)
#   GLM_EH_REPO repo holding GLM's unquantized MTP eh_proj; fetched into
#               LANE_STATE for EXL3_MTP_EH_FP16 (default zai-org/GLM-5.3-Flash)
set -euo pipefail
lane=${1:?usage: kyojin-serve <glm|mimo> [args...]}; shift
: "${MODEL_DIR:?set MODEL_DIR}"
export LANE_STATE=${LANE_STATE:-/tmp/lane}
mkdir -p "$LANE_STATE/slots"

if [ ! -f "$MODEL_DIR/config.json" ]; then
  : "${MODEL_REPO:?$MODEL_DIR has no config.json and MODEL_REPO is unset}"
  /opt/kyojin/.venv/bin/hf download "$MODEL_REPO" --local-dir "$MODEL_DIR"
fi

case "$lane" in
  glm)
    export GLM_MODEL=$MODEL_DIR
    # serve.py expects this sidecar and the published packs do not include it.
    export EXL3_MTP_EH_FP16=${EXL3_MTP_EH_FP16:-$LANE_STATE/glm53-mtp-eh-proj-bf16.safetensors}
    if [ "$EXL3_MTP_EH_FP16" != 0 ] && [ ! -f "$EXL3_MTP_EH_FP16" ]; then
      /opt/kyojin/.venv/bin/python /opt/kyojin/docker/glm_eh_sidecar.py \
        "${GLM_EH_REPO:-zai-org/GLM-5.3-Flash}" "$EXL3_MTP_EH_FP16"
    fi
    ;;
  mimo) export MIMO_MODEL=$MODEL_DIR ;;
  *) echo "kyojin-serve: unknown lane $lane" >&2; exit 2 ;;
esac
exec bash "/opt/kyojin/tools/lanes/serve_$lane.sh" \
  --host 0.0.0.0 --port "${PORT:-8000}" --slot-save-path "$LANE_STATE/slots" "$@"

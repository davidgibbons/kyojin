#!/usr/bin/env bash
# Container entrypoint: kyojin-serve <glm|mimo> [server args...]
#
#   MODEL_DIR   model pack directory (required)
#   MODEL_REPO  Hugging Face repo to download into MODEL_DIR when it has no
#               config.json yet (optional)
#   LANE_STATE  writable scratch dir: tune cache, slots, tmp (default /tmp/lane)
#   PORT        listen port (default 8000)
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
  glm)  export GLM_MODEL=$MODEL_DIR ;;
  mimo) export MIMO_MODEL=$MODEL_DIR ;;
  *) echo "kyojin-serve: unknown lane $lane" >&2; exit 2 ;;
esac
exec bash "/opt/kyojin/tools/lanes/serve_$lane.sh" \
  --host 0.0.0.0 --port "${PORT:-8000}" --slot-save-path "$LANE_STATE/slots" "$@"

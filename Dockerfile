# Kyojin serving image for AMD Strix Halo (gfx1151). Entrypoint usage: docker/serve.sh.
FROM ubuntu:24.04

ARG ROCM_INDEX=https://rocm.nightlies.amd.com/v2/gfx1151/
ARG MAX_JOBS=4

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-dev build-essential git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/kyojin
ENV EXL3_ROOT=/opt/kyojin \
    EXL3_VENV=/opt/kyojin/.venv \
    EXL3_HSA_LIB=/opt/hsa/libhsa-runtime64.so.1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN python3 -m venv .venv \
 && .venv/bin/pip install --no-cache-dir --pre torch --index-url "$ROCM_INDEX" \
 && .venv/bin/pip install --no-cache-dir -r requirements.txt

COPY . .

# The devel SDK is about 12 GB once expanded and only the compiler needs it,
# so it is installed, used and deleted in one layer. The HSA runtime is the
# one file kept: torch's own copy segfaults on gfx1151 (tools/strix_halo/env.sh,
# trap 1) and the lane scripts preload this one instead.
RUN set -eux; \
    rocm_ver=$(.venv/bin/pip show rocm | awk '/^Version:/ {print $2}'); \
    .venv/bin/pip install --no-cache-dir --pre "rocm-sdk-devel==$rocm_ver" --index-url "$ROCM_INDEX"; \
    .venv/bin/rocm-sdk init; \
    export EXL3_ROCM_SDK=$(.venv/bin/rocm-sdk path --root); \
    mkdir -p /opt/hsa; \
    cp -L "$EXL3_ROCM_SDK"/lib/libhsa-runtime64.so.1 /opt/hsa/; \
    MAX_JOBS=$MAX_JOBS ./build.sh; \
    ls exllamav3_ext*.so; \
    case "$EXL3_ROCM_SDK" in */_rocm_sdk_devel) rm -rf "$EXL3_ROCM_SDK";; esac; \
    .venv/bin/pip uninstall -y rocm-sdk-devel; \
    rm -rf build /root/.cache; \
    .venv/bin/pip freeze | grep -iE '^(torch|rocm|triton)'

COPY docker/serve.sh /usr/local/bin/kyojin-serve
ENTRYPOINT ["/usr/local/bin/kyojin-serve"]

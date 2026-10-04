# Kyojin serving image for AMD Strix Halo (gfx1151). Entrypoint usage: docker/serve.sh.
FROM ubuntu:24.04

ARG ROCM_INDEX=https://rocm.nightlies.amd.com/v2/gfx1151/
ARG MAX_JOBS=4

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-dev build-essential git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && (getent group 102 || groupadd -g 102 kyojin) \
 && useradd -u 101 -g 102 -M -d /tmp -s /usr/sbin/nologin kyojin

WORKDIR /opt/kyojin
ENV EXL3_ROOT=/opt/kyojin \
    EXL3_VENV=/opt/kyojin/.venv \
    PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN python3 -m venv .venv \
 && .venv/bin/pip install --no-cache-dir --pre torch --index-url "$ROCM_INDEX" \
 && .venv/bin/pip install --no-cache-dir -r requirements.txt

COPY . .

# The devel SDK is about 12 GB once expanded and only the compiler needs it,
# so it is installed, used and deleted in one layer.
ARG HSA_LIB=/opt/kyojin/.venv/lib/python3.12/site-packages/_rocm_sdk_core/lib/libhsa-runtime64.so.1
RUN set -eux; \
    rocm_ver=$(.venv/bin/pip show rocm | awk '/^Version:/ {print $2}'); \
    .venv/bin/pip install --no-cache-dir --pre "rocm-sdk-devel==$rocm_ver" --index-url "$ROCM_INDEX"; \
    .venv/bin/rocm-sdk init; \
    export EXL3_ROCM_SDK=$(.venv/bin/rocm-sdk path --root); \
    MAX_JOBS=$MAX_JOBS ./build.sh; \
    ls exllamav3_ext*.so; \
    case "$EXL3_ROCM_SDK" in */_rocm_sdk_devel) rm -rf "$EXL3_ROCM_SDK";; esac; \
    .venv/bin/pip uninstall -y rocm-sdk-devel; \
    rm -rf build /root/.cache; \
    .venv/bin/pip freeze | grep -iE '^(torch|rocm|triton)'; \
    test -e "$HSA_LIB"

# Set only after the build: env.sh preloads it into every process, and the
# build must preload the devel SDK's copy instead.
ENV EXL3_HSA_LIB=$HSA_LIB
COPY docker/serve.sh /usr/local/bin/kyojin-serve
# torch resolves its cache dir from the passwd entry, so the uid needs one.
USER 101:102
ENTRYPOINT ["/usr/local/bin/kyojin-serve"]

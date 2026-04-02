#!/usr/bin/env bash
set -euo pipefail

if ! command -v llama-server >/dev/null 2>&1; then
  echo "Error: llama-server not found. Install with: brew install llama.cpp" >&2
  exit 1
fi

HOST="${ATLAS_LLM_HOST:-127.0.0.1}"
PORT="${ATLAS_LLM_PORT:-8080}"
MODEL_ALIAS="${ATLAS_LLM_MODEL_ALIAS:-atlas-local-3b}"
ARCH="$(uname -m)"
LOGICAL_CPU="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
PERF_CPU="$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "${LOGICAL_CPU}")"
MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 17179869184)"
MEM_GB="$(( MEM_BYTES / 1024 / 1024 / 1024 ))"
HIGH_CAPACITY=0
if [[ "${MEM_GB}" -ge 32 && "${LOGICAL_CPU}" -ge 10 ]]; then
  HIGH_CAPACITY=1
fi

DEFAULT_CTX_SIZE="16384"
DEFAULT_PARALLEL="3"
DEFAULT_BATCH="4096"
DEFAULT_UBATCH="2048"
DEFAULT_THREADS_HTTP="4"
if [[ "${HIGH_CAPACITY}" -eq 1 ]]; then
  DEFAULT_CTX_SIZE="32768"
  DEFAULT_PARALLEL="4"
  DEFAULT_BATCH="8192"
  DEFAULT_UBATCH="4096"
  DEFAULT_THREADS_HTTP="8"
fi

CTX_SIZE="${ATLAS_LLM_CTX_SIZE:-${DEFAULT_CTX_SIZE}}"
PARALLEL_SLOTS="${ATLAS_LLM_PARALLEL:-${DEFAULT_PARALLEL}}"
THREADS="${ATLAS_LLM_THREADS:-}"
THREADS_BATCH="${ATLAS_LLM_THREADS_BATCH:-${LOGICAL_CPU}}"
THREADS_HTTP="${ATLAS_LLM_THREADS_HTTP:-${DEFAULT_THREADS_HTTP}}"
GPU_LAYERS="${ATLAS_LLM_GPU_LAYERS:-auto}"
BATCH_SIZE="${ATLAS_LLM_BATCH_SIZE:-${DEFAULT_BATCH}}"
UBATCH_SIZE="${ATLAS_LLM_UBATCH_SIZE:-${DEFAULT_UBATCH}}"
FLASH_ATTN="${ATLAS_LLM_FLASH_ATTN:-auto}"
REASONING_FORMAT="${ATLAS_LLM_REASONING_FORMAT:-}"
CACHE_REUSE="${ATLAS_LLM_CACHE_REUSE:-512}"
MODEL_PATH="${ATLAS_LLM_MODEL_PATH:-}"
HF_REPO="${ATLAS_LLM_HF_REPO:-}"
HF_FILE="${ATLAS_LLM_HF_FILE:-}"
API_KEY="${ATLAS_LLM_API_KEY:-}"

if [[ -z "${THREADS}" ]]; then
  if [[ "${ARCH}" == "arm64" ]]; then
    THREADS="${LOGICAL_CPU}"
  else
    THREADS="${LOGICAL_CPU}"
  fi
fi

if [[ "${ARCH}" == "arm64" && "${FLASH_ATTN}" == "auto" ]]; then
  FLASH_ATTN="on"
fi

if [[ -z "${MODEL_PATH}" && -z "${HF_REPO}" ]]; then
  cat >&2 <<'EOF'
Error: no model source configured.

Provide one of:
- ATLAS_LLM_MODEL_PATH=/abs/path/model.gguf
- ATLAS_LLM_HF_REPO=<user>/<repo>[:quant]

Example:
ATLAS_LLM_HF_REPO=unsloth/Qwen2.5-3B-Instruct-GGUF:q4_k_m \
ATLAS_LLM_MODEL_ALIAS=atlas-local-3b \
./scripts/start-local-llm-runtime.sh
EOF
  exit 1
fi

args=(
  --host "${HOST}"
  --port "${PORT}"
  --alias "${MODEL_ALIAS}"
  --ctx-size "${CTX_SIZE}"
  --parallel "${PARALLEL_SLOTS}"
  --threads "${THREADS}"
  --threads-batch "${THREADS_BATCH}"
  --threads-http "${THREADS_HTTP}"
  --batch-size "${BATCH_SIZE}"
  --ubatch-size "${UBATCH_SIZE}"
  --cache-reuse "${CACHE_REUSE}"
  --prio "2"
  --prio-batch "2"
  --flash-attn "${FLASH_ATTN}"
  --n-gpu-layers "${GPU_LAYERS}"
  --metrics
  --jinja
  --mlock
)

if [[ -n "${API_KEY}" ]]; then
  args+=(--api-key "${API_KEY}")
fi

if [[ -n "${REASONING_FORMAT}" ]]; then
  args+=(--reasoning-format "${REASONING_FORMAT}")
fi

if [[ -n "${MODEL_PATH}" ]]; then
  if [[ ! -f "${MODEL_PATH}" ]]; then
    echo "Error: model file not found: ${MODEL_PATH}" >&2
    exit 1
  fi
  args+=(--model "${MODEL_PATH}")
else
  args+=(--hf-repo "${HF_REPO}")
  if [[ -n "${HF_FILE}" ]]; then
    args+=(--hf-file "${HF_FILE}")
  fi
fi

echo "Starting local LLM runtime..."
echo "Endpoint: http://${HOST}:${PORT}/v1/chat/completions"
echo "Model alias: ${MODEL_ALIAS}"
echo "Hardware profile: arch=${ARCH} mem=${MEM_GB}GB logical_cpu=${LOGICAL_CPU} perf_cpu=${PERF_CPU}"
echo "Launch profile: ctx=${CTX_SIZE} parallel=${PARALLEL_SLOTS} threads=${THREADS}/${THREADS_BATCH} http_threads=${THREADS_HTTP} batch=${BATCH_SIZE} ubatch=${UBATCH_SIZE} cache_reuse=${CACHE_REUSE} flash_attn=${FLASH_ATTN} gpu_layers=${GPU_LAYERS} mlock=on"

if [[ "${ARCH}" == "arm64" ]] && otool -L "$(command -v llama-server)" 2>/dev/null | grep -qi 'libggml-metal'; then
  echo "Runtime check: llama-server is linked with libggml-metal"
  if llama-server --list-devices 2>/dev/null | grep -qi 'metal'; then
    echo "Device backend: Metal available"
  else
    echo "Runtime note: libggml-metal is linked, but device enumeration did not report Metal explicitly."
  fi
elif [[ "${ARCH}" == "arm64" ]]; then
  echo "Warning: llama-server does not appear linked with libggml-metal. Local inference may be CPU/Accelerate-bound."
fi

exec llama-server "${args[@]}"

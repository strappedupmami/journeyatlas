#!/usr/bin/env bash
set -euo pipefail

if ! command -v llama-server >/dev/null 2>&1; then
  echo "Error: llama-server not found. Install with: brew install llama.cpp" >&2
  exit 1
fi

HOST="${ATLAS_LLM_HOST:-127.0.0.1}"
PORT="${ATLAS_LLM_PORT:-8080}"
MODEL_ALIAS="${ATLAS_LLM_MODEL_ALIAS:-atlas-local-3b}"
CTX_SIZE="${ATLAS_LLM_CTX_SIZE:-4096}"
PARALLEL_SLOTS="${ATLAS_LLM_PARALLEL:-2}"
THREADS="${ATLAS_LLM_THREADS:-}"
GPU_LAYERS="${ATLAS_LLM_GPU_LAYERS:-auto}"
MODEL_PATH="${ATLAS_LLM_MODEL_PATH:-}"
HF_REPO="${ATLAS_LLM_HF_REPO:-}"
HF_FILE="${ATLAS_LLM_HF_FILE:-}"
API_KEY="${ATLAS_LLM_API_KEY:-}"

if [[ -z "${THREADS}" ]]; then
  if command -v sysctl >/dev/null 2>&1; then
    THREADS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
  else
    THREADS="8"
  fi
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
  --n-gpu-layers "${GPU_LAYERS}"
  --jinja
)

if [[ -n "${API_KEY}" ]]; then
  args+=(--api-key "${API_KEY}")
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

exec llama-server "${args[@]}"

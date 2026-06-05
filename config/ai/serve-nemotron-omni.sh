#!/usr/bin/env bash
################################################################################
# serve-nemotron-omni.sh — serve NVIDIA Nemotron 3 Nano Omni with vLLM.
#
# Nemotron 3 Nano Omni is an open multimodal MoE foundation model: 30B total
# params, ~3B active per forward pass, hybrid Mamba-Transformer. It perceives
# text, images, audio, video, documents, charts, and GUIs — output is text only
# (perception + reasoning engine, not an image/audio generator). 256k context.
#
# Tuned for NVIDIA RTX PRO Blackwell. The flags below match NVIDIA's published
# serving recipe, including `--moe-backend triton` — the documented workaround
# for the FlashInfer bug on RTX Pro cards.
#
# ── VRAM ──────────────────────────────────────────────────────────────────────
#   FP8 weights ≈ 30 GB → will NOT fit a 24 GB RTX PRO 4000.
#     • RTX PRO 4000 (24 GB):  use the NVFP4 variant (≈ half the VRAM), e.g.
#         MODEL=nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4
#     • RTX PRO 6000 / B200 (≥ 48 GB):  the FP8 default fits comfortably.
#
# ── Requires ──────────────────────────────────────────────────────────────────
#   vLLM >= 0.20.0   (uv tool install vllm  — see ai-workstation-toolchain.sh)
#   CUDA 12.9 / 13.0
#   For audio input inside a container:  python3 -m pip install "vllm[audio]"
#
# ── Override anything via env ───────────────────────────────────────────────────
#   MODEL=...           HF repo id or local path (default: FP8 reasoning variant)
#   QUANT=modelopt      vLLM quantization (NVIDIA's FP8/NVFP4 checkpoints are
#                       ModelOpt-quantized — proven on this box's Qwen3-8B-NVFP4
#                       server). Set QUANT="" for a vanilla/BF16 checkpoint.
#   PORT=8000  TP=1  MAX_MODEL_LEN=131072  MAX_NUM_SEQS=384
#   VLLM_EXTRA_ARGS="--gpu-memory-utilization 0.92"   appended verbatim
################################################################################
set -euo pipefail

MODEL="${MODEL:-nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-FP8}"
PORT="${PORT:-8000}"
TP="${TP:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-131072}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-384}"
QUANT="${QUANT-modelopt}"   # `-` not `:-`: QUANT="" disables it for BF16 checkpoints

if ! command -v vllm &>/dev/null; then
    echo "error: vllm not found on PATH. Install it first:" >&2
    echo "       uv tool install vllm --python 3.12   (or: claw install ai-workstation --inference-only)" >&2
    exit 1
fi

echo "» serving $MODEL on :$PORT (TP=$TP, ctx=$MAX_MODEL_LEN)"

# shellcheck disable=SC2086  # VLLM_EXTRA_ARGS is intentionally word-split
exec vllm serve "$MODEL" \
    --host 0.0.0.0 --port "$PORT" \
    --tensor-parallel-size "$TP" \
    --max-model-len "$MAX_MODEL_LEN" \
    --max-num-seqs "$MAX_NUM_SEQS" \
    --trust-remote-code \
    ${QUANT:+--quantization "$QUANT"} \
    --reasoning-parser nemotron_v3 \
    --enable-auto-tool-choice --tool-call-parser qwen3_coder \
    --kv-cache-dtype fp8 \
    --moe-backend triton \
    --video-pruning-rate 0.5 \
    --media-io-kwargs '{"video": {"fps": 2, "num_frames": 256}}' \
    --allowed-local-media-path / \
    ${VLLM_EXTRA_ARGS:-}

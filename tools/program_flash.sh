#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bitstream="$repo_dir/build/gowin/impl/pnr/fpga_project.fs"
flash_frequency=${OPENFPGALOADER_FREQ:-1000000}

if ! command -v openFPGALoader >/dev/null; then
  echo "openFPGALoader is required; install the openfpgaloader package" >&2
  exit 1
fi

if [[ ! -f "$bitstream" ]]; then
  echo "bitstream not found; run make fpga first" >&2
  exit 1
fi

if [[ ! "$flash_frequency" =~ ^[1-9][0-9]*$ ]]; then
  echo "OPENFPGALOADER_FREQ must be a positive frequency in Hz" >&2
  exit 1
fi

exec openFPGALoader \
  -b tangnano9k \
  -f \
  --freq "$flash_frequency" \
  "$bitstream"

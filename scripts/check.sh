#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash scripts/grep-gates.sh
gleam format --check src test
gleam build --target erlang --warnings-as-errors
gleam build --target javascript --warnings-as-errors
gleam test
gleam docs build

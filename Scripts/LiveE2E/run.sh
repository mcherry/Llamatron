#!/bin/zsh
# Compiles the Foundation-only Llamatron context-pipeline sources together with the
# live driver and runs them against a real Ollama server (outside the app sandbox,
# unlike the hosted XCTest process). Run from the repo root: ./Scripts/LiveE2E/run.sh
set -e
cd "$(dirname "$0")/../.."

SRC=(
  Llamatron/Models/Role.swift
  Llamatron/Services/OllamaDTOs.swift
  Llamatron/Services/OllamaClient.swift
  Llamatron/Services/ContextAssembler.swift
  Llamatron/Support/TokenEstimator.swift
  Llamatron/Support/TextChunker.swift
  Llamatron/Support/Vector.swift
  Llamatron/Support/TextTruncator.swift
  Llamatron/Support/ContextStrategy.swift
  Llamatron/Support/ContextBudget.swift
  Llamatron/Support/ContextPlanner.swift
  Scripts/LiveE2E/main.swift
)

BIN=/tmp/llamatron-e2e
echo "Compiling live driver…"
swiftc -O "${SRC[@]}" -o "$BIN"
echo "Running…"
"$BIN"

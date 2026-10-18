#!/bin/zsh
# Builds the live driver against the LlamaEngine checkout beside this repo (or
# $LLAMAENGINE_PATH) and runs it against a real Ollama server.
# Run from anywhere: ./Scripts/LiveE2E/run.sh
set -e
cd "$(dirname "$0")/../.."

ENGINE="${LLAMAENGINE_PATH:-$PWD/../LlamaEngine}"
if [[ ! -f "$ENGINE/Package.swift" ]]; then
  echo "LlamaEngine not found at $ENGINE — clone it beside this repo or set LLAMAENGINE_PATH."
  exit 2
fi
ENGINE="${ENGINE:A}"

# A fixed scratch package so repeat runs build incrementally.
PKG="${TMPDIR:-/tmp}/llamatron-live-e2e"
mkdir -p "$PKG/Sources/LiveE2E"
cp Scripts/LiveE2E/main.swift "$PKG/Sources/LiveE2E/main.swift"
cat > "$PKG/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiveE2E",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "$ENGINE")],
    targets: [
        .executableTarget(
            name: "LiveE2E",
            dependencies: [.product(name: "LlamaEngine", package: "LlamaEngine")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
EOF

echo "Building live driver against $ENGINE…"
swift build -c release --package-path "$PKG"
echo "Running…"
"$PKG/.build/release/LiveE2E"

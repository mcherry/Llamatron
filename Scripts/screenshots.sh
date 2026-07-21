#!/usr/bin/env bash
#
# One-shot, reproducible iPad screenshots for Llamatron.
#
# Regenerates the Xcode project, ensures the frameable simulator exists, captures a
# landscape iPad screenshot from anonymized seeded app state, wraps it in an iPad
# device frame, and refreshes the README hero image. Run any time.
#
# One-time setup:
#   brew install fastlane              # if needed
#   fastlane frameit download_frames   # downloads device frames (first run only)
#
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

# The iPad model we shoot on: it is the newest iPad Pro that fastlane's frameit has a
# device frame for (the current M-series iPads are too new for the frames repo).
readonly DEVICE="iPad Pro (12.9-inch) (4th generation)"
readonly DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro--12-9-inch---4th-generation-"

echo "==> Ensuring simulator '$DEVICE' exists"
if ! xcrun simctl list devices | grep -q "$DEVICE ("; then
  runtime="$(xcrun simctl list runtimes | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS[0-9.-]*' | tail -1)"
  xcrun simctl create "$DEVICE" "$DEVICE_TYPE" "$runtime"
fi

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Capturing screenshots (fastlane snapshot)"
fastlane ios screenshots

echo "==> Framing (fastlane frameit)"
( cd fastlane/screenshots && fastlane frameit )

# Copy the newest framed shot into docs/ for the README hero.
framed="$(ls -t fastlane/screenshots/en-US/*_framed.png 2>/dev/null | head -1 || true)"
if [ -n "$framed" ]; then
  mkdir -p docs
  cp "$framed" docs/screenshot-ipad.png
  echo "==> Hero copied to docs/screenshot-ipad.png"
else
  echo "!! No framed screenshot found. If frames are missing, run: fastlane frameit download_frames"
  exit 1
fi

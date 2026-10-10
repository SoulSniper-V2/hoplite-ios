#!/bin/zsh
# Usage: scripts/shot.sh <name> [wait-seconds] [launch args...]
# Relaunches the built app in the booted simulator with debug launch arguments and saves a screenshot.
set -e
name=$1; shift
wait=${1:-3}; shift || true
DEVICE=${DEVICE:-F0B9C225-1936-44A4-B119-0FD1CC80EC75}
APP=build/Build/Products/Debug-iphonesimulator/Hoplite.app
mkdir -p shots
xcrun simctl terminate $DEVICE sh.hoplite.mobile 2>/dev/null || true
xcrun simctl install $DEVICE $APP
sleep 1
xcrun simctl launch --terminate-running-process $DEVICE sh.hoplite.mobile "$@" >/dev/null
sleep $wait
xcrun simctl io $DEVICE screenshot --type=png shots/$name.png >/dev/null 2>&1
echo shots/$name.png

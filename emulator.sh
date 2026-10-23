#!/usr/bin/env bash
# Opens the virtual Android phone, puts the newest app on it and starts it.
# The phone runs on its own, apart from this terminal, so it stays open after
# this script ends. Close it with the X of its window.
cd "$(dirname "$0")"
sdk=~/Android/Sdk
adb=$sdk/platform-tools/adb

if ! $adb devices | grep -q "^emulator-.*device$"; then
  echo "Starting the phone, this takes about a minute..."
  # -allow-host-audio lets the phone hear this computer's microphone.
  setsid nohup $sdk/emulator/emulator -avd explainly -no-snapshot-save -allow-host-audio \
    > /tmp/explainly-emulator.log 2>&1 < /dev/null &
  $adb wait-for-device
  until [ "$($adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
fi

./install_apk.sh "$($adb devices | awk '/^emulator-/ {print $1; exit}')"

#!/usr/bin/env bash
# Builds the Android app:
#   Explainly.apk            for a real phone (arm64)
#   Explainly-emulator.apk   for the virtual phone (x86_64)
#
#   ./build_apk.sh        the app reaches the server through the USB cable.
#                         Works in any network. This is the normal way.
#   ./build_apk.sh wifi   the app reaches the server over Wi-Fi, no cable.
#                         Phone and computer must be in the same network, and
#                         you build again every time the computer's address changes.
cd "$(dirname "$0")/mobile"
export ANDROID_HOME=~/Android/Sdk
url=http://localhost:8000
[ "$1" = wifi ] && url=http://$(hostname -I | awk '{print $1}'):8000
echo "Server address in the app: $url"

~/development/flutter/bin/flutter build apk --release --split-per-abi --dart-define=API_URL=$url || exit 1
out=build/app/outputs/flutter-apk
cp $out/app-arm64-v8a-release.apk ../Explainly.apk
cp $out/app-x86_64-release.apk ../Explainly-emulator.apk
echo "Ready: $(cd .. && pwd)/Explainly.apk"

# If the emulator is open or a phone is connected by USB, put the new app on it.
for device in $($ANDROID_HOME/platform-tools/adb devices | awk 'NR>1 && $2=="device" {print $1}'); do
  ../install_apk.sh "$device"
done

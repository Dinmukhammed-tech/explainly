#!/usr/bin/env bash
# Puts the app on a phone connected by USB (or on the emulator), links it to
# the server on this computer through the cable, and opens it.
#   install_apk.sh [device id]      without an id: every connected device
#
# Run it again after you plug the phone in: the link through the cable is
# lost when the cable is pulled out.
cd "$(dirname "$0")"
adb=~/Android/Sdk/platform-tools/adb
app=kz.sdu.explainly.explainly
devices=${1:-$($adb devices | awk 'NR>1 && $2=="device" {print $1}')}
[ -z "$devices" ] && { echo "No phone or emulator is connected."; exit 1; }

for device in $devices; do
  case "$($adb -s "$device" shell getprop ro.product.cpu.abi | tr -d '\r')" in
    x86_64) apk=Explainly-emulator.apk ;;
    *)      apk=Explainly.apk ;;
  esac

  echo "Installing $apk on $device"
  if ! $adb -s "$device" install -r "$apk"; then
    # A copy signed with another key is in the way: remove it and try once more.
    $adb -s "$device" uninstall $app > /dev/null
    $adb -s "$device" install "$apk" || exit 1
  fi
  $adb -s "$device" shell pm grant $app android.permission.RECORD_AUDIO
  # "localhost:8000" on the phone now means port 8000 of this computer.
  $adb -s "$device" reverse tcp:8000 tcp:8000 > /dev/null
  $adb -s "$device" shell am force-stop $app
  $adb -s "$device" shell monkey -p $app -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
  echo "Explainly is open on $device"
done

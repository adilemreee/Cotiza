#!/usr/bin/env bash
# Captures raw App Store screenshots: every scene, in English, Spanish and Turkish, on each simulator.
# LANGS="tr" Tools/screenshots.sh … captures only the languages given.
# Then compose them with AppStoreScreenshotKit: AppStore/screenshot-kit/link_raw.sh, then
#   python3 ~/Developer/AppStoreScreenshotKit/compose.py AppStore/screenshot-kit/config.py
#
# Usage: Tools/screenshots.sh [device-name ...]
# Default devices: "Cotiza Shots iPhone 18 Pro" (6.3"), "Cotiza Shots iPad Pro 13" (13") and the iPhone Duo
# on iOS 27.2 (by UDID: this Mac has two simulators named "iPhone Duo").
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICES=("$@")
[ ${#DEVICES[@]} -eq 0 ] && DEVICES=("Cotiza Shots iPhone 18 Pro" "Cotiza Shots iPad Pro 13" "98130553-3EDF-462C-884C-88176F3FBF9C")
SCENES=(capture editor pdf signature home report paywall)
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Cotiza.app
OUT=AppStore/screenshots/raw

xcodebuild -project Cotiza.xcodeproj -scheme Cotiza -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData build -quiet

LANGS=(${LANGS:-en es tr})
locale_of() { case "$1" in tr) echo tr_TR ;; *) echo "${1}_US" ;; esac; }

transcript() {
  if [ "$1" = tr ]; then
    echo "Üç yatak odası boyama tanesi 4.500 lira, duvar ve tavan. Alçı ve zımpara 4 saat, saati 450. 6 kutu premium boya tanesi 1.450, bant, naylon ve rulo toplam 650. Müşteri Ayşe Demir."
  elif [ "$1" = es ]; then
    echo "Pintar tres recámaras a 450 cada una, paredes y techo. Resanar y lijar 4 horas a 45 la hora. 6 galones de pintura premium a 52.89 y cinta, plástico y rodillos por 38.50. Cliente María López."
  else
    echo "Paint three bedrooms at 450 each, walls and ceiling. Patch and sand 4 hours at 45 an hour. 6 gallons of premium paint at 52.89 and tape, plastic and rollers for 38.50. Client Maria Lopez."
  fi
}

capture() {
  local udid=$1 name=$2 file=$3
  if [[ "$name" == *Duo* ]]; then
    # Two screens: the large inner one (display 3) when unfolded, the cover one (display 1) when folded.
    # A simulator booted from the command line starts folded; unfold it in Device Hub for inner shots.
    xcrun simctl io "$udid" screenshot --display=3 "$file" >/dev/null 2>&1
    if python3 -c "import sys; from PIL import Image; sys.exit(0 if Image.open('$file').convert('L').getextrema()[1] < 8 else 1)"; then
      xcrun simctl io "$udid" screenshot --display=1 "$file" >/dev/null 2>&1
    fi
  else
    xcrun simctl io "$udid" screenshot "$file" >/dev/null 2>&1
  fi
}

udid_of() {
  if [[ "$1" =~ ^[0-9A-F-]{36}$ ]]; then echo "$1"
  else xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}'; fi
}

# One simulator at a time: several booted at once slow animations enough to spoil the captures.
# Simulators being captured are left as they are, so an unfolded iPhone Duo stays unfolded.
targets=" "
for name in "${DEVICES[@]}"; do targets+="$(udid_of "$name") "; done
for booted in $(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}'); do
  [[ "$targets" == *" $booted "* ]] || xcrun simctl shutdown "$booted"
done

for name in "${DEVICES[@]}"; do
  # A device can be given by name or by UDID (two simulators can share a name).
  if [[ "$name" =~ ^[0-9A-F-]{36}$ ]]; then
    udid=$name
    name=$(xcrun simctl list devices | grep -F "$udid" | sed -E 's/^ *(.*) \([0-9A-F-]{36}\).*/\1/')
  else
    udid=$(xcrun simctl list devices available | grep -F "$name (" | head -1 | grep -oE '[0-9A-F-]{36}')
  fi
  [ -z "$udid" ] && { echo "No simulator named $name"; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" >/dev/null
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install "$udid" "$APP"
  # The first launch after an install can come up without its launch arguments; take it out of the way.
  xcrun simctl launch "$udid" com.cotiza.app -CotizaResetState YES -CotizaDemoData YES >/dev/null
  sleep 8
  xcrun simctl terminate "$udid" com.cotiza.app 2>/dev/null || true
  slug=$(echo "$name" | sed 's/Cotiza Shots //; s/ /-/g')
  if [[ "$name" == *Duo* ]]; then
    # Unfolded and folded shots go to separate folders: the two screens have different sizes.
    probe="$(mktemp -d)/probe.png"
    xcrun simctl io "$udid" screenshot --display=3 "$probe" >/dev/null 2>&1
    if python3 -c "import sys; from PIL import Image; sys.exit(0 if Image.open('$probe').convert('L').getextrema()[1] < 8 else 1)"; then
      slug="$slug-Folded"
    fi
  fi
  for lang in "${LANGS[@]}"; do
    mkdir -p "$OUT/$slug/$lang"
    if [[ "$name" == *iPad* ]]; then
      # The iPad status bar shows the date in the system language, so switch it to the store language.
      xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$lang"
      xcrun simctl spawn "$udid" defaults write -g AppleLocale "$(locale_of "$lang")"
      xcrun simctl reboot "$udid" 2>/dev/null || { xcrun simctl shutdown "$udid"; xcrun simctl boot "$udid"; }
      xcrun simctl bootstatus "$udid" >/dev/null
      xcrun simctl status_bar "$udid" override --time "$(python3 -c 'import datetime as d; print(d.datetime(2026,11,12,9,41).astimezone(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')" --dataNetwork wifi --wifiMode active \
        --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
    fi
    for i in "${!SCENES[@]}"; do
      scene=${SCENES[$i]}
      args=(-CotizaResetState YES -CotizaDemoData YES -CotizaScreen "$scene" -AppleLanguages "($lang)" -AppleLocale "$(locale_of "$lang")")
      if [ "$scene" = paywall ]; then args+=(-CotizaMockPlans YES); else args+=(-CotizaForcePro YES); fi
      [ "$scene" = capture ] && args+=(-CotizaDemoTranscript "$(transcript $lang)")
      xcrun simctl terminate "$udid" com.cotiza.app 2>/dev/null || true
      xcrun simctl launch "$udid" com.cotiza.app "${args[@]}" >/dev/null
      file="$OUT/$slug/$lang/$((i + 1))-$scene.png"
      # Wait until the app is past the launch screen (slow right after a boot), then let the scene settle.
      for _ in $(seq 1 30); do
        sleep 1
        capture "$udid" "$name" "$file"
        python3 Tools/check_screenshots.py "$file" >/dev/null && break
      done
      case "$scene" in pdf|signature) sleep 6 ;; *) sleep 3 ;; esac
      capture "$udid" "$name" "$file"
      echo "$file"
    done
  done
  xcrun simctl terminate "$udid" com.cotiza.app 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear
  [[ "$name" == *Duo* ]] || xcrun simctl shutdown "$udid"
done

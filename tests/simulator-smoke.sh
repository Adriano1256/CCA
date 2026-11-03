#!/bin/bash
# Compila para o simulador (sem a biblioteca de IA, que não tem versão para simulador),
# abre o app, roda o teste real de exportação e fotografa as telas.
set -x
mkdir -p smoke
python3 - <<'PY'
import re
s = open('project.yml').read()
s = re.sub(r'packages:\n(?:  .*\n)+', '', s, count=1)
s = re.sub(r'    dependencies:\n(?:      .*\n)+', '', s, count=1)
s = s.replace('name: EditorIA\n', 'name: EditorIASim\n', 1)
open('project-sim.yml', 'w').write(s)
PY
xcodegen generate --spec project-sim.yml || exit 1
xcodebuild -project EditorIASim.xcodeproj -scheme EditorIA -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build-sim \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build > build-sim.log 2>&1
grep -E 'error:|BUILD (SUCCEEDED|FAILED)' build-sim.log | sort -u | tee smoke/sim-erros.txt
APP=build-sim/Build/Products/Debug-iphonesimulator/EditorIA.app
test -f "$APP/EditorIA" || exit 1

run_device() {
  NAME_MATCH=$1; TAG=$2; SMOKE=$3; shift 3
  DEVICE=$(xcrun simctl list devices available | grep -m1 -E "$NAME_MATCH" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  xcrun simctl boot "$DEVICE"
  xcrun simctl bootstatus "$DEVICE" -b > /dev/null
  xcrun simctl install "$DEVICE" "$APP"
  xcrun simctl privacy "$DEVICE" grant all com.criativar.editoria || true
  xcrun simctl status_bar "$DEVICE" override --time "9:41" || true

  # 1. Teste real: gera vídeos, monta, exporta e confere o arquivo.
  if [ "$SMOKE" = 1 ]; then
  SIMCTL_CHILD_EDITORIA_SMOKE=1 xcrun simctl launch --console-pty --terminate-running-process "$DEVICE" com.criativar.editoria > "smoke/$TAG-console.log" 2>&1 &
  CONSOLE=$!
  for i in $(seq 1 270); do
    DATA=$(xcrun simctl get_app_container "$DEVICE" com.criativar.editoria data)
    test -f "$DATA/Documents/Smoke/report.json" && break
    sleep 5
  done
  kill $CONSOLE 2>/dev/null
  cp -R "$DATA/Documents/Smoke/" "smoke/$TAG/" 2>/dev/null
  xcrun simctl terminate "$DEVICE" com.criativar.editoria
  fi

  # 2. Fotos de cada tela, já com o projeto de teste aberto.
  for PANEL in "" "Chat" "Montagem" "Clipe" "Mídia" "Legendas" "Áudio" "Cor" "Perfis"; do
    FILE=$(echo "${PANEL:-principal}" | tr -d ' ' | iconv -f utf8 -t ascii//TRANSLIT | tr -d "'\`^~")
    SIMCTL_CHILD_EDITORIA_OPEN="$PANEL" xcrun simctl launch --terminate-running-process "$DEVICE" com.criativar.editoria
    sleep 7
    xcrun simctl io "$DEVICE" screenshot "smoke/$TAG-$FILE.png"
    xcrun simctl spawn "$DEVICE" launchctl list | grep -q com.criativar.editoria || echo "$PANEL: app fechou sozinho" >> smoke/crashes.txt
  done
  xcrun simctl shutdown "$DEVICE"
}

run_device 'iPhone 1[0-9]' iphone 1
run_device 'iPad' ipad 0
ls -R smoke | head -60

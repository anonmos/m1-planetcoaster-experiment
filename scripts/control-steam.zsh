#!/bin/zsh
setopt NO_HUP

ROOT="${CHECKPOINT_ROOT:-${0:A:h:h}}"
R="${WINE_RUNTIME:-$ROOT/build/wineforge-runtime}"
WINE_EXEC="${WINE_EXEC:-$R/bin/wine}"
WINE_SERVER="${WINE_SERVER:-$R/bin/wineserver}"
P="${WINEPREFIX:-/Users/tim/Library/Containers/com.franke.Whisky/Bottles/66589F31-3F31-4D59-AC97-90EE21022A1D}"
STEAM_DIR="$P/drive_c/Program Files (x86)/Steam"
STEAM="$STEAM_DIR/steam.exe"
PC2_GAME="$STEAM_DIR/steamapps/common/Planet Coaster 2/PlanetCoaster2.exe"
EXP33_DIR="$STEAM_DIR/steamapps/common/Expedition 33"
EXP33_LAUNCHER="$EXP33_DIR/Expedition33_Steam.exe"
EXP33_GAME="$STEAM_DIR/steamapps/common/Expedition 33/Sandfall/Binaries/Win64/SandFall-Win64-Shipping.exe"
ER_DIR="$STEAM_DIR/steamapps/common/ELDEN RING/Game"
ER_GAME="$ER_DIR/eldenring.exe"
GPTK="${GPTK_WINE:-$ROOT/toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine}"
STEAM_LOG='/private/tmp/planetcoaster2-controller-steam.log'
PC2_LOG='/private/tmp/planetcoaster2-controller-pc2.log'
EXP33_LOG='/private/tmp/planetcoaster2-controller-33.log'
ER_LOG='/private/tmp/planetcoaster2-controller-er.log'
STEAM_PIDFILE='/private/tmp/planetcoaster2-controller-steam.pid'
PC2_PIDFILE='/private/tmp/planetcoaster2-controller-pc2.pid'
EXP33_PIDFILE='/private/tmp/planetcoaster2-controller-33.pid'
ER_PIDFILE='/private/tmp/planetcoaster2-controller-er.pid'

usage() {
  print 'Usage: control-steam.zsh <start|stop> <steam|game|all> [pc2|33|er]'
  print ''
  print 'Commands:'
  print '  start steam   Start Steam only'
  print '  start game pc2  Start Planet Coaster 2; Steam must already be running'
  print '  start game 33   Start Expedition 33; Steam must already be running'
  print '  start game er   Start Elden Ring (offline EAC bypass); Steam must already be running'
  print '  stop steam    Stop Steam and its Wine-side helper processes'
  print '  stop game pc2   Stop Planet Coaster 2 only'
  print '  stop game 33    Stop Expedition 33 only'
  print '  stop game er    Stop Elden Ring only'
  print '  start all     Start Steam, wait for login, then start the game'
  print '  stop all      Stop the game, Steam, and their Wine-side helpers'
  exit 2
}

if [[ $# -lt 2 || $# -gt 3 || ( "$1" != start && "$1" != stop ) || ( "$2" != steam && "$2" != game && "$2" != all ) || ( $# -eq 3 && "$3" != pc2 && "$3" != 33 && "$3" != er ) || ( "$2" != game && $# -eq 3 ) ]]; then
  usage
fi
if [[ ! -x "$WINE_EXEC" || ! -x "$WINE_SERVER" || ! -f "$STEAM" || ! -f "$PC2_GAME" || ! -f "$EXP33_GAME" || ! -f "$ER_GAME" ]]; then
  print -u2 'WineForge, Steam, Planet Coaster 2, Expedition 33, or Elden Ring is missing from the expected paths.'
  exit 1
fi

GAME_TARGET="${3:-pc2}"
if [[ "$GAME_TARGET" == pc2 ]]; then
  GAME="$PC2_GAME"
  APPID='2688950'
  GAME_LABEL='Planet Coaster 2'
  GAME_LOG="$PC2_LOG"
  GAME_PIDFILE="$PC2_PIDFILE"
  GAME_EXE='PlanetCoaster2.exe'
elif [[ "$GAME_TARGET" == er ]]; then
  GAME="$ER_GAME"
  APPID='1245620'
  GAME_LABEL='Elden Ring'
  GAME_LOG="$ER_LOG"
  GAME_PIDFILE="$ER_PIDFILE"
  GAME_EXE='eldenring.exe'
  # Elden Ring resolves its Data*.bhd archives relative to the working
  # directory: launching from $STEAM_DIR makes it look in
  # "C:\Program Files (x86)\Steam\Data0.bhd" and die in CSEblFileManager.
  GAME_DIR="$ER_DIR"
else
  GAME="$EXP33_GAME"
  APPID='1903340'
  GAME_LABEL='Expedition 33'
  GAME_LOG="$EXP33_LOG"
  GAME_PIDFILE="$EXP33_PIDFILE"
  GAME_EXE='SandFall-Win64-Shipping.exe'
  GAME_LAUNCHER="$EXP33_LAUNCHER"
fi

# GPU identity presented to games through D3DMetal. NVIDIA spoof for all
# targets: it is the configuration the working games were validated with,
# and Elden Ring boots furthest with it (the AMD identity was tried for its
# AGS library but changed nothing; the real blockers were the missing
# D3DMetal redirect tree and the working directory). All four remain
# env-overridable per launch, e.g.:
#   D3DM_UPSCALER_PROFILE=amd D3DM_VENDOR_ID=4098 D3DM_DEVICE_ID=29631 \
#   D3DM_DEVICE_DESCRIPTION='AMD Radeon RX 6800 XT' zsh scripts/control-steam.zsh start game er
: ${D3DM_UPSCALER_PROFILE:=nvidia}
: ${D3DM_VENDOR_ID:=4318}
: ${D3DM_DEVICE_ID:=10370}
: ${D3DM_DEVICE_DESCRIPTION:='NVIDIA GeForce RTX 4080'}

run_wine() {
  local steam_app_id="${STEAM_APP_ID:-$APPID}"
  local steam_client_launch="${STEAM_CLIENT_LAUNCH:-1}"
  arch -x86_64 env \
    PATH="$R/bin:$PATH" \
    WINEPREFIX="$P" WINEARCH=win64 \
    WINESERVER="$WINE_SERVER" \
    WINELOADER="$WINE_EXEC" \
    WINEDLLPATH="$R/lib/wine" \
    DYLD_LIBRARY_PATH="$GPTK/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
    DYLD_FALLBACK_LIBRARY_PATH="$GPTK/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
    WINE_FREETYPE_PATH="$R/lib/libfreetype.6.dylib" \
    WINE_FONTCONFIG_PATH="$R/lib/libfontconfig.1.dylib" \
    FONTCONFIG_FILE='/opt/homebrew/etc/fonts/fonts.conf' \
    FONTCONFIG_PATH='/opt/homebrew/etc/fonts' \
    D3DMETAL_FRAMEWORK_PATH="$R/lib/external/D3DMetal.framework/D3DMetal" \
    D3DMETAL_RUNTIME_DIR="$R/lib/external" \
    D3DM_ENABLE_METALFX=1 \
    D3DM_ERROR_MODE=1 \
    GRAPHICS_BACKEND=d3dmetal \
    D3DMETAL_UPSCALER_PROFILE="$D3DM_UPSCALER_PROFILE" \
    D3DM_VENDOR_ID="$D3DM_VENDOR_ID" \
    D3DM_DEVICE_ID="$D3DM_DEVICE_ID" \
    D3DM_DEVICE_DESCRIPTION="$D3DM_DEVICE_DESCRIPTION" \
    WINEESYNC=0 WINEMSYNC=0 WINEFSYNC=0 \
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    STEAM_RUNTIME=0 \
    SteamAppId="$steam_app_id" SteamGameId="$steam_app_id" SteamOverlayGameId="$steam_app_id" \
    SteamClientLaunch="$steam_client_launch" SteamPath="$STEAM_DIR" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_DIR" \
    WINEDLLOVERRIDES='dxgi,d3d10,d3d10core,d3d11,d3d12=b;nvapi,nvapi64,nvngx,nvngx-on-metalfx=b;gameoverlayrenderer,gameoverlayrenderer64,winebth=d' \
    WINEDEBUG="${WINE_DEBUG_MODE:-+loaddll,+err}" \
    "$WINE_EXEC" "$@"
}

find_pids() {
  local scope="$1"
  ps -axo pid=,args= 2>/dev/null | while read -r pid args; do
    [[ -z "$pid" || "$pid" == $$ ]] && continue
    # Wine-translated children (spawned via CreateProcess) show C:\ argv paths
    # with no trace of the macOS bottle path, so match those too. The C:\
    # markers are Wine-only and never match native macOS processes.
    local ours=0
    if [[ "$args" == *"$P"* || "$args" == *'C:\Program Files (x86)\'* || "$args" == *'C:\windows\system32\'* ]]; then
      ours=1
    fi
    (( ours )) || continue
    if [[ "$scope" == game ]]; then
      [[ "$args" == *"$GAME_EXE"* || ( "$GAME_TARGET" == 33 && "$args" == *'Expedition33_Steam.exe'* ) ]] && print "$pid"
    elif [[ "$scope" == steam ]]; then
      [[ "$args" == *('steam.exe'|'steamwebhelper'|'steamservice'|'steamerrorreporter')* ]] && print "$pid"
    else
      [[ "$args" == *('steam.exe'|'steamwebhelper'|'steamservice'|'steamerrorreporter'|'PlanetCoaster2.exe'|'eldenring.exe'|'start_protected_game.exe'|'conhost.exe'|'winedevice.exe'|'services.exe'|'plugplay.exe'|'svchost.exe'|'explorer.exe'|'rpcss.exe'|'winedbg'|'wineserver'|'wine-preloader'|'wine64-preloader')* ]] && print "$pid"
    fi
  done
}

stop_scope() {
  local scope="$1"
  local pids=(${(f)"$(find_pids "$scope")"})
  if (( ${#pids} == 0 )); then
    print "No $scope processes found."
    return 0
  fi
  print "Stopping $scope process IDs: ${pids[*]}"
  kill -TERM $pids 2>/dev/null || true
  sleep 3
  local remaining=(${(f)"$(find_pids "$scope")"})
  if (( ${#remaining} )); then
    print "Force-stopping remaining $scope process IDs: ${remaining[*]}"
    kill -KILL $remaining 2>/dev/null || true
  fi
  [[ "$scope" == steam ]] && rm -f "$STEAM_PIDFILE"
  [[ "$scope" == game ]] && rm -f "$GAME_PIDFILE"
}

stop_prefix_server() {
  print 'Terminating every Wine process in this experiment prefix...'
  STEAM_APP_ID=0 STEAM_CLIENT_LAUNCH=0 run_wine wineserver -k >/dev/null 2>&1 || true
  sleep 3
}

start_steam() {
  if (( ${#$(find_pids steam)} )); then
    print 'Steam is already running for this bottle.'
    return 0
  fi
  : > "$STEAM_LOG"
  cd "$STEAM_DIR"
  print 'Starting Steam...'
  ( STEAM_APP_ID=0 STEAM_CLIENT_LAUNCH=0 run_wine "$STEAM" -tcp -no-cef-sandbox -cef-disable-gpu -cef-disable-gpu-compositing >>"$STEAM_LOG" 2>&1 ) &
  print $! > "$STEAM_PIDFILE"
  print "Steam started. Log: $STEAM_LOG"
}

wait_for_steam() {
  local log="$STEAM_DIR/logs/connection_log.txt"
  print 'Waiting up to 180 seconds for Steam to report Logged On...'
  integer attempt
  for attempt in {1..90}; do
    if [[ -f "$log" ]] && tail -n 200 "$log" 2>/dev/null | grep -E '\[(Logged On|Logged Off),' | tail -n 1 | grep -q '\[Logged On,'; then
      print 'Steam is logged on.'
      return 0
    fi
    sleep 2
  done
  print -u2 'Steam did not report Logged On. The game was not started.'
  return 1
}

start_game() {
  if [[ "${FORCE_GAME:-0}" != 1 ]] && (( ${#$(find_pids game)} )); then
    print "$GAME_LABEL is already running for this bottle."
    return 0
  fi
  if (( ! ${#$(find_pids steam)} )); then
    print -u2 'Steam is not running for this bottle. Use start steam first.'
    return 1
  fi
  if ! wait_for_steam; then
    print -u2 "$GAME_LABEL was not started because Steam is not logged on."
    return 1
  fi
  : > "$GAME_LOG"
  cd "${GAME_DIR:-$STEAM_DIR}"
  print "Requesting $GAME_LABEL from the existing Steam client..."
  print "AppID: $APPID"
  if [[ "$GAME_TARGET" == 33 ]]; then
    print 'Launching the Expedition 33 Steam bootstrapper directly with Steam API environment...'
    ( STEAM_APP_ID="$APPID" STEAM_CLIENT_LAUNCH=0 run_wine "$GAME_LAUNCHER" -dx12 -nographicsdrivercheck -windowed -ResX=1280 -ResY=720 >>"$GAME_LOG" 2>&1 ) &
  elif [[ "$GAME_TARGET" == er ]]; then
    print 'Launching eldenring.exe directly (EAC bypass, offline only) with Steam API environment...'
    print 'EasyAntiCheat via start_protected_game.exe does not load under Wine; online play is unavailable.'
    ( STEAM_APP_ID="$APPID" STEAM_CLIENT_LAUNCH=0 run_wine "$GAME" >>"$GAME_LOG" 2>&1 ) &
  else
    ( STEAM_APP_ID=0 STEAM_CLIENT_LAUNCH=0 run_wine "$STEAM" -applaunch "$APPID" -dx12 -windowed -screen-width 1280 -screen-height 720 >>"$GAME_LOG" 2>&1 ) &
  fi
  print $! > "$GAME_PIDFILE"
  print "$GAME_LABEL started. Log: $GAME_LOG"
}

case "$1 $2" in
  'start steam') start_steam ;;
  'start game') start_game ;;
  'stop steam') stop_scope steam ;;
  'stop game') stop_scope game ;;
  'start all') start_steam && wait_for_steam && start_game ;;
  'stop all') stop_scope game; stop_scope steam; stop_scope all; stop_prefix_server; rm -f "$GAME_PIDFILE" "$STEAM_PIDFILE" ;;
esac

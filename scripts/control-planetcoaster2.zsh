#!/bin/zsh
setopt NO_HUP

ROOT="${CHECKPOINT_ROOT:-${0:A:h:h}}"
R="${WINE_RUNTIME:-$ROOT/build/wineforge-runtime}"
WINE_EXEC="${WINE_EXEC:-$R/bin/wine}"
WINE_SERVER="${WINE_SERVER:-$R/bin/wineserver}"
P="${WINEPREFIX:-/Users/tim/Library/Containers/com.franke.Whisky/Bottles/66589F31-3F31-4D59-AC97-90EE21022A1D}"
STEAM_DIR="$P/drive_c/Program Files (x86)/Steam"
STEAM="$STEAM_DIR/steam.exe"
GAME="$STEAM_DIR/steamapps/common/Planet Coaster 2/PlanetCoaster2.exe"
APPID='2688950'
GPTK="${GPTK_WINE:-$ROOT/toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine}"
STEAM_LOG='/private/tmp/planetcoaster2-controller-steam.log'
GAME_LOG='/private/tmp/planetcoaster2-controller-game.log'
STEAM_PIDFILE='/private/tmp/planetcoaster2-controller-steam.pid'
GAME_PIDFILE='/private/tmp/planetcoaster2-controller-game.pid'

usage() {
  print 'Usage: control-wineforge-planetcoaster2.zsh <start|stop> <steam|game|all>'
  print ''
  print 'Commands:'
  print '  start steam   Start Steam only'
  print '  start game    Start Planet Coaster 2 only; Steam must already be running'
  print '  stop steam    Stop Steam and its Wine-side helper processes'
  print '  stop game     Stop Planet Coaster 2 only'
  print '  start all     Start Steam, wait for login, then start the game'
  print '  stop all      Stop the game, Steam, and their Wine-side helpers'
  exit 2
}

if [[ $# -ne 2 || ( "$1" != start && "$1" != stop ) || ( "$2" != steam && "$2" != game && "$2" != all ) ]]; then
  usage
fi
if [[ ! -x "$WINE_EXEC" || ! -x "$WINE_SERVER" || ! -f "$STEAM" || ! -f "$GAME" ]]; then
  print -u2 'WineForge, Steam, or Planet Coaster 2 is missing from the expected paths.'
  exit 1
fi

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
    D3DMETAL_UPSCALER_PROFILE=nvidia \
    D3DM_VENDOR_ID=4318 \
    D3DM_DEVICE_ID=10370 \
    D3DM_DEVICE_DESCRIPTION='NVIDIA GeForce RTX 4080' \
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
    if [[ "$scope" == game ]]; then
      [[ "$args" == *'PlanetCoaster2.exe'* && "$args" == *"$P"* ]] && print "$pid"
    elif [[ "$scope" == steam ]]; then
      [[ "$args" == *"$P"* && "$args" == *('steam.exe'|'steamwebhelper'|'steamservice'|'steamerrorreporter')* ]] && print "$pid"
    else
      [[ "$args" == *"$P"* && "$args" == *('steam.exe'|'steamwebhelper'|'steamservice'|'steamerrorreporter'|'PlanetCoaster2.exe'|'conhost.exe'|'winedevice.exe'|'winedbg'|'wineserver'|'wine-preloader'|'wine64-preloader')* ]] && print "$pid"
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
  local start_lines=0
  [[ -f "$log" ]] && start_lines=$(wc -l < "$log")
  print 'Waiting up to 180 seconds for Steam to report Logged On...'
  integer attempt
  for attempt in {1..90}; do
    if [[ -f "$log" ]] && tail -n +$((start_lines + 1)) "$log" 2>/dev/null | grep -q '\[Logged On,'; then
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
    print 'Planet Coaster 2 is already running for this bottle.'
    return 0
  fi
  if (( ! ${#$(find_pids steam)} )); then
    print -u2 'Steam is not running for this bottle. Use start steam or start all first.'
    return 1
  fi
  : > "$GAME_LOG"
  cd "$STEAM_DIR"
  print 'Requesting Planet Coaster 2 from the existing Steam client...'
  print "AppID: $APPID"
  ( STEAM_APP_ID=0 STEAM_CLIENT_LAUNCH=0 run_wine "$STEAM" -applaunch "$APPID" -dx12 -windowed -screen-width 1280 -screen-height 720 >>"$GAME_LOG" 2>&1 ) &
  print $! > "$GAME_PIDFILE"
  print "Planet Coaster 2 started. Log: $GAME_LOG"
}

case "$1 $2" in
  'start steam') start_steam ;;
  'start game') start_game ;;
  'stop steam') stop_scope steam ;;
  'stop game') stop_scope game ;;
  'start all') start_steam && wait_for_steam && start_game ;;
  'stop all') stop_scope game; stop_scope steam; stop_prefix_server; rm -f "$GAME_PIDFILE" "$STEAM_PIDFILE" ;;
esac

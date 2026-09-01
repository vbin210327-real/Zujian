#!/bin/zsh

set -euo pipefail

usage() {
    /bin/echo "用法："
    /bin/echo "  $0 <录制.json> [输出.mp4] [30|60] [h264|hevc] [Watch 模拟器 UDID]"
    /bin/echo
    /bin/echo "未填 UDID 时使用当前已启动的 Watch 模拟器。"
}

fail() {
    /bin/echo "错误：$1" >&2
    exit 1
}

wait_for_file() {
    local file_path="$1"
    local timeout_seconds="$2"
    local label="$3"
    local began_at=$SECONDS
    while [[ ! -e "$file_path" ]]; do
        if (( SECONDS - began_at >= timeout_seconds )); then
            fail "等待${label}超时。"
        fi
        /bin/sleep 0.1
    done
}

wait_for_text() {
    local file_path="$1"
    local expected_text="$2"
    local timeout_seconds="$3"
    local began_at=$SECONDS
    while ! /usr/bin/grep -q "$expected_text" "$file_path" 2>/dev/null; do
        if (( SECONDS - began_at >= timeout_seconds )); then
            fail "模拟器视频录制未能启动。"
        fi
        /bin/sleep 0.1
    done
}

[[ $# -ge 1 ]] || {
    usage
    exit 2
}

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIRECTORY:h}"
INPUT_JSON="${1:A}"
FPS="${3:-60}"
CODEC="${4:-h264}"
DEVICE_ID="${5:-}"

[[ -f "$INPUT_JSON" ]] || fail "找不到录制文件：$INPUT_JSON"
[[ "$FPS" == "30" || "$FPS" == "60" ]] || fail "帧率只能是 30 或 60。"
[[ "$CODEC" == "h264" || "$CODEC" == "hevc" ]] || fail "编码只能是 h264 或 hevc。"

if [[ $# -ge 2 && -n "$2" ]]; then
    OUTPUT_MP4="${2:A}"
else
    INPUT_STEM="${INPUT_JSON:r}"
    OUTPUT_MP4="${INPUT_STEM}-native-$(/bin/date +%Y%m%d-%H%M%S).mp4"
fi
[[ ! -e "$OUTPUT_MP4" ]] || fail "输出文件已存在，请换一个文件名：$OUTPUT_MP4"

if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID="$(
        /usr/bin/xcrun simctl list devices available \
            | /usr/bin/awk '
                /^-- watchOS / { in_watch=1; next }
                /^-- / { in_watch=0 }
                in_watch && /\(Booted\)/ { print; exit }
            ' \
            | /usr/bin/sed -E 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/'
    )"
fi
[[ -n "$DEVICE_ID" ]] || fail "请先在 Xcode 启动一台与真表尺寸一致的 Watch 模拟器。"

TEMP_DIRECTORY="$(/usr/bin/mktemp -d /private/tmp/zujian-native-replay.XXXXXX)"
VIDEO_PROCESS_ID=""
RAW_VIDEO="$TEMP_DIRECTORY/raw-watch-capture.mov"
CONFORMER_SOURCE="$PROJECT_ROOT/Tools/NativeVideoConformer.swift"
CONFORMER_DIRECTORY="$PROJECT_ROOT/DerivedData/NativeReplayTools"
CONFORMER_BINARY="$CONFORMER_DIRECTORY/native-video-conformer"

cleanup() {
    if [[ -n "$VIDEO_PROCESS_ID" ]] && /bin/kill -0 "$VIDEO_PROCESS_ID" 2>/dev/null; then
        /bin/kill -INT "$VIDEO_PROCESS_ID" 2>/dev/null || true
        wait "$VIDEO_PROCESS_ID" 2>/dev/null || true
    fi
    /bin/rm -f \
        "$TEMP_DIRECTORY/watch-size.png" \
        "$TEMP_DIRECTORY/record-video.log" \
        "$RAW_VIDEO"
    /bin/rmdir "$TEMP_DIRECTORY" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

/bin/echo "1/7 校验 Watch 模拟器尺寸…"
/usr/bin/xcrun simctl io "$DEVICE_ID" screenshot --mask=ignored "$TEMP_DIRECTORY/watch-size.png" >/dev/null
ACTUAL_WIDTH="$(/usr/bin/sips -g pixelWidth "$TEMP_DIRECTORY/watch-size.png" | /usr/bin/awk '/pixelWidth/ { print $2 }')"
ACTUAL_HEIGHT="$(/usr/bin/sips -g pixelHeight "$TEMP_DIRECTORY/watch-size.png" | /usr/bin/awk '/pixelHeight/ { print $2 }')"
LOGICAL_WIDTH="$(/usr/bin/plutil -extract device.logicalWidth raw -o - "$INPUT_JSON")"
LOGICAL_HEIGHT="$(/usr/bin/plutil -extract device.logicalHeight raw -o - "$INPUT_JSON")"
SCREEN_SCALE="$(/usr/bin/plutil -extract device.scale raw -o - "$INPUT_JSON")"
EXPECTED_WIDTH="$(/usr/bin/awk -v points="$LOGICAL_WIDTH" -v scale="$SCREEN_SCALE" 'BEGIN { value=int(points*scale+0.5); if (value%2) value++; print value }')"
EXPECTED_HEIGHT="$(/usr/bin/awk -v points="$LOGICAL_HEIGHT" -v scale="$SCREEN_SCALE" 'BEGIN { value=int(points*scale+0.5); if (value%2) value++; print value }')"

if [[ "$ACTUAL_WIDTH" != "$EXPECTED_WIDTH" || "$ACTUAL_HEIGHT" != "$EXPECTED_HEIGHT" ]]; then
    fail "录制素材是 ${EXPECTED_WIDTH}×${EXPECTED_HEIGHT}px，当前 Watch 模拟器是 ${ACTUAL_WIDTH}×${ACTUAL_HEIGHT}px。请启动与录制真表同尺寸的模拟器。"
fi

/bin/echo "2/7 编译 Debug Watch App…"
/usr/bin/xcodebuild \
    -project "$PROJECT_ROOT/Zujian.xcodeproj" \
    -scheme Zujian \
    -configuration Debug \
    -sdk watchsimulator \
    -destination "platform=watchOS Simulator,id=$DEVICE_ID" \
    -derivedDataPath "$PROJECT_ROOT/DerivedData/NativeReplayBuild" \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

WATCH_APP="$PROJECT_ROOT/DerivedData/NativeReplayBuild/Build/Products/Debug-watchsimulator/Zujian.app"
[[ -d "$WATCH_APP" ]] || fail "编译成功但找不到 Zujian.app。"

/bin/echo "3/7 安装原生回放宿主…"
/usr/bin/xcrun simctl install "$DEVICE_ID" "$WATCH_APP"
DATA_CONTAINER="$(/usr/bin/xcrun simctl get_app_container "$DEVICE_ID" com.linfanbin.zujian.watchapp data)"
DOCUMENTS_DIRECTORY="$DATA_CONTAINER/Documents"
/bin/mkdir -p "$DOCUMENTS_DIRECTORY"

REPLAY_JSON="$DOCUMENTS_DIRECTORY/ZujianNativeReplay.json"
READY_MARKER="$DOCUMENTS_DIRECTORY/ZujianNativeReplay.ready"
START_MARKER="$DOCUMENTS_DIRECTORY/ZujianNativeReplay.start"
FINISHED_MARKER="$DOCUMENTS_DIRECTORY/ZujianNativeReplay.finished"
ERROR_MARKER="$DOCUMENTS_DIRECTORY/ZujianNativeReplay.error.txt"
/bin/rm -f "$READY_MARKER" "$START_MARKER" "$FINISHED_MARKER" "$ERROR_MARKER"
/bin/cp "$INPUT_JSON" "$REPLAY_JSON"

/bin/echo "4/7 用原 ReadyView / WorkoutView / FinishedView 加载时间轴…"
/usr/bin/xcrun simctl launch \
    --terminate-running-process \
    "$DEVICE_ID" \
    com.linfanbin.zujian.watchapp \
    --native-replay ZujianNativeReplay.json \
    --native-replay-fps "$FPS" >/dev/null
wait_for_file "$READY_MARKER" 30 "Watch 原生 UI 就绪"
if [[ -f "$ERROR_MARKER" ]]; then
    fail "$(<"$ERROR_MARKER")"
fi

/bin/echo "5/7 录制纯 App 画面…"
/usr/bin/xcrun simctl io "$DEVICE_ID" recordVideo \
    --codec=h264 \
    --mask=black \
    "$RAW_VIDEO" >"$TEMP_DIRECTORY/record-video.log" 2>&1 &
VIDEO_PROCESS_ID=$!
wait_for_text "$TEMP_DIRECTORY/record-video.log" "Recording started" 30
/usr/bin/touch "$START_MARKER"

DURATION="$(/usr/bin/plutil -extract duration raw -o - "$INPUT_JSON")"
TIMEOUT_SECONDS="$(/usr/bin/awk -v duration="$DURATION" 'BEGIN { print int(duration+30.999) }')"
wait_for_file "$FINISHED_MARKER" "$TIMEOUT_SECONDS" "时间轴回放完成"
/bin/sleep 0.25
/bin/kill -INT "$VIDEO_PROCESS_ID"
wait "$VIDEO_PROCESS_ID"
VIDEO_PROCESS_ID=""

[[ -s "$RAW_VIDEO" ]] || fail "模拟器原始视频没有生成。"

/bin/echo "6/7 生成固定 ${FPS} fps 的 ${CODEC} MP4…"
/bin/mkdir -p "$CONFORMER_DIRECTORY"
if [[ ! -x "$CONFORMER_BINARY" || "$CONFORMER_SOURCE" -nt "$CONFORMER_BINARY" ]]; then
    /usr/bin/xcrun swiftc \
        -parse-as-library \
        -O \
        "$CONFORMER_SOURCE" \
        -o "$CONFORMER_BINARY" \
        -framework AVFoundation \
        -framework CoreVideo \
        -framework CoreGraphics
fi
"$CONFORMER_BINARY" \
    "$RAW_VIDEO" \
    "$OUTPUT_MP4" \
    "$FPS" \
    "$CODEC" \
    "$DURATION" \
    0.05

[[ -s "$OUTPUT_MP4" ]] || fail "视频文件没有生成。"
/bin/echo "7/7 完成：$OUTPUT_MP4"

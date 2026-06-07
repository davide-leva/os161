#!/usr/bin/env bash
set -e

interactive=false
wait_gdb=false
project_home="$HOME/os161"
src_dir="$project_home/src"
root_dir="$project_home/root"
tools_dir="$project_home/tools"
libcompat_dir="$project_home/.os161-libcompat"
xterm_font="JetBrainsMono Nerd Font Mono"
xterm_font_size=12

export PATH="$tools_dir/bin:$PATH"

while getopts "iw" opt; do
	case $opt in
		i) interactive=true ;;
		w) wait_gdb=true ;;
	esac
done

shift $((OPTIND - 1))

log() {
	clear

	printf "\n%s" "$1"

	if [ "$interactive" = true ]; then
		for _ in 1 2 3 4 5; do
			sleep 0.06
			printf "."
		done
	fi

	printf "\n\n"
}

launch_xterm() {
	local title="$1"
	local command="$2"

	xterm \
		-class "$title" \
		-name "$title" \
		-title "$title" \
		-xrm "*renderFont: true" \
		-xrm "*faceName: $xterm_font" \
		-xrm "*faceSize: $xterm_font_size" \
		-xrm "*utf8: 2" \
		-fa "$xterm_font" \
		-fs "$xterm_font_size" \
		-bg "#1e1e2e" \
		-fg "#cdd6f4" \
		-geometry 140x40 \
		-e "bash -c '$command'" &

	LAST_XTERM_PID=$!

	float_niri_window "$title"
}

float_niri_window() {
	local title="$1"
	local window_id=""

	if ! command -v niri >/dev/null 2>&1 || [ -z "${NIRI_SOCKET:-}" ]; then
		return
	fi

	for _ in 1 2 3 4 5 6 7 8 9 10; do
		sleep 0.15

		if command -v jq >/dev/null 2>&1; then
			window_id=$(
				niri msg -j windows 2>/dev/null |
					jq -r --arg title "$title" '.[] | select(.title == $title or .app_id == $title) | .id' |
					tail -n 1
			)
		else
			window_id=$(
				niri msg windows 2>/dev/null |
					awk -v title="$title" '
						/^Window ID / {
							id = $3
							sub(":", "", id)
							matched = 0
						}
						index($0, title) {
							matched = 1
						}
						matched && id != "" {
							found = id
						}
						END {
							if (found != "") {
								print found
							}
						}
					'
			)
		fi

		if [ -n "$window_id" ] && [ "$window_id" != "null" ]; then
			niri msg action move-window-to-floating --id "$window_id" >/dev/null 2>&1 || true
			return
		fi
	done
}

prepare_toolchain_libs() {
	local cc1="$tools_dir/libexec/gcc/mips-harvard-os161/4.8.3/cc1"

	if [ ! -x "$cc1" ] || ! command -v ldd >/dev/null 2>&1; then
		return
	fi

	if ldd "$cc1" 2>/dev/null | grep -q "libmpfr.so.4 => not found"; then
		mkdir -p "$libcompat_dir"

		if [ -e /usr/lib/libmpfr.so.4 ]; then
			ln -sf /usr/lib/libmpfr.so.4 "$libcompat_dir/libmpfr.so.4"
		elif [ -e /usr/lib/libmpfr.so.6 ]; then
			ln -sf /usr/lib/libmpfr.so.6 "$libcompat_dir/libmpfr.so.4"
		fi

		export LD_LIBRARY_PATH="$libcompat_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	fi
}

prepare_toolchain_libs

if [ $# -ne 1 ]; then
	log "Using default configuration DUMBVM"
	conf="DUMBVM"
else
	conf="$1"
fi

log "Applying configuration"

cd "$src_dir/kern/conf"
./config "$conf"

log "Configuration applied"

log "Building kernel"

cd "$src_dir/kern/compile/$conf"

bmake depend
bmake
bmake install

log "Kernel build finished"

clear

echo ""
echo "Kernel booted"
echo ""

cd "$root_dir"

if [ "$wait_gdb" = true ]; then
	launch_xterm \
		"OS161-GDB" \
		"cd '$root_dir'; exec mips-harvard-os161-gdb -tui kernel"

	GDB_XTERM_PID=$LAST_XTERM_PID

	sleep 1

	launch_xterm \
		"OS161" \
		"cd '$root_dir'; exec sys161 -w kernel"

	SYS161_XTERM_PID=$LAST_XTERM_PID
else
	launch_xterm \
		"OS161" \
		"cd '$root_dir'; exec sys161 kernel"

	SYS161_XTERM_PID=$LAST_XTERM_PID
fi

wait "$SYS161_XTERM_PID"

echo ""
echo "Kernel stopped"
echo ""

kill "$SYS161_XTERM_PID" 2>/dev/null || true

if [ "$wait_gdb" = true ]; then
	kill "$GDB_XTERM_PID" 2>/dev/null || true
fi

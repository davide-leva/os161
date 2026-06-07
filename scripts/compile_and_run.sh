#!/usr/bin/env bash
set -e

interactive=false
debug=false
floating_windows=false
niri_workspace_changed=false
gdb_port=16161
project_home="$HOME/os161"
src_dir="$project_home/src"
root_dir="$project_home/root"
tools_dir="$project_home/tools"
libcompat_dir="$project_home/.os161-libcompat"
xterm_font="JetBrainsMono Nerd Font Mono"
xterm_font_size=16

export PATH="$tools_dir/bin:$PATH"

cleanup() {
	if ! declare -F return_to_previous_niri_workspace >/dev/null; then
		return
	fi

	return_to_previous_niri_workspace
}

trap cleanup EXIT

usage() {
	cat <<EOF
Usage: $0 [options] [CONFIG]

Build and run an OS/161 kernel.

CONFIG defaults to DUMBVM.

By default, when running under niri, the script moves to the workspace
below the current one before opening xterms. OS161 goes on the left;
GDB goes on the right. With no debugger, OS161 fills the whole workspace.
Use -f to keep xterms floating in the current workspace.
When the OS/161 window closes, the script asks niri to return to the
previous workspace.

Options:
  -i, --interactive   Show animated progress dots between build steps.
  -d, --debug         Start System/161 in GDB mode.
                      The script starts sys161 first with "-w -p $gdb_port",
                      so OS/161 waits before executing the kernel. It then
                      opens GDB and runs "target remote :$gdb_port" for you.
  -f, --floating      Keep the xterms floating in the current workspace.
  -w                  Legacy alias for --debug.
  -h, --help          Show this help.

Debug flow:
  1. Build and install the selected kernel.
  2. Open an OS161 xterm on the left running: sys161 -w -p $gdb_port kernel
  3. Open an OS161-GDB xterm on the right running: mips-harvard-os161-gdb -tui kernel
  4. GDB connects to System/161 with: target remote :$gdb_port

Once GDB is connected, use "continue" or "c" to let the kernel run.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-i|--interactive)
			interactive=true
			shift
			;;
		-d|--debug|-w)
			debug=true
			shift
			;;
		-f|--floating)
			floating_windows=true
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		--)
			shift
			break
			;;
		-*)
			printf "Unknown option: %s\n\n" "$1" >&2
			usage >&2
			exit 2
			;;
		*)
			break
			;;
	esac
done

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
	local bg="#111827"
	local fg="#d1fae5"
	local cursor="#34d399"
	local border="#059669"
	local geometry="132x36"

	case "$title" in
		OS161-GDB)
			bg="#10131f"
			fg="#f8fafc"
			cursor="#f59e0b"
			border="#2563eb"
			geometry="150x44"
			;;
		OS161)
			bg="#071411"
			fg="#d1fae5"
			cursor="#34d399"
			border="#059669"
			geometry="132x36"
			;;
	esac

	xterm \
		-class "$title" \
		-name "$title" \
		-title "$title" \
		-xrm "*renderFont: true" \
		-xrm "*faceName: $xterm_font" \
		-xrm "*faceSize: $xterm_font_size" \
		-xrm "*utf8: 2" \
		-xrm "*cursorBlink: true" \
		-xrm "*internalBorder: 10" \
		-xrm "*saveLines: 10000" \
		-xrm "*scrollBar: true" \
		-xrm "*rightScrollBar: true" \
		-xrm "*color0: #0b1220" \
		-xrm "*color1: #ef4444" \
		-xrm "*color2: #22c55e" \
		-xrm "*color3: #eab308" \
		-xrm "*color4: #3b82f6" \
		-xrm "*color5: #a855f7" \
		-xrm "*color6: #14b8a6" \
		-xrm "*color7: #e5e7eb" \
		-xrm "*color8: #475569" \
		-xrm "*color9: #f87171" \
		-xrm "*color10: #4ade80" \
		-xrm "*color11: #facc15" \
		-xrm "*color12: #60a5fa" \
		-xrm "*color13: #c084fc" \
		-xrm "*color14: #2dd4bf" \
		-xrm "*color15: #ffffff" \
		-fa "$xterm_font" \
		-fs "$xterm_font_size" \
		-bg "$bg" \
		-fg "$fg" \
		-cr "$cursor" \
		-bd "$border" \
		-b 10 \
		-sb \
		-rightbar \
		-geometry "$geometry" \
		-e bash -lc "$command" &

	LAST_XTERM_PID=$!

	place_niri_window "$title"
}

prepare_niri_workspace() {
	if [ "$floating_windows" = true ]; then
		return
	fi

	if ! command -v niri >/dev/null 2>&1 || [ -z "${NIRI_SOCKET:-}" ]; then
		return
	fi

	niri msg action focus-workspace-down >/dev/null 2>&1 ||
		niri msg action focus-workspace 999 >/dev/null 2>&1 ||
		return

	niri_workspace_changed=true
}

return_to_previous_niri_workspace() {
	if [ "$niri_workspace_changed" != true ]; then
		return
	fi

	if ! command -v niri >/dev/null 2>&1 || [ -z "${NIRI_SOCKET:-}" ]; then
		return
	fi

	niri msg action focus-workspace-previous >/dev/null 2>&1 || true
}

place_niri_window() {
	local title="$1"
	local window_id=""
	local column_index=1

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
			if [ "$floating_windows" = true ]; then
				niri msg action move-window-to-floating --id "$window_id" >/dev/null 2>&1 || true
				return
			fi

			niri msg action focus-window --id "$window_id" >/dev/null 2>&1 || true
			niri msg action move-window-to-tiling --id "$window_id" >/dev/null 2>&1 || true

			if [ "$debug" = false ] && [ "$title" = "OS161" ]; then
				niri msg action move-column-to-index 1 >/dev/null 2>&1 || true
				niri msg action set-column-width "100%" >/dev/null 2>&1 || true
				return
			fi

			if [ "$title" = "OS161-GDB" ]; then
				column_index=2
			fi

			niri msg action move-column-to-index "$column_index" >/dev/null 2>&1 || true
			niri msg action set-column-width "50%" >/dev/null 2>&1 || true
			return
		fi
	done
}

prepare_toolchain_libs() {
	local cc1="$tools_dir/libexec/gcc/mips-harvard-os161/4.8.3/cc1"
	local gdb="$tools_dir/bin/mips-harvard-os161-gdb"
	local needs_libcompat=false

	if [ ! -x "$cc1" ] || ! command -v ldd >/dev/null 2>&1; then
		return
	fi

	if ldd "$cc1" 2>/dev/null | grep -q "libmpfr.so.4 => not found"; then
		mkdir -p "$libcompat_dir"
		needs_libcompat=true

		if [ -e /usr/lib/libmpfr.so.4 ]; then
			ln -sf /usr/lib/libmpfr.so.4 "$libcompat_dir/libmpfr.so.4"
		elif [ -e /usr/lib/libmpfr.so.6 ]; then
			ln -sf /usr/lib/libmpfr.so.6 "$libcompat_dir/libmpfr.so.4"
		fi
	fi

	if [ -x "$gdb" ] && ldd "$gdb" 2>/dev/null | grep -q "libncurses.so.5 => not found"; then
		mkdir -p "$libcompat_dir"
		needs_libcompat=true

		if [ -e /usr/lib/libncurses.so.5 ]; then
			ln -sf /usr/lib/libncurses.so.5 "$libcompat_dir/libncurses.so.5"
		elif [ -e /usr/lib/libncursesw.so.6 ]; then
			ln -sf /usr/lib/libncursesw.so.6 "$libcompat_dir/libncurses.so.5"
		fi
	fi

	if [ -x "$gdb" ] && ldd "$gdb" 2>/dev/null | grep -q "libtinfo.so.5 => not found"; then
		mkdir -p "$libcompat_dir"
		needs_libcompat=true

		if [ -e /usr/lib/libtinfo.so.5 ]; then
			ln -sf /usr/lib/libtinfo.so.5 "$libcompat_dir/libtinfo.so.5"
		elif [ -e /usr/lib/libtinfo.so.6 ]; then
			ln -sf /usr/lib/libtinfo.so.6 "$libcompat_dir/libtinfo.so.5"
		fi
	fi

	if [ "$needs_libcompat" = true ]; then
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

prepare_niri_workspace

if [ "$debug" = true ]; then
	launch_xterm \
		"OS161" \
		"cd '$root_dir'; exec sys161 -w -p '$gdb_port' kernel"

	SYS161_XTERM_PID=$LAST_XTERM_PID

	sleep 1

	launch_xterm \
		"OS161-GDB" \
		"cd '$root_dir'; exec mips-harvard-os161-gdb -tui kernel -ex 'target remote :$gdb_port'"

	GDB_XTERM_PID=$LAST_XTERM_PID
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

if [ "$debug" = true ]; then
	kill "$GDB_XTERM_PID" 2>/dev/null || true
fi

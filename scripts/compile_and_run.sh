#!/usr/bin/env bash
set -e

interactive=false
debug=false
floating_windows=false
compile_only=false
clean_only=false
build_userland=false
niri_workspace_changed=false

default_config="DUMBVM"
gdb_port=16161

project_home="$HOME/os161"
src_dir="$project_home/src"
root_dir="$project_home/root"
tools_dir="$project_home/tools"
libcompat_dir="$project_home/.os161-libcompat"

xterm_font="JetBrainsMono Nerd Font Mono"
xterm_font_size=16
os161_xterm_bg="#071411"
os161_xterm_fg="#d1fae5"
os161_xterm_cursor="#34d399"
os161_xterm_border="#059669"
os161_xterm_geometry="132x36"
gdb_xterm_bg="#10131f"
gdb_xterm_fg="#f8fafc"
gdb_xterm_cursor="#f59e0b"
gdb_xterm_border="#2563eb"
gdb_xterm_geometry="150x44"
xterm_color0="#0b1220"
xterm_color1="#ef4444"
xterm_color2="#22c55e"
xterm_color3="#eab308"
xterm_color4="#3b82f6"
xterm_color5="#a855f7"
xterm_color6="#14b8a6"
xterm_color7="#e5e7eb"
xterm_color8="#475569"
xterm_color9="#f87171"
xterm_color10="#4ade80"
xterm_color11="#facc15"
xterm_color12="#60a5fa"
xterm_color13="#c084fc"
xterm_color14="#2dd4bf"
xterm_color15="#ffffff"
xterm_internal_border=10
xterm_save_lines=10000

niri_window_lookup_attempts=10
niri_window_lookup_delay=0.15
niri_fallback_workspace=999
niri_full_width="100%"
niri_split_width="50%"
gdb_launch_delay=1
interactive_progress_steps=5
interactive_progress_delay=0.06
toolchain_gcc_version="4.8.3"
os161_xterm_title="OS161"
gdb_xterm_title="OS161-GDB"

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
       $0 [options] clean [CONFIG]

Build and run an OS/161 kernel.

When CONFIG is omitted, the script tries to use a kernel configuration
matching the current git branch name uppercased. For example, branch lab2
uses LAB2 if src/kern/conf/LAB2 exists. Otherwise it asks whether to use
$default_config.

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
  -c, --compile-only  Build and install the kernel, then stop before running it.
  -k, --clean         Clean the selected kernel build directory, then stop.
  -u, --userland      Also build and install the full userland tree.
  -w                  Legacy alias for --debug.
  -h, --help          Show this help.

Short options can be combined; for example, -idfcku is the same as -i -d -f -c -k -u.

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
		-c|--compile-only)
			compile_only=true
			shift
			;;
		-k|--clean)
			clean_only=true
			shift
			;;
		-u|--userland)
			build_userland=true
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		-[!-]*)
			short_options="${1#-}"
			for ((i = 0; i < ${#short_options}; i++)); do
				case "${short_options:i:1}" in
					i)
						interactive=true
						;;
					d|w)
						debug=true
						;;
					f)
						floating_windows=true
						;;
					c)
						compile_only=true
						;;
					k)
						clean_only=true
						;;
					u)
						build_userland=true
						;;
					h)
						usage
						exit 0
						;;
					*)
						printf "Unknown option: -%s\n\n" "${short_options:i:1}" >&2
						usage >&2
						exit 2
						;;
				esac
			done
			shift
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

if [ "${1:-}" = "clean" ]; then
	clean_only=true
	shift
fi

log() {
	clear

	printf "\n%s" "$1"

	if [ "$interactive" = true ]; then
		for ((i = 0; i < interactive_progress_steps; i++)); do
			sleep "$interactive_progress_delay"
			printf "."
		done
	fi

	printf "\n\n"
}

launch_xterm() {
	local title="$1"
	local command="$2"
	local bg="$os161_xterm_bg"
	local fg="$os161_xterm_fg"
	local cursor="$os161_xterm_cursor"
	local border="$os161_xterm_border"
	local geometry="$os161_xterm_geometry"

	case "$title" in
		"$gdb_xterm_title")
			bg="$gdb_xterm_bg"
			fg="$gdb_xterm_fg"
			cursor="$gdb_xterm_cursor"
			border="$gdb_xterm_border"
			geometry="$gdb_xterm_geometry"
			;;
		"$os161_xterm_title")
			bg="$os161_xterm_bg"
			fg="$os161_xterm_fg"
			cursor="$os161_xterm_cursor"
			border="$os161_xterm_border"
			geometry="$os161_xterm_geometry"
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
		-xrm "*internalBorder: $xterm_internal_border" \
		-xrm "*saveLines: $xterm_save_lines" \
		-xrm "*scrollBar: true" \
		-xrm "*rightScrollBar: true" \
		-xrm "*color0: $xterm_color0" \
		-xrm "*color1: $xterm_color1" \
		-xrm "*color2: $xterm_color2" \
		-xrm "*color3: $xterm_color3" \
		-xrm "*color4: $xterm_color4" \
		-xrm "*color5: $xterm_color5" \
		-xrm "*color6: $xterm_color6" \
		-xrm "*color7: $xterm_color7" \
		-xrm "*color8: $xterm_color8" \
		-xrm "*color9: $xterm_color9" \
		-xrm "*color10: $xterm_color10" \
		-xrm "*color11: $xterm_color11" \
		-xrm "*color12: $xterm_color12" \
		-xrm "*color13: $xterm_color13" \
		-xrm "*color14: $xterm_color14" \
		-xrm "*color15: $xterm_color15" \
		-fa "$xterm_font" \
		-fs "$xterm_font_size" \
		-bg "$bg" \
		-fg "$fg" \
		-cr "$cursor" \
		-bd "$border" \
		-b "$xterm_internal_border" \
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
		niri msg action focus-workspace "$niri_fallback_workspace" >/dev/null 2>&1 ||
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

	for ((i = 0; i < niri_window_lookup_attempts; i++)); do
		sleep "$niri_window_lookup_delay"

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

			if [ "$debug" = false ] && [ "$title" = "$os161_xterm_title" ]; then
				niri msg action move-column-to-index 1 >/dev/null 2>&1 || true
				niri msg action set-column-width "$niri_full_width" >/dev/null 2>&1 || true
				return
			fi

			if [ "$title" = "$gdb_xterm_title" ]; then
				column_index=2
			fi

			niri msg action move-column-to-index "$column_index" >/dev/null 2>&1 || true
			niri msg action set-column-width "$niri_split_width" >/dev/null 2>&1 || true
			return
		fi
	done
}

prepare_toolchain_libs() {
	local cc1="$tools_dir/libexec/gcc/mips-harvard-os161/$toolchain_gcc_version/cc1"
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

config_exists() {
	[ -f "$src_dir/kern/conf/$1" ]
}

branch_config_name() {
	local branch

	branch=$(git -C "$project_home" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
	if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
		return 1
	fi

	printf "%s" "$branch" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]_' '_'
}

confirm_default_config() {
	local requested_config="$1"
	local answer

	printf "Warning: kernel configuration %s does not exist yet.\n" "$requested_config" >&2
	printf "Use default configuration %s instead? [Y/n] " "$default_config" >&2
	if ! read -r answer; then
		printf "\nAborted. No answer received.\n" >&2
		exit 2
	fi

	case "$answer" in
		n|N|no|NO|No)
			printf "Aborted. Create src/kern/conf/%s or pass an existing CONFIG.\n" "$requested_config" >&2
			exit 2
			;;
		*)
			conf="$default_config"
			;;
	esac
}

select_config() {
	local branch_config

	if [ $# -eq 1 ]; then
		conf="$1"
		return
	fi

	if [ $# -gt 1 ]; then
		printf "Too many arguments.\n\n" >&2
		usage >&2
		exit 2
	fi

	branch_config=$(branch_config_name || true)
	if [ -n "$branch_config" ] && config_exists "$branch_config"; then
		conf="$branch_config"
		log "Using branch configuration $conf"
		return
	fi

	if [ -z "$branch_config" ]; then
		branch_config="$default_config"
	fi

	confirm_default_config "$branch_config"
	log "Using default configuration $conf"
}

select_config "$@"

log "Applying configuration"

cd "$src_dir/kern/conf"
./config "$conf"

log "Configuration applied"

cd "$src_dir/kern/compile/$conf"

if [ "$clean_only" = true ]; then
	log "Cleaning kernel build"
	bmake clean
	echo ""
	echo "Clean mode: kernel build directory cleaned."
	echo ""
	exit 0
fi

log "Building kernel"

bmake depend
bmake
bmake install

log "Kernel build finished"

if [ "$build_userland" = true ]; then
	log "Building full userland"
	if [ "$interactive" = true ]; then
		"$project_home/scripts/compile_userland.sh" -i
	else
		"$project_home/scripts/compile_userland.sh"
	fi
	log "Userland build finished"
fi

if [ "$compile_only" = true ]; then
	echo ""
	if [ "$build_userland" = true ]; then
		echo "Compile-only mode: kernel and userland built and installed."
	else
		echo "Compile-only mode: kernel built and installed."
	fi
	echo ""
	exit 0
fi

clear

echo ""
echo "Kernel booted"
echo ""

cd "$root_dir"

prepare_niri_workspace

if [ "$debug" = true ]; then
	launch_xterm \
		"$os161_xterm_title" \
		"cd '$root_dir'; exec sys161 -w -p '$gdb_port' kernel"

	SYS161_XTERM_PID=$LAST_XTERM_PID

	sleep "$gdb_launch_delay"

	launch_xterm \
		"$gdb_xterm_title" \
		"cd '$root_dir'; exec mips-harvard-os161-gdb -tui kernel -ex 'target remote :$gdb_port'"

	GDB_XTERM_PID=$LAST_XTERM_PID
else
	launch_xterm \
		"$os161_xterm_title" \
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

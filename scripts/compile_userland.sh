#!/usr/bin/env bash
set -e

interactive=false
clean_only=false
rebuild=false
stage_only=false
install_root=true
use_libcompat=true
target="build"

project_home="$HOME/os161"
src_dir="$project_home/src"
userland_dir="$src_dir/userland"
tools_dir="$project_home/tools"
libcompat_dir="$project_home/.os161-libcompat"

interactive_progress_steps=5
interactive_progress_delay=0.06
toolchain_gcc_version="4.8.3"

export PATH="$tools_dir/bin:$PATH"

usage() {
	cat <<EOF
Usage: $0 [options] [PROGRAM_OR_DIR]
       $0 [options] clean [PROGRAM_OR_DIR]

Build OS/161 userland programs.

When PROGRAM_OR_DIR is omitted, the whole userland tree is built and installed
into the OS/161 root. You can pass a directory relative to src/userland, such as
testbin/palin, bin/ls, or just a program name such as palin.

Options:
  -i, --interactive    Show animated progress dots between build steps.
  -k, --clean          Clean the selected userland directory, then stop.
  -r, --rebuild        Clean, then build.
  -s, --stage-only     Build into the staging area only; do not install to root.
  -t, --target TARGET  Run a specific bmake target instead of build.
  --no-libcompat       Disable local compatibility symlinks for old tool libs.
  -h, --help           Show this help.

Short options can be combined; for example, -ir is the same as -i -r.

Examples:
  $0                   Build and install all userland.
  $0 palin             Build and install src/userland/testbin/palin.
  $0 testbin/palin     Same as above.
  $0 -k palin          Clean only palin.
  $0 -t depend palin   Run bmake depend in palin's directory.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-i|--interactive)
			interactive=true
			shift
			;;
		-k|--clean)
			clean_only=true
			shift
			;;
		-r|--rebuild)
			rebuild=true
			shift
			;;
		-s|--stage-only)
			stage_only=true
			install_root=false
			shift
			;;
		-t|--target)
			if [ $# -lt 2 ]; then
				printf "Missing value for %s.\n\n" "$1" >&2
				usage >&2
				exit 2
			fi
			target="$2"
			shift 2
			;;
		--no-libcompat)
			use_libcompat=false
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
					k)
						clean_only=true
						;;
					r)
						rebuild=true
						;;
					s)
						stage_only=true
						install_root=false
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
	printf "\n%s" "$1"

	if [ "$interactive" = true ]; then
		for ((i = 0; i < interactive_progress_steps; i++)); do
			sleep "$interactive_progress_delay"
			printf "."
		done
	fi

	printf "\n\n"
}

prepare_toolchain_libs() {
	local cc1="$tools_dir/libexec/gcc/mips-harvard-os161/$toolchain_gcc_version/cc1"
	local needs_libcompat=false

	if [ "$use_libcompat" != true ]; then
		return
	fi

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

	if [ "$needs_libcompat" = true ]; then
		export LD_LIBRARY_PATH="$libcompat_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	fi
}

resolve_userland_dir() {
	local requested="$1"
	local found

	if [ -z "$requested" ]; then
		printf "%s" "$userland_dir"
		return
	fi

	requested="${requested#src/userland/}"
	requested="${requested#userland/}"
	requested="${requested%/}"

	if [ -d "$userland_dir/$requested" ] && [ -f "$userland_dir/$requested/Makefile" ]; then
		printf "%s" "$userland_dir/$requested"
		return
	fi

	found=$(
		find "$userland_dir/bin" "$userland_dir/sbin" "$userland_dir/testbin" \
			-mindepth 1 -maxdepth 1 -type d -name "$requested" -print -quit 2>/dev/null
	)

	if [ -n "$found" ] && [ -f "$found/Makefile" ]; then
		printf "%s" "$found"
		return
	fi

	printf "Cannot find userland program or directory: %s\n" "$1" >&2
	printf "Try a path like testbin/palin, bin/ls, or a program name like palin.\n" >&2
	exit 2
}

run_bmake() {
	local dir="$1"
	local make_target="$2"

	cd "$dir"
	bmake "$make_target"
}

install_staging_to_root() {
	cd "$src_dir"
	bmake install
}

if [ $# -gt 1 ]; then
	printf "Too many arguments.\n\n" >&2
	usage >&2
	exit 2
fi

program_or_dir="${1:-}"
build_dir=$(resolve_userland_dir "$program_or_dir")

prepare_toolchain_libs

if [ "$clean_only" = true ]; then
	log "Cleaning userland"
	run_bmake "$build_dir" clean
	printf "Clean mode: userland directory cleaned: %s\n" "$build_dir"
	exit 0
fi

if [ "$rebuild" = true ]; then
	log "Cleaning userland"
	run_bmake "$build_dir" clean
fi

log "Building userland"
run_bmake "$build_dir" "$target"

if [ "$target" != "build" ]; then
	printf "Target mode: ran bmake %s in %s\n" "$target" "$build_dir"
	exit 0
fi

if [ "$install_root" = true ]; then
	if [ -z "$program_or_dir" ]; then
		log "Installing staged userland to root"
		install_staging_to_root
	else
		log "Installing program to root"
		run_bmake "$build_dir" install
	fi
fi

if [ "$stage_only" = true ]; then
	printf "Stage-only mode: userland built in staging area.\n"
else
	printf "Userland build finished: %s\n" "$build_dir"
fi

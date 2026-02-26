#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Parse grammar name -> root from build.zig
# Format: "name=root" per line, only entries with non-default roots
ROOTS_MAP=$(sed -n 's/.*\.name = "\([^"]*\)".*\.root = "\([^"]*\)".*/\1=\2/p' build.zig)

get_root() {
    local match
    match=$(echo "$ROOTS_MAP" | grep "^${1}=" | head -1 | cut -d= -f2-) || true
    echo "${match:-src}"
}

# Parse dependency name + URL from build.zig.zon, download each grammar
current_name=""
while IFS= read -r line; do
    # Match dependency name: .bash = .{
    new_name=$(echo "$line" | sed -n 's/^[[:space:]]*\.\([a-z_]*\) = \.{.*/\1/p') || true
    if [ -n "$new_name" ]; then
        current_name="$new_name"
    fi

    # Match URL: .url = "..."
    url=$(echo "$line" | sed -n 's/.*\.url = "\([^"]*\)".*/\1/p') || true
    if [ -z "$url" ] || [ -z "$current_name" ]; then
        continue
    fi

    # Skip the core tree-sitter library
    if [ "$current_name" = "tree_sitter_api" ]; then
        current_name=""
        continue
    fi

    root=$(get_root "$current_name")

    if [ -f "grammars/$current_name/$root/parser.c" ]; then
        echo "skip $current_name"
    else
        echo "vendor $current_name"
        mkdir -p "grammars/$current_name"

        case "$url" in
            git+*)
                # git+https://github.com/user/repo#commit -> archive tarball
                repo_commit="${url#git+}"
                commit="${repo_commit##*#}"
                repo="${repo_commit%%#*}"
                curl -fsSL "$repo/archive/$commit.tar.gz" | tar xz --strip-components=1 -C "grammars/$current_name"
                ;;
            *)
                curl -fsSL "$url" | tar xz --strip-components=1 -C "grammars/$current_name"
                ;;
        esac
    fi

    current_name=""
done < build.zig.zon

echo "done"

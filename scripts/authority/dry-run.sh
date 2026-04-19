#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/authority/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/dry-run.sh --target TARGET --diff-file PATCH
       scripts/authority/dry-run.sh --target TARGET --patch PATCH
USAGE
  exit 2
}

target=""
patch_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || usage
      target="$2"
      shift 2
      ;;
    --diff-file|--patch)
      [[ $# -ge 2 ]] || usage
      patch_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$target" ]] || usage
[[ -n "$patch_file" ]] || usage
[[ -r "$patch_file" ]] || die "patch file is not readable: $patch_file"

target="$(repo_relpath "$target")"
tmp_dir="$(mktemp -d)"
warnings_file="$tmp_dir/warnings.jsonl"
errors_file="$tmp_dir/errors.jsonl"
touch "$warnings_file" "$errors_file"
trap 'rm -rf "$tmp_dir"' EXIT

record_warning() {
  jq -cn --arg message "$1" '$message' >> "$warnings_file"
}

record_error() {
  jq -cn --arg message "$1" '$message' >> "$errors_file"
}

mkdir -p "$tmp_dir/repo"
mkdir -p "$tmp_dir/repo/$(dirname "$target")"
if [[ -e "$REPO_ROOT/$target" ]]; then
  cp "$REPO_ROOT/$target" "$tmp_dir/repo/$target"
fi

if ! (cd "$REPO_ROOT" && git apply --check "$patch_file" >/dev/null 2>&1); then
  record_error "git apply --check failed for patch"
fi

if ! (cd "$tmp_dir/repo" && patch -s -p1 < "$patch_file" >/dev/null 2>&1); then
  if ! (cd "$tmp_dir/repo" && patch -s -p0 < "$patch_file" >/dev/null 2>&1); then
    record_error "patch could not be applied in dry-run workspace"
  fi
fi

candidate="$tmp_dir/repo/$target"
if [[ ! -e "$candidate" && -e "$REPO_ROOT/$target" ]]; then
  candidate="$REPO_ROOT/$target"
fi

case "$target" in
  *.yaml|*.yml)
    if [[ -e "$candidate" ]] && ! ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$candidate" >/dev/null 2>&1; then
      record_error "YAML syntax check failed for $target"
    fi
    ;;
  *.json)
    if [[ -e "$candidate" ]] && ! ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$candidate" >/dev/null 2>&1; then
      record_error "JSON syntax check failed for $target"
    fi
    ;;
esac

if [[ "$target" == *.md && -e "$candidate" ]]; then
  if ! ruby - "$candidate" "$tmp_dir/repo" "$REPO_ROOT" <<'RUBY' > "$tmp_dir/dead-links.txt"; then
file = ARGV.fetch(0)
tmp_root = ARGV.fetch(1)
repo_root = ARGV.fetch(2)
base = File.dirname(file)
dead = []

content = File.read(file)
content.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |raw|
  href = raw.split(/\s+/, 2).first.to_s
  next if href.empty?
  next if href.start_with?("#", "http://", "https://", "mailto:")

  path = href.sub(/#.*/, "")
  next if path.empty?

  candidates = []
  if path.start_with?("/")
    rel = path.sub(%r{\A/+}, "")
    candidates << File.join(tmp_root, rel)
    candidates << File.join(repo_root, rel)
  else
    candidates << File.expand_path(path, base)
    repo_candidate = File.expand_path(path, File.join(repo_root, File.dirname(file.sub(%r{\A#{Regexp.escape(tmp_root)}/?}, ""))))
    candidates << repo_candidate
  end

  dead << href unless candidates.any? { |candidate| File.exist?(candidate) }
end

puts dead
exit(dead.empty? ? 0 : 1)
RUBY
    while IFS= read -r link; do
      [[ -n "$link" ]] && record_error "dead markdown link after patch: $link"
    done < "$tmp_dir/dead-links.txt"
  fi
fi

changed_lines="$(
  awk '
    /^(\+\+\+|---)/ { next }
    /^[+-]/ { count++ }
    END { print count + 0 }
  ' "$patch_file"
)"

current_lines=0
if [[ -f "$REPO_ROOT/$target" ]]; then
  current_lines="$(wc -l < "$REPO_ROOT/$target" | tr -d '[:space:]')"
fi

if [[ "$changed_lines" -gt 200 ]]; then
  record_warning "large diff warning: $changed_lines changed lines"
fi

if [[ "$current_lines" -gt 0 && "$changed_lines" -gt $((current_lines / 2)) ]]; then
  record_warning "minimal diff warning: changed lines exceed 50 percent of current file length"
fi

error_count="$(wc -l < "$errors_file" | tr -d '[:space:]')"

jq -n \
  --argjson ok "$([[ "$error_count" -eq 0 ]] && echo true || echo false)" \
  --arg target "$target" \
  --slurpfile errors "$errors_file" \
  --slurpfile warnings "$warnings_file" \
  '{
    ok: $ok,
    target: $target,
    errors: $errors,
    warnings: $warnings
  }'

[[ "$error_count" -eq 0 ]]

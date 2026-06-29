#!/usr/bin/env bash
#
# triage-scan.sh — Resource Intake Triage scanner (T-OS-508)
#
# Owner が docs/ やルート等に置いた参照・参考ファイルを走査し、
# .ai/RESOURCES/ の適切なサブディレクトリへの取り込み候補として提案する。
# --apply 指定時のみ実際に git mv + 台帳登録 + リネームを実行する。
#
# Rule: .claude/rules/resource-intake-triage.md
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

RESOURCES_DIR=".ai/RESOURCES"
LEDGER="${RESOURCES_DIR}/README.md"

APPLY=0
JSON=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/resources/triage-scan.sh            # 走査して取り込み候補を提案（移動しない）
  bash scripts/resources/triage-scan.sh --json     # 機械可読 (JSON) で候補を出力
  bash scripts/resources/triage-scan.sh --apply     # 候補を取り込む（git mv + 台帳登録 + リネーム）

候補が 0 件なら exit 0。--apply なしで候補ありなら exit 0（提案のみ）。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# ルート直下の固定文書（絶対に動かさない）
is_root_fixed() {
  case "$1" in
    CLAUDE.md|AGENTS.md|README.md|ORGOS_QUICKSTART.md) return 0 ;;
    *) return 1 ;;
  esac
}

# 拡張子 → 配置先サブディレクトリ。未知の種別は "references"（要確認カテゴリ）
classify() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.pdf|*.docx|*.doc|*.txt|*.csv|*.xlsx|*.xls|*.md) echo "docs/inputs" ;;
    *.pptx|*.ppt|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.fig|*.sketch|*.xd) echo "designs" ;;
    *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.java|*.rb|*.php|*.c|*.cpp|*.sh) echo "code-samples" ;;
    *) echo "references" ;;
  esac
}

# 受領日プレフィックス（ファイル名に日付らしき 8 桁がなければ付与）
date_prefix_if_needed() {
  local base="$1"
  if [[ "$base" =~ [0-9]{8} || "$base" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
    echo "$base"
  else
    echo "$(date +%Y%m%d)_${base}"
  fi
}

# 走査対象を収集（NUL 区切り）: ルート直下 + docs/ 直下（docs/archive は意図的退避なので除外）
collect_candidates() {
  # ルート直下のファイル（maxdepth 1, ファイルのみ, ドットファイル除外）
  find . -maxdepth 1 -type f ! -name '.*' -print0
  # docs/ 直下のファイル（サブディレクトリ archive 等は除外）
  if [[ -d docs ]]; then
    find docs -maxdepth 1 -type f ! -name '.*' -print0
  fi
}

CANDIDATES=()
while IFS= read -r -d '' f; do
  rel="${f#./}"
  name="$(basename "$rel")"
  # ルート直下の固定文書を除外
  if [[ "$rel" == "$name" ]] && is_root_fixed "$name"; then
    continue
  fi
  CANDIDATES+=("$rel")
done < <(collect_candidates)

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  if [[ "$JSON" -eq 1 ]]; then echo '{"candidates":[],"count":0}'; else echo "取り込み候補なし。"; fi
  exit 0
fi

# JSON 出力
if [[ "$JSON" -eq 1 ]]; then
  printf '{"candidates":['
  first=1
  for rel in "${CANDIDATES[@]}"; do
    dest="$(classify "$rel")"
    [[ $first -eq 1 ]] || printf ','
    first=0
    printf '{"source":"%s","dest":".ai/RESOURCES/%s/"}' "$rel" "$dest"
  done
  printf '],"count":%d}\n' "${#CANDIDATES[@]}"
fi

# 台帳へ 1 行追記（テーブル区切り行の直後に挿入し、プレースホルダ行があれば除去）
append_ledger() {
  local newname="$1" dest="$2"
  local today; today="$(date +%Y-%m-%d)"
  local row="| ${newname} | .ai/RESOURCES/${dest}/ | Owner | (triage 取込) | ${today} |"
  local tmp; tmp="$(mktemp)"
  awk -v row="$row" '
    BEGIN { inserted=0 }
    /^\| *\(entries\) *\|/ { next }   # プレースホルダ行を除去
    { print }
    /^\|[-| ]+\|$/ && !inserted { print row; inserted=1 }
  ' "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
}

# 提案 / 適用
echo ""
echo "取り込み候補 ${#CANDIDATES[@]} 件:"
for rel in "${CANDIDATES[@]}"; do
  dest="$(classify "$rel")"
  name="$(basename "$rel")"
  newname="$(date_prefix_if_needed "$name")"
  target="${RESOURCES_DIR}/${dest}/${newname}"
  if [[ "$APPLY" -eq 1 ]]; then
    mkdir -p "${RESOURCES_DIR}/${dest}"
    if git ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      git mv "$rel" "$target"
    else
      mv "$rel" "$target"
    fi
    append_ledger "$newname" "$dest"
    echo "  [取込] $rel → $target"
  else
    echo "  [候補] $rel → $target"
  fi
done

if [[ "$APPLY" -eq 0 ]]; then
  echo ""
  echo "取り込むには: bash scripts/resources/triage-scan.sh --apply"
fi

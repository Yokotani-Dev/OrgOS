#!/bin/bash
# run-parallel.sh - 複数のCodexタスクを並列実行する
#
# Usage: ./run-parallel.sh T-003 T-004 T-005
#        ./run-parallel.sh --all        # 実行可能な全タスクを実行
#        ./run-parallel.sh --status     # 実行中タスクの状態を確認
#
# 各タスクは別々のworktreeで実行され、結果は.ai/CODEX/RESULTS/に出力される

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKTREES_DIR="$PROJECT_ROOT/.worktrees"
ORDERS_DIR="$PROJECT_ROOT/.ai/CODEX/ORDERS"
RESULTS_DIR="$PROJECT_ROOT/.ai/CODEX/RESULTS"
LOGS_DIR="$PROJECT_ROOT/.ai/CODEX/LOGS"
CONTROL_FILE="$PROJECT_ROOT/.ai/CONTROL.yaml"

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# CONTROL.yamlからCodex設定を読み取る
get_codex_config() {
    local key=$1
    local default=$2
    if [[ -f "$CONTROL_FILE" ]]; then
        grep "^  $key:" "$CONTROL_FILE" | sed 's/.*: *"\?\([^"]*\)"\?.*/\1/' || echo "$default"
    else
        echo "$default"
    fi
}

# Worktreeを作成
setup_worktree() {
    local task_id=$1
    local worktree_path="$WORKTREES_DIR/$task_id"
    local branch_name="task/$task_id"

    if [[ -d "$worktree_path" ]]; then
        log_info "Worktree already exists: $worktree_path"
        return 0
    fi

    log_info "Creating worktree for $task_id..."

    # ブランチが存在しない場合は作成
    if ! git -C "$PROJECT_ROOT" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        git -C "$PROJECT_ROOT" branch "$branch_name"
    fi

    # Worktreeを追加
    git -C "$PROJECT_ROOT" worktree add "$worktree_path" "$branch_name"

    log_success "Worktree created: $worktree_path"
}

# Codexを実行
run_codex() {
    local task_id=$1
    local worktree_path="$WORKTREES_DIR/$task_id"
    local order_file="$ORDERS_DIR/$task_id.md"
    local log_file="$LOGS_DIR/$task_id.log"
    local result_file="$RESULTS_DIR/$task_id.json"

    # Work Orderの確認
    if [[ ! -f "$order_file" ]]; then
        log_error "Work Order not found: $order_file"
        log_warn "Run /org-tick to generate Work Orders first"
        return 1
    fi

    # Worktreeの準備
    setup_worktree "$task_id"

    # Codex設定を取得
    local sandbox=$(get_codex_config "sandbox" "workspace-write")
    local approval=$(get_codex_config "approval" "on-request")

    # Codexコマンドを構築
    local codex_cmd="codex exec"

    case "$sandbox" in
        "read-only")
            codex_cmd="$codex_cmd --sandbox read-only"
            ;;
        "workspace-write")
            codex_cmd="$codex_cmd --sandbox workspace-write"
            ;;
        "danger-full-access")
            codex_cmd="$codex_cmd --sandbox danger-full-access"
            ;;
    esac

    case "$approval" in
        "untrusted")
            codex_cmd="$codex_cmd --ask-for-approval untrusted"
            ;;
        "on-failure")
            codex_cmd="$codex_cmd --ask-for-approval on-failure"
            ;;
        "on-request")
            codex_cmd="$codex_cmd --ask-for-approval on-request"
            ;;
        "never")
            codex_cmd="$codex_cmd --ask-for-approval never"
            ;;
    esac

    local prompt="AGENTS.md を読み、$order_file の指示に従って実行せよ"

    log_info "Starting Codex for $task_id..."
    log_info "Working directory: $worktree_path"
    log_info "Log file: $log_file"

    # ログディレクトリを作成
    mkdir -p "$LOGS_DIR"

    # Codexをバックグラウンドで実行
    (
        cd "$worktree_path"
        $codex_cmd "$prompt" 2>&1 | tee "$log_file"
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            log_success "$task_id completed successfully"
        else
            log_error "$task_id failed with exit code $exit_code"
        fi
    ) &

    local pid=$!
    echo "$pid" > "$LOGS_DIR/$task_id.pid"

    log_success "$task_id started (PID: $pid)"
    echo "$pid"
}

# 実行中のタスク状態を確認
check_status() {
    log_info "Checking running tasks..."

    if [[ ! -d "$LOGS_DIR" ]]; then
        log_warn "No tasks have been run yet"
        return 0
    fi

    local running=0
    local completed=0
    local failed=0

    for pid_file in "$LOGS_DIR"/*.pid; do
        [[ -f "$pid_file" ]] || continue

        local task_id=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")

        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}RUNNING${NC}  $task_id (PID: $pid)"
            ((running++))
        else
            local result_file="$RESULTS_DIR/$task_id.json"
            if [[ -f "$result_file" ]]; then
                local status=$(grep '"status"' "$result_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
                if [[ "$status" == "completed" ]] || [[ "$status" == "approved" ]]; then
                    echo -e "${GREEN}DONE${NC}     $task_id"
                    ((completed++))
                else
                    echo -e "${RED}FAILED${NC}   $task_id ($status)"
                    ((failed++))
                fi
            else
                echo -e "${RED}UNKNOWN${NC}  $task_id (no result file)"
                ((failed++))
            fi
            rm -f "$pid_file"
        fi
    done

    echo ""
    log_info "Summary: $running running, $completed completed, $failed failed"
}

# すべてのタスクを待機
wait_all() {
    log_info "Waiting for all tasks to complete..."

    if [[ ! -d "$LOGS_DIR" ]]; then
        log_warn "No tasks to wait for"
        return 0
    fi

    for pid_file in "$LOGS_DIR"/*.pid; do
        [[ -f "$pid_file" ]] || continue

        local task_id=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")

        if kill -0 "$pid" 2>/dev/null; then
            log_info "Waiting for $task_id (PID: $pid)..."
            wait "$pid" 2>/dev/null || true
        fi
    done

    check_status
}

# Worktreeのクリーンアップ
cleanup_worktree() {
    local task_id=$1
    local worktree_path="$WORKTREES_DIR/$task_id"

    if [[ -d "$worktree_path" ]]; then
        log_info "Removing worktree for $task_id..."
        git -C "$PROJECT_ROOT" worktree remove "$worktree_path" --force 2>/dev/null || true
        log_success "Worktree removed: $worktree_path"
    fi
}

# ヘルプを表示
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [TASK_IDs...]

Parallel execution of Codex tasks using git worktrees.

Options:
  --status      Show status of running/completed tasks
  --wait        Wait for all running tasks to complete
  --cleanup ID  Remove worktree for specified task
  --help        Show this help message

Examples:
  $(basename "$0") T-003 T-004 T-005    Run multiple tasks in parallel
  $(basename "$0") --status             Check task status
  $(basename "$0") --wait               Wait for all tasks
  $(basename "$0") --cleanup T-003      Remove T-003 worktree

Notes:
  - Each task runs in its own worktree (.worktrees/<TASK_ID>/)
  - Results are written to .ai/CODEX/RESULTS/<TASK_ID>.json
  - Logs are written to .ai/CODEX/LOGS/<TASK_ID>.log
  - Work Orders must exist in .ai/CODEX/ORDERS/<TASK_ID>.md
EOF
}

# メイン処理
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi

    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --status)
            check_status
            exit 0
            ;;
        --wait)
            wait_all
            exit 0
            ;;
        --cleanup)
            if [[ $# -lt 2 ]]; then
                log_error "Task ID required for cleanup"
                exit 1
            fi
            cleanup_worktree "$2"
            exit 0
            ;;
        --*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            # タスクIDのリストとして処理
            local pids=()
            for task_id in "$@"; do
                if [[ "$task_id" =~ ^T- ]]; then
                    pid=$(run_codex "$task_id")
                    pids+=("$pid")
                else
                    log_warn "Invalid task ID format: $task_id (expected T-XXX)"
                fi
            done

            echo ""
            log_success "Started ${#pids[@]} tasks in parallel"
            log_info "Check status: $0 --status"
            log_info "Wait for completion: $0 --wait"
            ;;
    esac
}

main "$@"

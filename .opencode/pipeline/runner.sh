#!/bin/bash
# Pipeline Runner — Meow workflow auto-flow engine
# 用法: runner.sh start <feature-name>
#        runner.sh continue <feature-name>

WORKDIR="${WORKDIR:-.}"

PHASES=("spec" "plan" "craft" "verify" "deliver" "DONE")

get_state_file() {
    echo "$WORKDIR/.opencode/works/$1/status.json"
}

get_current_phase() {
    local feature_name="$1"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    state = json.load(f)
phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
idx = state.get('phase', 0)
print(phases[idx] if idx < len(phases) else "DONE")
PYEOF
}

get_state_info() {
    local feature_name="$1"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" <<'PYEOF'
import json, sys
state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

print(f"PROJECT_TYPE={state.get('project_type', 'backend')}")
print(f"COMPLEXITY={state.get('complexity', 'standard')}")
print(f"DOMAIN={state.get('domain', 'generic')}")
print(f"SUBAGENT={state.get('subagent', 'coder')}")
print(f"MODEL_TIER={state.get('model_tier', 'mid-high')}")
print(f"ESCALATE={state.get('escalate', False)}")
print(f"APPROVED={state.get('approved', False)}")
print(f"RELEASED={state.get('released', False)}")
PYEOF
}

# Test command lookup by project_type + root files
get_test_command() {
    local project_type="$1"
    local work_dir="$WORKDIR"

    case "$project_type" in
        frontend)
            if [ -f "$work_dir/package.json" ]; then
                echo "npm run test; npx biome ci ."
            else
                echo "echo 'No package.json found'"
            fi
            ;;
        backend)
            if [ -f "$work_dir/Gemfile" ]; then
                echo "bundle exec rspec; bundle exec ruby -c lib/"
            elif [ -f "$work_dir/Cargo.toml" ]; then
                echo "cargo test; cargo clippy -- -D warnings"
            elif [ -f "$work_dir/package.json" ]; then
                echo "npm run test"
            else
                echo "echo 'No recognized backend test config'"
            fi
            ;;
        docs|blog|wiki)
            echo "echo 'Lightweight verify: docs syntax check only'"
            ;;
        comprehensive)
            # Comprehensive uses backend test command as primary, plus frontend if package.json exists
            local cmd=""
            if [ -f "$work_dir/Gemfile" ]; then
                cmd="bundle exec rspec; bundle exec ruby -c lib/"
            elif [ -f "$work_dir/Cargo.toml" ]; then
                cmd="cargo test; cargo clippy -- -D warnings"
            fi
            if [ -f "$work_dir/package.json" ]; then
                if [ -n "$cmd" ]; then
                    cmd="$cmd; npm run test"
                else
                    cmd="npm run test"
                fi
            fi
            if [ -z "$cmd" ]; then
                cmd="echo 'No recognized test config for comprehensive project'"
            fi
            echo "$cmd"
            ;;
        *)
            echo "echo 'Unknown project_type: $project_type'"
            ;;
    esac
}

# Model tier → default model mapping
get_model_for_tier() {
    local tier="$1"
    local role="$2"

    # Default mapping; can be overridden by status.json model_override
    case "$tier" in
        base)
            echo "muse-spark-1.2-contributor"
            ;;
        mid)
            echo "mimo-v2.5-pro"
            ;;
        mid-high)
            # Coder/reviewer/tester use minimax for mid-high; others use hy3
            case "$role" in
                tester|reviewer|planner)
                    echo "minimax-m2.7-highspeed"
                    ;;
                *)
                    echo "hy3"
                    ;;
            esac
            ;;
        high)
            echo "kimi-k2.7-code"
            ;;
        apex)
            echo "claude-opus-5"
            ;;
        *)
            echo "hy3"
            ;;
    esac
}

get_phase_model() {
    local feature_name="$1"
    local phase="$2"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" "$phase" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
phase = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

tier = state.get('model_tier', 'mid-high')
override = state.get('model_override', {})

# Map phase to role
role_map = {
    'spec': 'explorer',
    'plan': 'planner',
    'craft': 'coder',
    'verify': 'tester',
    'deliver': 'deliverer'
}
role = role_map.get(phase, 'coder')

# Check override
if override.get(phase):
    print(override[phase])
    sys.exit(0)

# Default tier mapping
tier_map = {
    'base': 'muse-spark-1.2-contributor',
    'mid': 'mimo-v2.5-pro',
    'mid-high': 'hy3',
    'high': 'kimi-k2.7-code',
    'apex': 'claude-opus-5'
}

# Role-specific adjustments for mid-high
if tier == 'mid-high' and role in ('tester', 'reviewer', 'planner'):
    print('minimax-m2.7-highspeed')
else:
    print(tier_map.get(tier, 'hy3'))
PYEOF
}

get_phase_subagent() {
    local phase="$1"
    local project_type="$2"
    local complexity="$3"

    case "$phase" in
        spec)
            if [ "$project_type" == "docs" ] || [ "$project_type" == "blog" ] || [ "$project_type" == "wiki" ]; then
                echo "writer"
            else
                echo "explorer"
            fi
            ;;
        plan)
            echo "planner"
            ;;
        craft)
            echo "coder"
            ;;
        verify)
            echo "tester"
            ;;
        deliver)
            echo "deliverer"
            ;;
        *)
            echo "general"
            ;;
    esac
}

run_agent() {
    local feature_name="$1"
    local phase="$2"
    local model="$3"
    local subagent="$4"
    local domain="$5"
    local project_type="$6"
    local test_command="$7"

    echo ""
    echo "━━━ Running phase: $phase (subagent: $subagent, model: $model) ━━━━━━━━━"
    echo ""

    # Map new subagent names to existing agent files
    local agent_name="$subagent"
    case "$subagent" in
        explorer|planner|writer)
            agent_name="feature"
            ;;
        deliverer)
            agent_name="releaser"
            ;;
        coder|reviewer|tester)
            agent_name="$subagent"
            ;;
    esac

    echo "→ 调用 $agent_name agent..."
    echo "   project_type: $project_type"
    echo "   domain: $domain"
    echo "   test_command: $test_command"
    # opencode agent:$agent_name --feature "$feature_name" --domain "$domain" --project-type "$project_type"
}

advance_phase() {
    local feature_name="$1"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" <<'PYEOF'
import json, sys, datetime
state_file = sys.argv[1]
with open(state_file, 'r') as f:
    state = json.load(f)

phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
current_idx = state.get('phase', 0)
project_type = state.get('project_type', 'backend')
complexity = state.get('complexity', 'standard')

skip_plan = complexity == 'trivial' or project_type in ('docs', 'blog', 'wiki')

if current_idx == 0 and skip_plan:
    # Skip plan, go to craft
    state['phase'] = 2
    state['phases']['plan']['status'] = 'skipped'
    state['status'] = 'RUNNING'
    state['updated_at'] = str(datetime.datetime.now().astimezone())
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)
    print("✅ Phase advanced to craft (plan skipped)")
elif current_idx < len(phases) - 2:
    # Not yet at deliver, advance normally
    state['phase'] = current_idx + 1
    state['status'] = 'RUNNING'
    state['updated_at'] = str(datetime.datetime.now().astimezone())
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)
    print(f"✅ Phase advanced to {phases[current_idx + 1]} (index {current_idx + 1})")
elif current_idx == len(phases) - 2:
    # At deliver, advance to DONE
    state['phase'] = current_idx + 1
    state['status'] = 'DONE'
    state['updated_at'] = str(datetime.datetime.now().astimezone())
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)
    print("✅ Pipeline completed")
else:
    state['status'] = 'DONE'
    state['updated_at'] = str(datetime.datetime.now().astimezone())
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)
    print("✅ Pipeline completed")
PYEOF
}

check_and_handle_checkpoint() {
    local feature_name="$1"
    local next_phase="$2"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" "$next_phase" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
next_phase = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
current_idx = state.get('phase', 0)
current_phase = phases[current_idx] if current_idx < len(phases) else "DONE"
project_type = state.get('project_type', 'backend')
complexity = state.get('complexity', 'standard')

# APPROVED checkpoint: after Plan phase (current=plan, next=craft)
skip_approved = complexity == 'trivial' or project_type in ('docs', 'blog', 'wiki')
if next_phase == "craft" and current_phase == "plan" and not skip_approved:
    if not state.get('approved', False):
        print("APPROVED")
        sys.exit(0)

# RELEASING checkpoint: before Deliver (current=verify, next=deliver)
if next_phase == "deliver" and current_phase == "verify":
    if not state.get('released', False):
        print("RELEASING")
        sys.exit(0)

print("CONTINUE")
PYEOF
}

show_banner() {
    local feature_name="$1"
    local phase="$2"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" "$phase" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
phase = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
phase_idx = phases.index(phase) if phase in phases else 0

print()
print("━" * 60)
print(f"  Phase {phase_idx}/5: {phase.upper()}")
print(f"  Feature: {state['feature']}")
print(f"  Project Type: {state.get('project_type', 'backend')}")
print(f"  Complexity: {state.get('complexity', 'standard')}")
print(f"  Domain: {state.get('domain', 'generic')}")
if state.get('escalate'):
    print("  ⚠️  ESCALATE flag is set")
print("━" * 60)
print()
PYEOF
}

handle_blocker() {
    local feature_name="$1"
    local phase="$2"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" "$phase" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
phase = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

attempts = state['phases'][phase].get('attempts', 0)
limit = state['retry_limits'].get(phase, 3)

if attempts < limit:
    state['phases'][phase]['attempts'] = attempts + 1
    state['phases'][phase]['status'] = 'failed'
    state['phase'] = 2  # back to craft
    state['status'] = 'RUNNING'
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)
    print(f"RETRY:{attempts + 1}")
else:
    print("ESCALATE")
PYEOF
}

cmd="${1:-}"
feature_name="${2:-}"

if [ -z "$feature_name" ]; then
    echo "Usage: runner.sh <start|continue|status|test-cmd> <feature-name>"
    exit 1
fi

state_file=$(get_state_file "$feature_name")
if [ ! -f "$state_file" ]; then
    echo "❌ 状态文件不存在: $state_file"
    echo "   请先运行: state.sh init <feature-name>"
    exit 1
fi

if [ "$cmd" == "test-cmd" ]; then
    project_type=$(get_state_info "$feature_name" | grep "^PROJECT_TYPE=" | cut -d= -f2)
    echo "Test command: $(get_test_command "$project_type")"
    exit 0
fi

current_phase=$(get_current_phase "$feature_name")

if [ "$current_phase" == "DONE" ]; then
    echo "✅ Pipeline 已完成"
    exit 0
fi

if [ "$cmd" == "status" ]; then
    "$(dirname "$0")/state.sh" status "$feature_name"
    exit 0
fi

if [ "$cmd" == "continue" ] || [ "$cmd" == "start" ]; then
    show_banner "$feature_name" "$current_phase"

    state_info=$(get_state_info "$feature_name")
    project_type=$(echo "$state_info" | grep "^PROJECT_TYPE=" | cut -d= -f2)
    complexity=$(echo "$state_info" | grep "^COMPLEXITY=" | cut -d= -f2)
    domain=$(echo "$state_info" | grep "^DOMAIN=" | cut -d= -f2)
    subagent=$(get_phase_subagent "$current_phase" "$project_type" "$complexity")
    model=$(get_phase_model "$feature_name" "$current_phase")
    test_command=$(get_test_command "$project_type")

    run_agent "$feature_name" "$current_phase" "$model" "$subagent" "$domain" "$project_type" "$test_command"

    next_phase=$("$(dirname "$0")/state.sh" next "$feature_name")
    checkpoint=$(check_and_handle_checkpoint "$feature_name" "$next_phase")

    if [ "$checkpoint" == "APPROVED" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  APPROVED Checkpoint"
        echo ""
        echo "  Plan 阶段完成，请审查 02-plan.md 后确认："
        echo "  → 运行: state.sh approve $feature_name"
        echo "  → 确认后: runner.sh continue $feature_name"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    fi

    if [ "$checkpoint" == "RELEASING" ]; then
        advance_phase "$feature_name"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  RELEASING Checkpoint"
        echo ""
        echo "  Verify 阶段完成，准备发布。"
        echo "  → 运行: state.sh release $feature_name"
        echo "  → 确认后: runner.sh continue $feature_name"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    fi

    advance_phase "$feature_name"

    new_phase=$(get_current_phase "$feature_name")
    if [ "$new_phase" != "DONE" ]; then
        echo ""
        echo "✅ Phase 转换完成 → $new_phase"
        echo "   继续运行: runner.sh continue $feature_name"
    else
        echo "✅ Pipeline 完成"
    fi
    exit 0
fi

if [ "$cmd" == "retry" ]; then
    result=$(handle_blocker "$feature_name" "$current_phase")
    if [[ "$result" == RETRY:* ]]; then
        attempt=$(echo "$result" | cut -d: -f2)
        echo "🔄 Retry $attempt/3 for $current_phase"
        echo "   继续运行: runner.sh continue $feature_name"
    else
        echo "❌ Max retries exceeded. Escalating to user."
    fi
    exit 0
fi

echo "Unknown command: $cmd"
echo "Usage: runner.sh <start|continue|status|test-cmd|retry> <feature-name>"

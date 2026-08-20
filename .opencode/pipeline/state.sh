#!/bin/bash
# Pipeline State Manager (Meow workflow)
# 用法: ./state.sh <command> [args]

WORKDIR="${WORKDIR:-.}"

PHASES=("spec" "plan" "craft" "verify" "deliver" "DONE")
PHASE_NAMES=("Spec" "Plan" "Craft" "Verify" "Deliver" "Done")

get_state_file() {
    echo "$WORKDIR/.opencode/works/$1/status.json"
}

init_work() {
    local feature_name="$1"
    local work_dir="$WORKDIR/.opencode/works/$feature_name"
    mkdir -p "$work_dir"

    cat > "$work_dir/status.json" <<EOF
{
  "id": "$feature_name",
  "feature": "$feature_name",
  "project_type": "backend",
  "complexity": "standard",
  "domain": "generic",
  "subagent": "coder",
  "model_tier": "mid-high",
  "confidence": "medium",
  "escalate": false,
  "status": "SPEC_STARTED",
  "phase": 0,
  "approved": false,
  "released": false,
  "path": [],
  "classifier_output": {},
  "model_override": {},
  "created_at": "$(date -Iseconds)",
  "updated_at": "$(date -Iseconds)",
  "phases": {
    "spec":    { "status": "pending", "handoff": "01-spec.md", "attempts": 0 },
    "plan":    { "status": "pending", "handoff": "02-plan.md", "attempts": 0 },
    "craft":   { "status": "pending", "handoff": "03-craft.md", "attempts": 0 },
    "verify":  { "status": "pending", "handoff": "04-verify.md", "attempts": 0 },
    "deliver": { "status": "pending", "handoff": "05-deliver.md", "attempts": 0 }
  },
  "escalations": [],
  "retry_limits": { "craft": 3, "verify": 3 }
}
EOF
    echo "✅ 工作目录已创建: $work_dir"
    echo "✅ 状态文件: $work_dir/status.json"
}

set_status() {
    local feature_name="$1"
    local status="$2"
    local phase="${3:-0}"
    local state_file
    state_file=$(get_state_file "$feature_name")

    if [ ! -f "$state_file" ]; then
        echo "❌ 状态文件不存在: $state_file"
        echo "   请先运行: state.sh init <feature-name>"
        return 1
    fi

    python3 - "$state_file" "$status" "$phase" <<'PYEOF'
import json, sys

state_file = sys.argv[1]
new_status = sys.argv[2]
new_phase = int(sys.argv[3])

with open(state_file, 'r') as f:
    state = json.load(f)

state['status'] = new_status
state['phase'] = new_phase
state['updated_at'] = str(__import__('datetime').datetime.now().astimezone())

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"✅ 状态已更新: {new_status} (Phase {new_phase})")
PYEOF
}

get_status() {
    local feature_name="$1"
    local state_file
    state_file=$(get_state_file "$feature_name")

    if [ ! -f "$state_file" ]; then
        echo "❌ 状态文件不存在: $state_file"
        return 1
    fi

    python3 - "$state_file" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
with open(state_file, 'r') as f:
    state = json.load(f)
phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
current = state.get('phase', 0)
phase_name = phases[current] if current < len(phases) else "DONE"
print(f"Feature:      {state['feature']}")
print(f"Status:       {state['status']}")
print(f"Phase:        {current}/5 ({phase_name})")
print(f"Project Type: {state.get('project_type', 'N/A')}")
print(f"Complexity:   {state.get('complexity', 'N/A')}")
print(f"Domain:       {state.get('domain', 'N/A')}")
print(f"Subagent:     {state.get('subagent', 'N/A')}")
print(f"Model Tier:   {state.get('model_tier', 'N/A')}")
print(f"Escalate:     {state.get('escalate', False)}")
print(f"Approved:     {state.get('approved', False)}")
print(f"Released:     {state.get('released', False)}")
print(f"Updated:      {state['updated_at']}")
PYEOF
}

list_works() {
    local works_dir="$WORKDIR/.opencode/works"
    if [ ! -d "$works_dir" ]; then
        echo "暂无工作目录"
        return
    fi

    echo "━━━ Meow Workflow Works ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for dir in "$works_dir"/*; do
        if [ -d "$dir" ]; then
            local name
            name=$(basename "$dir")
            local status="unknown"
            local phase=0
            local project_type="N/A"
            local complexity="N/A"
            if [ -f "$dir/status.json" ]; then
                status=$(python3 -c "import json; print(json.load(open('$dir/status.json'))['status'])" 2>/dev/null || echo "error")
                phase=$(python3 -c "import json; print(json.load(open('$dir/status.json'))['phase'])" 2>/dev/null || echo "0")
                project_type=$(python3 -c "import json; print(json.load(open('$dir/status.json')).get('project_type','N/A'))" 2>/dev/null || echo "N/A")
                complexity=$(python3 -c "import json; print(json.load(open('$dir/status.json')).get('complexity','N/A'))" 2>/dev/null || echo "N/A")
            fi
            echo "  $name  →  $status | $project_type/$complexity (Phase $phase/5)"
        fi
    done
}

show_phase_banner() {
    local phase="$1"
    local phase_name="$2"
    local description="${3:-}"

    printf '\n'
    printf '━━━━━━━━━━━━━━━━━━━━━━━━[ Phase %s/5: %s ]' "$phase" "$phase_name"
    printf '━%.0s' $(seq 1 $((50 - ${#phase_name} - ${#phase} - 20)))
    printf '\n'
    if [ -n "$description" ]; then
        echo "  $description"
    fi
    printf '\n'
}

get_phase_index() {
    local phase_name="$1"
    for i in "${!PHASES[@]}"; do
        if [ "${PHASES[$i]}" == "$phase_name" ]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
    return 1
}

next_phase() {
    local feature_name="$1"
    local state_file
    state_file=$(get_state_file "$feature_name")

    if [ ! -f "$state_file" ]; then
        echo "❌ 状态文件不存在"
        return 1
    fi

    python3 - "$state_file" <<'PYEOF'
import json, sys
state_file = sys.argv[1]
with open(state_file, 'r') as f:
    state = json.load(f)

phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
current_idx = state.get('phase', 0)

if current_idx >= len(phases) - 1:
    print("DONE")
else:
    next_phase = phases[current_idx + 1]
    print(next_phase)
PYEOF
}

check_checkpoint() {
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
# Skip for trivial and docs/blog/wiki projects
skip_approved = complexity == 'trivial' or project_type in ('docs', 'blog', 'wiki')
if next_phase == "craft" and current_phase == "plan" and not skip_approved:
    if not state.get('approved', False):
        print("APPROVED")
        sys.exit(0)

# RELEASING checkpoint: before Deliver commit (current=verify, next=deliver)
if next_phase == "deliver" and current_phase == "verify":
    if not state.get('released', False):
        print("RELEASING")
        sys.exit(0)

print("CONTINUE")
PYEOF
}

approve() {
    local feature_name="$1"
    local state_file
    state_file=$(get_state_file "$feature_name")

    if [ ! -f "$state_file" ]; then
        echo "❌ 状态文件不存在"
        return 1
    fi

    python3 - "$state_file" <<'PYEOF'
import json, sys, datetime
state_file = sys.argv[1]
with open(state_file, 'r') as f:
    state = json.load(f)

state['approved'] = True
state['phases']['plan']['status'] = 'completed'
state['updated_at'] = str(datetime.datetime.now().astimezone())

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print("✅ APPROVED 已确认，继续 pipeline")
PYEOF
}

release() {
    local feature_name="$1"
    local state_file
    state_file=$(get_state_file "$feature_name")

    if [ ! -f "$state_file" ]; then
        echo "❌ 状态文件不存在"
        return 1
    fi

    python3 - "$state_file" <<'PYEOF'
import json, sys, datetime
state_file = sys.argv[1]
with open(state_file, 'r') as f:
    state = json.load(f)

state['released'] = True
state['updated_at'] = str(datetime.datetime.now().astimezone())

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print("✅ RELEASING 已确认，执行 release")
PYEOF
}

update_phase() {
    local feature_name="$1"
    local new_phase="$2"
    local new_status="$3"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" "$new_phase" "$new_status" <<'PYEOF'
import json, sys, datetime
state_file = sys.argv[1]
new_phase = int(sys.argv[2])
new_status = sys.argv[3]

with open(state_file, 'r') as f:
    state = json.load(f)

phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
if new_phase < len(phases):
    phase_name = phases[new_phase]
    if phase_name != "DONE":
        state['phases'][phase_name]['status'] = new_status
state['phase'] = new_phase
state['status'] = new_status
state['updated_at'] = str(datetime.datetime.now().astimezone())

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Phase {new_phase}: {phases[new_phase]} → {new_status}")
PYEOF
}

increment_attempts() {
    local feature_name="$1"
    local phase="$2"
    local state_file
    state_file=$(get_state_file "$feature_name")

    python3 - "$state_file" "$phase" <<'PYEOF'
import json, sys, datetime
state_file = sys.argv[1]
phase = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

state['phases'][phase]['attempts'] = state['phases'][phase].get('attempts', 0) + 1
state['updated_at'] = str(datetime.datetime.now().astimezone())

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"✅ {phase} attempts incremented")
PYEOF
}

save_classifier_output() {
    local feature_name="$1"
    local json_file="$2"
    local state_file
    state_file=$(get_state_file "$feature_name")

    if [ ! -f "$json_file" ]; then
        echo "❌ JSON 文件不存在: $json_file"
        return 1
    fi

    python3 - "$state_file" "$json_file" <<'PYEOF'
import json, sys, datetime
state_file = sys.argv[1]
json_file = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

with open(json_file, 'r') as f:
    classifier_input = f.read().strip()

if not classifier_input:
    print("❌ classifier JSON 文件为空")
    sys.exit(1)

try:
    classifier = json.loads(classifier_input)
except json.JSONDecodeError as e:
    print(f"❌ classifier 输出不是有效 JSON: {e}")
    sys.exit(1)

state['project_type'] = classifier.get('project_type', 'backend')
state['complexity'] = classifier.get('complexity', 'standard')
state['domain'] = classifier.get('domain', 'generic')
state['subagent'] = classifier.get('subagent', 'coder')
state['model_tier'] = classifier.get('model_tier', 'mid-high')
state['confidence'] = classifier.get('confidence', 'medium')
state['escalate'] = classifier.get('escalate', False)
state['path'] = classifier.get('path', [])
state['classifier_output'] = classifier
state['updated_at'] = str(datetime.datetime.now().astimezone())

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"✅ 分类已保存: {state['project_type']} | {state['complexity']} | {state['domain']} | escalate={state['escalate']}")
PYEOF
}

case "$1" in
    init)
        init_work "$2"
        ;;
    status)
        get_status "$2"
        ;;
    set)
        set_status "$2" "$3" "$4"
        ;;
    list)
        list_works
        ;;
    banner)
        show_phase_banner "$2" "$3" "$4"
        ;;
    next)
        next_phase "$2"
        ;;
    auto)
        feature_name="$2"
        state_file=$(get_state_file "$feature_name")

        if [ ! -f "$state_file" ]; then
            echo "❌ 状态文件不存在: $state_file"
            exit 1
        fi

        current_phase=$(python3 - "$state_file" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    state = json.load(f)
phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
idx = state.get('phase', 0)
print(phases[idx] if idx < len(phases) else "DONE")
PYEOF
)

        if [ "$current_phase" == "DONE" ]; then
            echo "✅ Pipeline 已完成"
            exit 0
        fi

        next=$(next_phase "$feature_name")
        checkpoint=$(check_checkpoint "$feature_name" "$next")

        if [ "$checkpoint" == "APPROVED" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚠️  APPROVED Checkpoint — 需要你确认"
            echo ""
            echo "  Plan 阶段已完成，请审查 02-plan.md 后确认："
            echo "  运行: state.sh approve $feature_name"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 0
        fi

        if [ "$checkpoint" == "RELEASING" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚠️  RELEASING Checkpoint — 需要你确认"
            echo ""
            echo "  Verify 阶段已完成，准备发布："
            echo "  运行: state.sh release $feature_name"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 0
        fi

        phase_idx=$(get_phase_index "$current_phase")

        # Skip Plan for trivial or docs/blog/wiki projects
        project_type=$(python3 - "$state_file" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    state = json.load(f)
print(state.get('project_type', 'backend'))
PYEOF
)
        complexity=$(python3 - "$state_file" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    state = json.load(f)
print(state.get('complexity', 'standard'))
PYEOF
)

        if [ "$current_phase" == "spec" ] && { [ "$complexity" == "trivial" ] || [ "$project_type" == "docs" ] || [ "$project_type" == "blog" ] || [ "$project_type" == "wiki" ]; }; then
            new_idx=2  # craft
            # Mark plan as skipped
            python3 - "$state_file" <<'PYEOF'
import json, sys, datetime
state_file = sys.argv[1]
with open(state_file, 'r') as f:
    state = json.load(f)
state['phases']['plan']['status'] = 'skipped'
state['updated_at'] = str(datetime.datetime.now().astimezone())
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PYEOF
        else
            new_idx=$((phase_idx + 1))
        fi

        update_phase "$feature_name" "$new_idx" "RUNNING"
        echo "✅ 自动流转: $current_phase → ${PHASES[$new_idx]}"
        ;;
    approve)
        feature_name="$2"
        state_file=$(get_state_file "$feature_name")

        if [ ! -f "$state_file" ]; then
            echo "❌ 状态文件不存在"
            exit 1
        fi

        current_phase=$(python3 - "$state_file" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    state = json.load(f)
phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
idx = state.get('phase', 0)
print(phases[idx] if idx < len(phases) else "DONE")
PYEOF
)

        if [ "$current_phase" != "plan" ]; then
            echo "⚠️  当前不是 plan 阶段，无法 approve"
            exit 1
        fi

        approve "$feature_name"
        phase_idx=$(get_phase_index "plan")
        new_idx=$((phase_idx + 1))
        update_phase "$feature_name" "$new_idx" "RUNNING"
        echo "✅ 已批准，自动流转: plan → craft"
        ;;
    release)
        feature_name="$2"
        state_file=$(get_state_file "$feature_name")

        if [ ! -f "$state_file" ]; then
            echo "❌ 状态文件不存在"
            exit 1
        fi

        current_phase=$(python3 - "$state_file" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    state = json.load(f)
phases = ["spec", "plan", "craft", "verify", "deliver", "DONE"]
idx = state.get('phase', 0)
print(phases[idx] if idx < len(phases) else "DONE")
PYEOF
)

        if [ "$current_phase" != "verify" ]; then
            echo "⚠️  当前不是 verify 阶段，无法 release"
            exit 1
        fi

        release "$feature_name"
        phase_idx=$(get_phase_index "verify")
        new_idx=$((phase_idx + 1))
        update_phase "$feature_name" "$new_idx" "RUNNING"
        echo "✅ 已发布确认，自动流转: verify → deliver"
        ;;
    retry)
        increment_attempts "$2" "$3"
        ;;
    save-classifier)
        save_classifier_output "$2" "$3"
        ;;
    *)
        echo "Usage: state.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init <feature-name>              初始化新 feature 工作目录"
        echo "  status <feature-name>            查看当前状态"
        echo "  set <feature-name> <status> [phase]  设置状态"
        echo "  list                             列出所有 works"
        echo "  banner <phase> <name> [desc]     显示阶段横幅"
        echo "  next <feature-name>              查看下一个 phase"
        echo "  auto <feature-name>              自动流转到下一个 phase"
        echo "  approve <feature-name>           确认 APPROVED，继续 pipeline"
        echo "  release <feature-name>           确认 RELEASING，执行交付"
        echo "  retry <feature-name> <phase>     增加 phase 重试次数"
        echo "  save-classifier <feature-name> <json-file>  从文件读取 classifier JSON 并保存"
        echo ""
        ;;
esac

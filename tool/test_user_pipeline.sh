#!/usr/bin/env bash

set -u

MODE="full"
REPORT_DIR="docs/testing/reports"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
REPORT_FILE="${REPORT_DIR}/user_pipeline_report_${TIMESTAMP}.md"
ENV_FILE="${SN_TEST_ENV_FILE:-.env.integration}"

TOTAL_STEPS=0
PASSED_STEPS=0
FAILED_STEPS=0
SKIPPED_STEPS=0
RESULT_ROWS=""
OVERALL_STATUS="PASS"
LAST_STEP_STATUS="PASS"

usage() {
  cat <<'EOF'
Usage:
  ./tool/test_user_pipeline.sh [--fast | --server | --full]

Modes:
  --fast    Run local ordered pipeline (unit + widget) only.
  --server  Run live-server ordered pipeline only.
  --full    Run both local and live-server pipelines (default).

Notes:
  - Server mode requires SN_TEST_BASE_URL, SN_TEST_DEVICE_ID, SN_TEST_DEVICE_TOKEN.
  - Values are resolved from process env first, then SN_TEST_ENV_FILE/.env.integration.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast)
      MODE="fast"
      shift
      ;;
    --server)
      MODE="server"
      shift
      ;;
    --full)
      MODE="full"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

lookup_from_file() {
  local key="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi

  local line
  while IFS= read -r line; do
    case "$line" in
      "${key}="*)
        echo "${line#${key}=}"
        return
        ;;
      *)
        ;;
    esac
  done < "$file"
  echo ""
}

resolve_env() {
  local key="$1"
  local process_value="${!key:-}"
  if [[ -n "$process_value" ]]; then
    echo "$process_value"
    return
  fi
  lookup_from_file "$key" "$ENV_FILE"
}

add_row() {
  local step_name="$1"
  local status="$2"
  local duration="$3"
  local command="$4"
  RESULT_ROWS="${RESULT_ROWS}
| ${step_name} | ${status} | ${duration}s | \`${command}\` |"
}

run_step() {
  local step_name="$1"
  local command="$2"
  TOTAL_STEPS=$((TOTAL_STEPS + 1))

  echo ""
  echo "==> ${step_name}"
  echo "    ${command}"

  local start_ts
  start_ts="$(date +%s)"

  if bash -lc "$command"; then
    local end_ts
    end_ts="$(date +%s)"
    local duration=$((end_ts - start_ts))
    PASSED_STEPS=$((PASSED_STEPS + 1))
    add_row "$step_name" "PASS" "$duration" "$command"
    LAST_STEP_STATUS="PASS"
  else
    local end_ts
    end_ts="$(date +%s)"
    local duration=$((end_ts - start_ts))
    FAILED_STEPS=$((FAILED_STEPS + 1))
    OVERALL_STATUS="FAIL"
    add_row "$step_name" "FAIL" "$duration" "$command"
    LAST_STEP_STATUS="FAIL"
  fi
}

run_step_if() {
  local should_run="$1"
  local step_name="$2"
  local command="$3"

  if [[ "$should_run" == "1" ]]; then
    run_step "$step_name" "$command"
  else
    TOTAL_STEPS=$((TOTAL_STEPS + 1))
    SKIPPED_STEPS=$((SKIPPED_STEPS + 1))
    add_row "$step_name" "SKIP" "0" "$command"
  fi
}

mkdir -p "$REPORT_DIR"

RUN_FAST=0
RUN_SERVER=0
if [[ "$MODE" == "fast" ]]; then
  RUN_FAST=1
fi
if [[ "$MODE" == "server" ]]; then
  RUN_SERVER=1
fi
if [[ "$MODE" == "full" ]]; then
  RUN_FAST=1
  RUN_SERVER=1
fi

SERVER_READY=1
SERVER_BASE_URL=""
SERVER_DEVICE_ID=""
SERVER_DEVICE_TOKEN=""
if [[ "$RUN_SERVER" == "1" ]]; then
  SERVER_BASE_URL="$(resolve_env SN_TEST_BASE_URL)"
  SERVER_DEVICE_ID="$(resolve_env SN_TEST_DEVICE_ID)"
  SERVER_DEVICE_TOKEN="$(resolve_env SN_TEST_DEVICE_TOKEN)"
  if [[ -z "$SERVER_BASE_URL" || -z "$SERVER_DEVICE_ID" || -z "$SERVER_DEVICE_TOKEN" ]]; then
    SERVER_READY=0
    OVERALL_STATUS="FAIL"
  fi
fi

if [[ "$RUN_FAST" == "1" ]]; then
  run_step "Pipeline 01 - Device Registration Gate" "flutter test test/app/unit/repositories/device/device_repository_impl_test.dart --reporter compact"
  run_step "Pipeline 02 - Create Book (server UUID source of truth)" "flutter test test/app/unit/repositories/book/book_repository_impl_create_test.dart --reporter compact"
  run_step "Pipeline 03 - Read/Archive/Delete Book" "flutter test test/app/unit/repositories/book/book_repository_impl_read_test.dart test/app/unit/repositories/book/book_repository_impl_write_test.dart --reporter compact"
  run_step "Pipeline 04 - Rename/Reorder/Server Import Guards" "flutter test test/app/unit/repositories/book/book_repository_impl_update_test.dart test/app/unit/repositories/book/book_repository_impl_server_test.dart test/app/unit/services/book/book_order_service_test.dart --reporter compact"
  run_step "Pipeline 05 - Create/Update/Delete/Reschedule Event" "flutter test test/app/unit/repositories/event/event_repository_impl_write_test.dart --reporter compact"
  run_step "Pipeline 06 - Event Query/Sync Apply" "flutter test test/app/unit/repositories/event/event_repository_impl_read_test.dart test/app/unit/repositories/event/event_repository_impl_sync_test.dart --reporter compact"
  run_step "Pipeline 07 - Note Save/Load/Sync Apply" "flutter test test/app/unit/repositories/note/note_repository_impl_test.dart --reporter compact"
  run_step "Pipeline 08 - Drawing Save/Load/Update/Clear" "flutter test test/app/unit/repositories/drawing/drawing_repository_impl_test.dart test/app/unit/utils/schedule/schedule_layout_utils_test.dart --reporter compact"
  run_step "Pipeline 09 - Event Detail Trigger -> Server -> Return -> Update" "flutter test test/app/unit/controllers/event_detail_controller_test.dart --reporter compact"
  run_step "Pipeline 10 - App Bootstrap & Setup Widget Paths" "flutter test test/widget_test.dart test/app/widget/app_bootstrap_setup_test.dart --reporter compact"
fi

if [[ "$RUN_SERVER" == "1" ]]; then
  if [[ "$SERVER_READY" == "1" ]]; then
    run_step "Pipeline 11 - Live Fixture Provision (create book -> create event)" "dart run tool/create_event_metadata_fixture.dart"
    if [[ "$LAST_STEP_STATUS" == "PASS" ]]; then
      run_step "Pipeline 12 - Live Event Metadata Roundtrip" "flutter test test/app/integration/event_metadata_server_smoke_test.dart --reporter compact"
    else
      run_step_if "0" "Pipeline 12 - Live Event Metadata Roundtrip" "flutter test test/app/integration/event_metadata_server_smoke_test.dart --reporter compact"
    fi
  else
    TOTAL_STEPS=$((TOTAL_STEPS + 1))
    FAILED_STEPS=$((FAILED_STEPS + 1))
    add_row "Pipeline 11 - Live Fixture Provision (create book -> create event)" "FAIL" "0" "Missing SN_TEST_BASE_URL/SN_TEST_DEVICE_ID/SN_TEST_DEVICE_TOKEN in env or ${ENV_FILE}"
    TOTAL_STEPS=$((TOTAL_STEPS + 1))
    SKIPPED_STEPS=$((SKIPPED_STEPS + 1))
    add_row "Pipeline 12 - Live Event Metadata Roundtrip" "SKIP" "0" "flutter test test/app/integration/event_metadata_server_smoke_test.dart --reporter compact"
  fi
fi

if [[ "$FAILED_STEPS" -gt 0 ]]; then
  OVERALL_STATUS="FAIL"
fi

cat > "$REPORT_FILE" <<EOF
# User Pipeline Automation Report

Date: $(date '+%Y-%m-%d %H:%M:%S %Z')
Mode: \`${MODE}\`
Overall Status: **${OVERALL_STATUS}**
Report Path: \`${REPORT_FILE}\`
Checklist Source: \`docs/testing/physical_device_test_checklist.md\`

## Execution Summary

- Total steps: ${TOTAL_STEPS}
- Passed: ${PASSED_STEPS}
- Failed: ${FAILED_STEPS}
- Skipped: ${SKIPPED_STEPS}
- Server env file: \`${ENV_FILE}\`

## Ordered Pipeline Results

| Step | Status | Duration | Command |
|---|---|---:|---|${RESULT_ROWS}

## Checklist Coverage Mapping (Automate Everything Possible)

| Checklist Section | Automation Status | Coverage Notes |
|---|---|---|
| 1. App Launch & Setup | Partial | Automated: device credential persistence + app bootstrap widget (\`test/widget_test.dart\`, device repository tests). Manual-only: physical install/uninstall and real setup UI navigation. |
| 2. Book Behavior | High (Partial) | Automated: create/blank-name validation, rename trim, archive visibility, delete, reorder persistence logic, server import + duplicate guard. Manual-only: physical drag/drop gesture feel. |
| 3. Event Behavior | High (Partial) | Automated: create/edit/remove/reschedule/delete/query/sync-upsert via event repository + controller flow tests. Manual-only: full schedule screen rendering across day/week on physical device. |
| 4. Note Behavior | Partial | Automated: record-shared note semantics, save/update/delete/batch/sync apply + event-detail save flow + has-note indicator scope (only events that actually edit note show note tag). Manual-only: handwriting UX validation on real touch device. |
| 5. Drawing Behavior | Partial | Automated: save/update/load/clear/range preload/batch semantics plus 2-day page/window mapping regression checks (no previous-page leakage) in drawing and schedule layout utility tests. Manual-only: canvas interaction smoothness and visual fidelity on device. |
| 6. Device Credentials & Session | Partial | Automated: save/get/replace credential behavior. Manual-only: repeated relaunch behavior on actual installed app binary. |
| 7. Offline / Online Connectivity | Partial | Automated: server sync failure path and live metadata roundtrip (\`event_metadata_server_smoke_test.dart\`) when server env configured. Manual-only: airplane-mode OS-level toggling and UX messaging. |
| 8. Performance Sanity (Manual) | Manual-only | Not automatable in current unit/integration test stack; requires physical profiling and user-perceived latency checks. |

## Manual-Only Items (Explicit)

- Fresh install/uninstall and physical setup journey.
- Real touch interactions for schedule/note/drawing gestures.
- Airplane mode toggling and reconnect behavior on actual device network stack.
- Performance/fps/input latency validation on target hardware.
EOF

echo ""
echo "Pipeline finished with status: ${OVERALL_STATUS}"
echo "Markdown report: ${REPORT_FILE}"

# Keep checklist auto-test column in sync with the latest pipeline result.
dart run tool/update_checklist_auto_status.dart --report "${REPORT_FILE}" >/dev/null 2>&1 || true

if [[ "$OVERALL_STATUS" == "FAIL" ]]; then
  exit 1
fi

exit 0

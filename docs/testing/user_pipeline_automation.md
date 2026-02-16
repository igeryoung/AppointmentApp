# User Pipeline Automation

This automation is based on `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/physical_device_test_checklist.md` and executes test steps in user-flow order.

## Command

```bash
./tool/test_user_pipeline.sh --fast
./tool/test_user_pipeline.sh --server
./tool/test_user_pipeline.sh --full
```

Default mode is `--full`.

## Phase Modes

- `--fast`: local ordered pipeline only (unit + widget), no live server dependency.
- `--server`: live-server pipeline only.
- `--full`: `--fast` + `--server`.

## Enforced Order (Data Dependency)

1. Device registration gate.
2. Book creation and book management.
3. Event creation/update/remove/delete/reschedule.
   - Includes no-record-number reschedule note continuity coverage (old/new event should resolve same note).
   - Includes no-record-number refill coverage (reenter + fill record number keeps note and updates event metadata).
4. Note behaviors.
   - Includes has-note indicator scope coverage: events that only load shared existing note without note edits must keep note tag off.
5. Drawing behaviors.
6. Event-detail trigger -> server -> return -> update.
7. App bootstrap widget path.
8. Live fixture provision (`create book -> create event`).
9. Live server metadata roundtrip verification.

## Live Server Requirements

For `--server` and `--full`, these variables are required:

- `SN_TEST_BASE_URL`
- `SN_TEST_DEVICE_ID`
- `SN_TEST_DEVICE_TOKEN`

Resolution order:
1. process environment
2. `SN_TEST_ENV_FILE`
3. `.env.integration`

If missing, pipeline fails by design.

## Report Output

Each run writes a markdown report to:

- `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/reports/user_pipeline_report_<timestamp>.md`

Report includes:

- ordered step pass/fail table
- checklist coverage mapping
- explicit manual-only items

After each run, the script also updates:

- `/Users/yangping/Studio/side-project/scheduleNote/docs/testing/physical_device_test_checklist.md`

It fills the `Auto Test` column with:

- `[V]` when mapped pipeline steps pass
- `[ ]` otherwise (including manual-only rows)

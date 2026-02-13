# Device Pilot Case Matrix

| Case ID | Test Purpose | Real App Scenario | Workflow Position | Expected Result | Mapped Test |
|---|---|---|---|---|---|
| DEVICE-UNIT-001 | verify empty credentials behavior | app checks registration state on startup | WF-DEVICE-01 | null returned when no device row exists | `test/app/unit/repositories/device/device_repository_impl_test.dart` |
| DEVICE-UNIT-002 | verify save/get credential flow | setup saves device credentials | WF-DEVICE-02 | saved credentials are returned unchanged | `test/app/unit/repositories/device/device_repository_impl_test.dart` |
| DEVICE-UNIT-003 | verify replacement semantics | setup re-saves credentials after re-registration | WF-DEVICE-03 | old row replaced and only latest credentials remain | `test/app/unit/repositories/device/device_repository_impl_test.dart` |

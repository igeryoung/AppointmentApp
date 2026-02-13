# App Workflow Scenarios (Device)

## WF-DEVICE-01 Read Credentials
- Real case: app startup checks if device is registered.
- Purpose: ensure empty state returns null credentials.

## WF-DEVICE-02 Save Credentials
- Real case: server setup saves device registration values.
- Purpose: ensure saved credentials are persisted and readable.

## WF-DEVICE-03 Replace Credentials
- Real case: re-registration overwrites existing local credentials.
- Purpose: ensure single-row replacement semantics remain stable.

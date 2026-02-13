# App Workflow Scenarios (Drawing)

## WF-DRAWING-01 Load Drawing Overlay
- Real case: user opens schedule day/3-day view and existing strokes load.
- Purpose: ensure cached drawing retrieval uses normalized date matching.

## WF-DRAWING-02 Save Drawing Overlay
- Real case: user draws strokes and auto-save runs.
- Purpose: ensure save writes and update-in-place behavior.

## WF-DRAWING-03 Clear Drawing Cache
- Real case: user clears drawing for a day/view.
- Purpose: ensure delete removes the matching cache row.

## WF-DRAWING-04 Preload Drawing Range
- Real case: app preloads drawings for upcoming range.
- Purpose: ensure date-range and view-mode filtering are correct.

## WF-DRAWING-05 Batch Persist Drawings
- Real case: app saves multiple drawings during state flush.
- Purpose: ensure batch write handles insert and update consistently.

# App Workflow Scenarios (Book)

## WF-BOOK-01 Create Book
- Real case: user taps `+` in Book List, enters book name, confirms.
- Purpose: ensure local book row is created only after server UUID is returned.

## WF-BOOK-02 Create Book (Unregistered Device)
- Real case: user tries creating book before device registration/setup is complete.
- Purpose: prevent invalid local state when credentials are missing.

## WF-BOOK-03 View Book List
- Real case: user opens app and sees active books.
- Purpose: ensure archived books are excluded in default listing.

## WF-BOOK-04 Archive Book
- Real case: user archives an old book from book menu.
- Purpose: ensure archived book is hidden from active list but still exists in DB.

## WF-BOOK-05 Reorder Books
- Real case: user drags book cards to set preferred order.
- Purpose: ensure saved order is applied and new books appear at top when not yet in saved order.

## WF-BOOK-06 Rename Book
- Real case: user renames a book from book menu.
- Purpose: ensure name is trimmed, persisted, and missing targets are rejected.

## WF-BOOK-07 Import Book From Server
- Real case: user opens import dialog, searches server books, and pulls one to local.
- Purpose: ensure credential checks, server query forwarding, duplicate-local prevention, and valid pull persistence.

## WF-BOOK-08 Check Server Book Info
- Real case: user checks if a server book is still available before import.
- Purpose: ensure 404 returns a safe null result instead of crashing the workflow.

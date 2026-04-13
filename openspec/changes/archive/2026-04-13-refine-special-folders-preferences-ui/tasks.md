## 1. Refactor the editor layout

- [x] 1.1 Replace the stack-based Special Folders editor body with a padded list container built on `NSScrollView` and `NSTableView`
- [x] 1.2 Add lower-left `+` and `-` controls, wire the add flow to `NSOpenPanel`, and disable the remove control when no rows are selected
- [x] 1.3 Keep disposition editing available per row in the new list presentation and preserve save-on-change behavior

## 2. Add list interactions

- [x] 2.1 Implement multi-row selection and delete the current selection from the `-` control
- [x] 2.2 Add a context menu delete action that respects multi-selection and updates selection correctly on right-click
- [x] 2.3 Implement drag-and-drop row reordering and persist the updated rule order
- [x] 2.4 Enable alternating row backgrounds and keep the empty state presentation consistent when the list has no rows

## 3. Verify behavior

- [x] 3.1 Update or extend debug helpers and UI tests to cover adding, multi-select deletion, context-menu deletion, and reorder persistence
- [x] 3.2 Run the relevant test targets or focused verification steps for the Search preferences Special Folders editor

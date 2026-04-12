## 1. Grid Alignment Fix

- [x] 1.1 Update grid item title rendering so attributed filenames keep centered paragraph styling in grid mode only
- [x] 1.2 Preserve the existing preview-size sizing math, two-line limit, and middle truncation while applying the alignment fix

## 2. Regression Coverage

- [x] 2.1 Add DEBUG inspection helpers needed to measure grid icon/title horizontal alignment in tests
- [x] 2.2 Extend search-results tests to verify grid alignment at multiple preview sizes and with a long highlighted filename

## 3. Verification

- [x] 3.1 Run the targeted search-results test suite and confirm the new grid alignment coverage passes

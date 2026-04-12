## ADDED Requirements

### Requirement: The app SHALL keep grid result captions centered under previews

The system SHALL keep each grid result item's filename block horizontally centered with its preview icon when the user changes preview size. The system SHALL preserve the current two-line title limit and middle-truncation behavior while applying the updated grid alignment.

#### Scenario: Increase preview size without shifting the caption off center
- **WHEN** the user increases the grid preview size from the default value to a larger supported value
- **THEN** each grid item keeps its filename block horizontally centered with the preview icon

#### Scenario: Reduce preview size without changing title behavior
- **WHEN** the user decreases the grid preview size to a smaller supported value
- **THEN** each grid item still keeps its filename block horizontally centered with the preview icon and continues to display at most two truncated-middle lines

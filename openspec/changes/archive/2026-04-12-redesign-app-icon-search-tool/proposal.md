## Why

FileHound now has enough product shape that the placeholder-style app icon has become a visible quality gap. Before the app ships publicly, it needs a more intentional macOS icon that clearly reads as a sharp file-search tool instead of a generic utility.

## What Changes

- Redesign the macOS AppIcon around a search-forward, tool-sharp visual direction with a clearly readable magnifier.
- Replace every raster in `FileHound/Assets.xcassets/AppIcon.appiconset` while keeping the existing asset-slot structure intact.
- Validate that the icon remains recognizable across the standard macOS app-icon sizes, especially the smallest slots used in Finder and the Dock.

## Capabilities

### New Capabilities
- `app-icon-branding`: define and ship a search-focused FileHound app icon set for the macOS asset catalog.

### Modified Capabilities
None.

## Impact

- Affected assets live in `FileHound/Assets.xcassets/AppIcon.appiconset`.
- Implementation may use local image-generation or export tooling, but the checked-in output remains the raster icon set already referenced by Xcode.
- Verification needs both asset-catalog/build validation and manual review of small-size legibility.

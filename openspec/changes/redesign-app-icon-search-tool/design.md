## Context

FileHound currently ships with a valid macOS app-icon set, but it does not yet communicate a strong product identity. The approved direction is explicit: the icon must feel search-forward, sharper and more professional than a generic consumer utility, and it must contain an obvious magnifier rather than relying on abstract branding alone.

The existing asset-catalog integration is already correct, so this change should focus on replacing the icon artwork, not redesigning Xcode asset-slot wiring. Because macOS surfaces the same icon at very different sizes, the design also needs an explicit simplification strategy for the smallest slots.

## Goals / Non-Goals

**Goals:**
- Ship a new macOS AppIcon set that clearly reads as a professional file-search tool.
- Keep an obvious magnifier as the primary visual anchor.
- Preserve recognition from 16x16 through 1024x1024 while keeping the current asset-catalog structure.

**Non-Goals:**
- Reworking in-app UI colors, typography, or brand guidelines beyond the icon itself.
- Changing the `AccentColor` asset or runtime theme behavior.
- Extending this change to DMG background art, release-marketing graphics, or other non-icon visuals.

## Decisions

### 1. Use a "sharp magnifier + file hit slice" composition

The icon should combine a hard-edged magnifier with a file/result structure visible inside the lens. That gives FileHound an immediate "search files" reading instead of a more generic "search anything" look.

Why this decision:
- The user explicitly wants a visible magnifier.
- Adding a file/result slice inside the lens keeps the icon tied to desktop file search instead of web-search metaphors.
- This direction preserves strong semantic clarity even before a user has seen the product.

Alternatives considered:
- A path/tree-search icon based on folder hierarchy lines.
  - Rejected because it is more abstract at small sizes and weaker at first-glance recognition.
- A mascot-like or brand-symbol treatment tied to "hound" metaphors.
  - Rejected because it weakens the direct search-tool reading and adds unnecessary branding abstraction for the current stage.

### 2. Keep the current AppIcon asset structure and replace only the raster payloads

The implementation should keep `AppIcon.appiconset/Contents.json` intact and replace the referenced PNG files with the new artwork exports.

Why this decision:
- The existing asset-catalog wiring is already valid for macOS.
- This minimizes Xcode integration risk and keeps the change focused on the visual asset itself.

Alternative considered:
- Rebuild the asset set or file naming from scratch.
  - Rejected because it provides no product benefit and creates avoidable integration churn.

### 3. Design from a high-resolution master and export downward

Implementation should establish a single high-resolution master image first, then export the required icon sizes from that source while checking for small-size legibility.

Why this decision:
- It keeps the artwork consistent across all slots.
- It makes future refinements cheaper than hand-editing every raster independently.

Alternative considered:
- Tune or repaint every slot separately.
  - Rejected because it is slower, harder to keep consistent, and unnecessary for this scope.

## Risks / Trade-offs

- [Small icon slots can lose the file-search story] -> Simplify aggressively for 16/32 px and preserve only the base plate, magnifier silhouette, and one high-contrast hit detail.
- [The icon could drift too close to Spotlight] -> Avoid Spotlight's typical black/rainbow treatment and keep FileHound on a colder, sharper utility palette.
- [A detailed master can export poorly to low resolutions] -> Review the generated small slots directly and, if needed, make targeted export adjustments before replacing the checked-in files.

## Migration Plan

1. Produce and review the new master icon in the approved direction.
2. Export all required AppIcon rasters and replace the files in `FileHound/Assets.xcassets/AppIcon.appiconset`.
3. Build the app to confirm the asset catalog stays valid, then manually review the icon at small and large sizes.

Rollback strategy:
- Restore the previous icon rasters in `AppIcon.appiconset`; no code or data migration is involved.

## Open Questions

None.

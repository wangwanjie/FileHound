## 1. Icon Design

- [ ] 1.1 Produce a high-resolution master icon in the approved "sharp magnifier + file hit slice" direction
- [ ] 1.2 Review the master against the required visual constraints: search-forward, tool-sharp, and obvious magnifier

## 2. Asset Replacement

- [ ] 2.1 Export the required macOS AppIcon raster sizes from the approved master artwork
- [ ] 2.2 Replace the existing files in `FileHound/Assets.xcassets/AppIcon.appiconset` without changing the current asset-slot structure

## 3. Verification

- [ ] 3.1 Build the app and confirm the asset catalog reports no missing AppIcon warnings
- [ ] 3.2 Manually review the replaced icon at small and large macOS sizes for recognizability

# Appearance review — 10 September 2026

## Direction and plan

Use a quiet neutral canvas, white content surfaces, graphite secondary text, and one accessible blue action color in Light Mode. Keep the existing Dark Mode surfaces, map motion, navigation, source media, and persistence behavior. Premium here means clear hierarchy and legibility, not extra decoration.

Reviewed the live view implementations for Memories/search/empty states, the capture dial and all capture sheets, image/video/audio/note/link/PDF details and editors, AI Help and its source/answer states, Project Timeline/map/focus preview/River/history/source/evidence/archive, Settings/appearance, collections/tags/membership, Privacy & AI, and the Share Extension. Camera, Photos, Files, Quick Look, native video controls, alerts, and the share composer are system-owned surfaces and remain native.

Apple references:

- [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/): grouping and hierarchy carry emphasis; avoid unnecessary custom bar decoration.
- [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/): glass belongs primarily to the floating control/navigation layer; avoid glass-on-glass and tint only meaningful actions.

Implementation plan:

1. Introduce shared adaptive color roles and small content-surface modifiers, retaining native typography, material adaptation, and dark semantic colors.
2. Memories: white cards against a neutral canvas, thin quiet edges and restrained elevation, neutral loading placeholders; leave actual photos/videos untouched.
3. Map: a pale silver-gray field, pearl-white circles with subtle lower shading and movement-driven reflection; focus through size, brightness, and a clearer rim. No grid/gesture changes.
4. Timeline/River: consistent inset grouping, quieter metadata, and a continuous slate rail with blue junctions. Keep existing River alignment and navigation.
5. Details/capture: near-white reading/writing surfaces, white editor fields, neutral tags/media containers; preserve immersive photo/video contrast.
6. AI Help: consistent suggestions, source cards, and composer; accessible blue user bubbles; neutral assistant answers.
7. Settings/organization/privacy/archive: coherent grouped surfaces and neutral decorative icons, with readable semantic success/warning/error colors.
8. Verify screenshots and navigation in Light and Dark Mode, contrast roles in normal/increased-contrast traits, and existing motion/media regressions. No external AI calls or personal-library mutations for visual testing.

## Implementation

`RememberAppearance.swift` owns the color roles and the `rememberCanvas`, `rememberCard`, and `rememberGroupedList` modifiers. Light colors are an app-specific interpretation of the principles above, not an official Apple palette. Dynamic UIKit colors preserve native dark/elevated trait resolution and provide darker Increased Contrast variants. Cards increase border strength with Increased Contrast. Actual source images, video surfaces, system navigation, and dark map lighting remain unchanged.

The map's light circles have an opaque pearl base for reliable text contrast, subtle lower shading, and the same position-driven reflection as before. No timer, sensor, external dependency, grid-coordinate change, or new navigation step was added. Standard materials remain confined to the existing appropriate surfaces; Liquid Glass is not applied to content cards.

Changed UI files: `ContentView.swift`, `ProjectView.swift`, `ProjectGraphView.swift`, `ProjectGraphLighting.swift`, `ProvenanceViews.swift`, `MemoryDetailView.swift`, `RiverMediaView.swift`, `AudioMemoryPlayerView.swift`, `LocalImageView.swift`, `LocalVideoPlayerView.swift`, `InAppCaptureViews.swift`, `VoiceCaptureView.swift`, `AskRememberView.swift`, `SettingsView.swift`, `OrganizeView.swift`, and `PrivacyDashboardView.swift`. Added shared `RememberAppearance.swift`, `AppearanceTests.swift`, and `AppearanceReviewUITests.swift`; updated this document and `readme.md`.

| Role | Light appearance | Dark appearance |
| --- | --- | --- |
| Canvas | `#F3F4F6` | Existing system/grouped background per screen |
| Reading/writing | `#FCFCFD` | System background |
| Content card | `#FFFFFF` | Existing semantic card fill |
| Inset/tag | `#E9EDF2` | Existing tertiary/tinted fill as appropriate |
| Secondary text | `#515C6C` | Secondary label |
| Action | `#005EBF` | System blue |
| Success / warning / error | `#216E47` / `#805214` / `#BD2838` | System green / orange / red |
| Map field / lower shading | `#E7ECF2` / `#D4DDE8` | Existing graphite treatment |

Opaque user-message bubbles use a separate deeper blue fill so white text has sufficient contrast in both modes. The full-screen assistant inherits the app tint, while decorative privacy icons and the thread-options glyph use neutral foregrounds. Secondary text across the custom screens uses the shared readable role; native list headers, disabled controls, system media controls, and placeholders retain their system styling.

## Validation

Completed on 10 September 2026:

| Check | Result |
| --- | --- |
| Full unit suite, including adaptive-palette/contrast tests | 107 tests in 7 suites passed |
| Simulator Light and Dark appearance tours | Both passed; 21 screenshot checkpoints per appearance |
| Simulator interaction regressions | 4 passed: bidirectional dial drag, accessibility text size, Photos video import/inline River playback, and three-surface/temporary-AI navigation |
| Physical iPhone existing-library checks | 3 passed: expanded Light appearance tour, map focus/drag/return, and existing-library graph navigation |
| Signed device build | Passed; installed in place and launched on the connected iPhone |
| `git diff --check` | Passed |

The first visual-tour run failed its final empty-search assertion because the chosen fixture query matched three synthetic memories. Replaced only that test query with an unambiguous no-match string; both complete tours then passed. Production search behavior was not changed.

Reviewed representative screenshots across both modes, including the real phone's photo library/detail/editor, map, River, Timeline, Settings, AI Help, and Privacy. Also checked the regression screenshots for large-text River junction alignment and native inline video playback. Palette tests verify normal/Increased Contrast text and status colors, surface separation, and white text on message bubbles in both appearances. This is not a complete accessibility certification of every system sheet or arbitrary user image. Fresh cloud-AI responses and real voice recordings were not exercised.

The final phone tour included the tint-inheritance and neutral-icon refinements. The subsequent one-line restoration of the bright warning label over immersive photos was covered by the final simulator regression build and signed device build, but its photo-analysis error state was not separately triggered on the phone.

### Commands and evidence

Simulator commands used `xcodebuild -project Remember/Remember.xcodeproj -scheme Remember -destination 'platform=iOS Simulator,id=5741ED23-9F8F-4FB6-84E9-FE1E83225998' -configuration Debug -derivedDataPath /tmp/RememberProvenance -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO`, with these selections and the `test` action:

- Palette-only check: `-only-testing:RememberTests/AppearanceTests` (passed).
- Appearance review: `-only-testing:RememberTests -only-testing:RememberUITests/AppearanceReviewUITests/testLightSurfaces -only-testing:RememberUITests/AppearanceReviewUITests/testDarkSurfaces -resultBundlePath /tmp/remember-appearance-final-review.xcresult`.
- Final regressions: `-only-testing:RememberTests -only-testing:RememberUITests/RememberUITests/testDialFollowsDragInBothDirections -only-testing:RememberUITests/RememberUITests/testMemoryMapAccessibilityTextSize -only-testing:RememberUITests/RememberUITests/testPhotosVideoImportAndInlineRiverPlayback -only-testing:RememberUITests/RememberUITests/testThreeSurfaceNavigationAndTemporaryAI -resultBundlePath /tmp/remember-appearance-regressions.xcresult`.

Physical tests used `xcodebuild -xctestrun /tmp/RememberProvenance/Build/Products/Remember_Remember_iphoneos26.5-arm64.xctestrun -destination 'platform=iOS,id=00008150-000A123A2EC0C01C' -parallel-testing-enabled NO -only-testing:RememberUITests/AppearanceReviewUITests/testExistingLightLibrary -only-testing:RememberUITests/RememberUITests/testExistingMapFocusHoldDragAndReturn -only-testing:RememberUITests/RememberUITests/testExistingLibraryGraphNavigationWithoutCaptures -resultBundlePath /tmp/remember-appearance-phone-final.xcresult test-without-building`.

Final signed build: `xcodebuild -project Remember/Remember.xcodeproj -scheme Remember -destination 'platform=iOS,id=00008150-000A123A2EC0C01C' -configuration Debug -derivedDataPath /tmp/RememberProvenance -disableAutomaticPackageResolution DEVELOPMENT_TEAM=397P48LWC5 build`.

Install and launch: `xcrun devicectl device install app --device 5675C6C5-EBD9-59AF-B61D-F36F22C8D2B4 /tmp/RememberProvenance/Build/Products/Debug-iphoneos/Remember.app`, then `xcrun devicectl device process launch --device 5675C6C5-EBD9-59AF-B61D-F36F22C8D2B4 SimpleStudio.Remember`.

Detailed logs remain in `/tmp/remember-appearance-final-review.log`, `/tmp/remember-appearance-regressions.log`, `/tmp/remember-appearance-phone-final.log`, and `/tmp/remember-appearance-install-build.log`. Screenshot exports are in `/tmp/remember-appearance-final-images`, `/tmp/remember-appearance-phone-final-images`, and `/tmp/remember-appearance-regression-images`. An initial attachment export attempted before the regression bundle finalized failed; rerunning it after test completion succeeded. Existing simulator embedding-cache permissions and Xcode metadata warnings did not fail the checks.

No personal memories were imported, edited, or deleted during phone verification. Appearance overrides were process-only; the installed app was launched normally with the saved appearance preference intact. No Git state was changed. To review the new appearance, choose **Settings → Appearance → Light**.

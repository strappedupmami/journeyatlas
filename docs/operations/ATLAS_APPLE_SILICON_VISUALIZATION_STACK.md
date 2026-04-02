# Atlas Apple Silicon Visualization Stack

This note closes the gap from the latest PDF: native macOS visualization for large CAD assemblies, exploded views, and interactive scene updates.

## Current-State Truth

The repository already has a macOS app shell and strong local-first positioning, but it does not yet have a production 3D visualization stack.

That means Atlas should describe this as a roadmap and implementation direction, not as a completed end-user feature.

## Recommended Stack

For the native visualization layer, the PDF's direction is reasonable:

- Native macOS app for Apple Silicon
- SwiftUI shell for the desktop product surface
- RealityKit / Metal for high-performance local rendering
- USD / USDZ as the hierarchical scene interchange format
- Rust backend or service layer for orchestration, artifact handling, and safety controls

## Why Native Matters

For large multi-part assemblies, the real bottleneck is not only polygon count. It is:

- scene hierarchy
- memory pressure
- inspection latency
- live swaps of updated components
- stable playback while geometry changes underneath

A browser viewer is fine for lightweight preview. It is not the right default for Atlas if the goal is:

- exploded view inspection
- component-by-component commentary
- timeline pause/edit/resume loops
- high-fidelity local rendering on engineering machines

## Recommended Product Model

Atlas should treat the visualization app as a review cockpit, not as the system of record for CAD.

Recommended flow:

1. CAD pipeline produces a validated assembly revision
2. Atlas exports a hierarchical scene package such as USD/USDZ
3. Native macOS app opens that revision locally
4. User plays an exploded sequence or cinematic review path
5. User pauses, comments, or records a requested change
6. Atlas sends a structured modification request back to the CAD orchestration layer
7. Updated geometry or scene nodes return to the Mac for review

That keeps the renderer fast while the CAD truth stays in the engineering system.

## Exploded Views

Exploded views should be treated as deterministic scene transforms, not manual animation work.

Minimum implementation shape:

- preserve part hierarchy on import
- track local transforms per part/subassembly
- apply controlled offsets along defined axes
- keep a reversible mapping back to the original assembled state
- allow user-controlled intensity from compact to full explode

Important boundary:

- exploded views are a visualization aid
- they are not proof of manufacturability or regulatory compliance

## Interactive Cinematic Timeline

The PDF is directionally right that a useful "video" here is really a real-time scene timeline.

Recommended capabilities:

- authored camera path
- play / pause / scrub
- scene annotations tied to timestamps and part IDs
- live replacement of updated nodes after a CAD revision
- version-aware comments so feedback stays attached to the correct model state

## Suggested Mac App Architecture

Keep the app split cleanly:

- SwiftUI: desktop shell, panels, controls, inspector UI
- RealityKit / Metal: scene loading, rendering, lighting, animation
- Rust service boundary: orchestration, asset manifest validation, revision metadata, network requests

If Atlas later wants Rust-heavy desktop logic, a Tauri-style shell can still coexist with native rendering, but the important thing is preserving a true native rendering path instead of forcing everything through a web view.

## What Still Needs To Happen On Your End

- Decide whether Atlas will standardize on `USD`, `USDZ`, or a mixed export path
- Pick the first real scene type to support: exploded assembly review, cinematic walkthrough, or paused comment workflow
- Define minimum Apple Silicon hardware targets for end users
- Build the exporter path from CAD outputs into hierarchical scene assets
- Decide how voice comments, text comments, and revision IDs are linked together
- Assign ownership for native rendering performance, because this is now a desktop product surface, not just backend orchestration

## Honest Product Boundary

Safe claim:

"Atlas is building a native Apple Silicon visualization cockpit for high-fidelity assembly review and iterative scene updates."

Unsafe claim:

"Atlas already ships a production-ready native CAD cinema studio."

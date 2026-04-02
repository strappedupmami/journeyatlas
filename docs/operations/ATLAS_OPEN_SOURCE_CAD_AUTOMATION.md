# Atlas Open-Source CAD Automation

This document covers the missing implementation layer from the PDF: using FreeCAD and Blender as the low-cost AI-driven geometry stack.

## What is realistic

Yes, both FreeCAD and Blender are viable AI integration targets because they are Python-driven.

- FreeCAD is the stronger fit for parametric, dimensionally controlled engineering geometry.
- Blender is the stronger fit for mesh-heavy form exploration, visualization, rendering, and some simulation-oriented workflows.

## Recommended split

### FreeCAD

Use FreeCAD for:

- brackets
- mounts
- racks
- structural subcomponents
- parts that must stay parametric
- STEP / STL export for fabrication workflows

### Blender

Use Blender for:

- exterior form exploration
- aerodynamic or packaging visualization
- photorealistic renders
- dashboard/media assets
- OBJ / image output

## Safe architecture

Do not let an LLM write raw Python directly onto the host machine and execute it unrestricted.

Use this flow:

1. Atlas defines a constrained part request.
2. The model generates Python for FreeCAD or Blender.
3. Rust or another trusted backend validates the request shape.
4. The generated code runs inside an isolated sandbox or container.
5. Output is written only to an approved export directory.
6. Human review checks geometry, dimensions, and compliance implications before downstream use.

## Minimum guardrails

- Restrict filesystem access to a disposable workspace
- Restrict network access during CAD execution unless explicitly required
- Restrict Python imports to approved modules
- Log prompt, generated code hash, output files, and execution result
- Keep revision history for generated geometry and exported files
- Require human approval before any file is treated as fabrication-ready

## What still needs to happen on your end

- Decide whether FreeCAD, Blender, or both are the real R&D path
- Define the approved Python execution environment
- Build the sandbox/container policy
- Define accepted export formats per workflow:
  - STEP
  - STL
  - OBJ
  - PNG
- Define review ownership for:
  - geometry correctness
  - manufacturing readiness
  - compliance impact
  - revision control

## End-user readiness note

This stack is good for internal R&D acceleration. It does not make customer-facing vehicle claims real by itself.

Before any “real-world ready” claim, you still need:

- engineering review
- drawing/BOM workflow
- compliance review
- physical validation
- manufacturing QA

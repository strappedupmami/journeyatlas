# Atlas Safety-Critical CAD Stack

This note translates the latest PDF into a practical Atlas position for safety-critical, AI-assisted vehicle engineering.

## Core Truth

There is no real category of "regulatory-approved CAD software."

For Israel Ministry of Transport workflows and UNECE-aligned homologation, what matters is:

- Traceability across revisions, parameters, exports, and reviewers
- Credible FEA / validation evidence for safety-relevant structures
- Controlled quality processes across design, manufacturing, and change management
- Qualified human engineering sign-off for any road-going claim

## Recommended Stack By Budget

### 1. Best Overall For Agentic Engineering: Onshape

Use when Atlas wants the cleanest cloud-native API surface and the strongest audit history.

- REST API is a natural fit for Atlas Rust services
- Built-in document/version history helps preserve design lineage
- Easier to orchestrate remotely than legacy desktop CAD + COM automation
- Strongest option when traceability matters as much as geometry generation

Best fit:

- Parametric bracketry
- Mounting systems
- Iterative structural parts
- Teams that want clear revision history and controlled exports

### 2. Cheapest Commercial Route: Autodesk Fusion

Use when Atlas wants a lower-cost commercial seat with scripting and integrated simulation.

- Python and C++ automation support
- Built-in simulation is useful for early stress and load checks
- Lower licensing cost than heavy enterprise automotive suites

Best fit:

- Startup-stage R&D
- Faster commercial deployment than a full open-source stack
- Teams that need geometry plus early FEA in one tool

### 3. Cheapest Open Route: FreeCAD + Code_Aster

Use when Atlas wants near-zero licensing cost and is willing to own the orchestration burden.

- FreeCAD handles parametric geometry generation
- Code_Aster handles serious structural simulation on the open stack
- Requires more internal tooling, stronger sandboxing, and tighter workflow controls

Best fit:

- Internal R&D
- Cost-constrained experimentation
- Teams willing to build middleware for export, meshing, validation, and report generation

## Safety-Critical Targets Atlas Should Model Explicitly

The PDF is directionally right that the engineering workflow should be tied to concrete safety targets instead of vague "compliance AI" claims.

Examples Atlas should track with real human ownership:

- UNECE R29 for cab/front structure survival space where relevant
- UNECE R66 for rollover strength in applicable large-van/bus-style bodies
- ISO 26262 for software/electronics safety-relevant systems
- ISO / IATF 16949-style quality discipline for production and change control

These are not "features" the software can claim by itself. They are evidence programs Atlas must run.

## Suggested Atlas Architecture

Recommended flow:

1. User or agent defines a constrained engineering request
2. Atlas backend converts it into a validated CAD job schema
3. Atlas sends that schema to the chosen execution layer
4. CAD output is exported into controlled storage
5. FEA / validation jobs run against named load cases
6. Results are attached to the design revision record
7. Human engineering review decides whether the design can move forward

Minimum controls:

- No raw LLM-generated code on the host machine
- Sandbox/container boundary for CAD or solver execution
- Revision IDs tied to generated geometry and simulation outputs
- Controlled export formats such as STEP, STL, OBJ, PDF, CSV
- Structured evidence bundle per revision

## Example Onshape-Oriented Payload Shape

If Atlas chooses Onshape, the Rust backend should not send free-form prompts directly into CAD. It should send validated job data.

Example internal request shape:

```json
{
  "job_type": "parametric_mount_bracket",
  "project_id": "atlas-trailer-platform-v1",
  "revision_id": "rev-0027",
  "constraints": {
    "material": "6061-T6",
    "mount_hole_pattern_mm": [0, 40, 80],
    "plate_thickness_mm": 6,
    "target_load_newtons": 8500,
    "max_mass_kg": 1.2
  },
  "exports": ["STEP", "PDF"],
  "validation": {
    "run_mass_properties": true,
    "run_structural_check": true
  }
}
```

Example Atlas workflow against an Onshape-style API surface:

1. Create or select document/workspace for the project
2. Create or update the part studio from validated parameters
3. Request mass properties and geometry metadata
4. Export the resulting revision as STEP/PDF
5. Store the returned document/workspace/version IDs alongside the Atlas revision record

The key point is not the exact endpoint path. The key point is that Atlas should preserve:

- Input schema
- Output artifact IDs
- Exported files
- Validation results
- Reviewer decision

That is the evidence chain real-world programs need.

## What Still Needs To Happen On Your End

- Choose the actual production CAD stack: Onshape, Fusion, or FreeCAD + Code_Aster
- Decide which parts of the flow are R&D-only versus production-significant
- Put a real FEA owner in place for safety-relevant structures
- Define revision control, approval gates, and evidence retention rules
- Map target regulatory scope by vehicle class and market before marketing any safety claim
- Assign human ownership for ISO 26262 if Atlas touches safety-relevant electronics/software
- Run physical testing where required; simulation alone is not enough for final roadworthiness claims

## Product Claim Boundary

Safe claim:

"Atlas uses AI-assisted CAD and validation workflows to accelerate engineering."

Unsafe claim:

"Atlas automatically produces regulator-approved vehicle designs."

# Atlas Onshape Agent Orchestration

This note closes the gap from the latest PDF: how Atlas should actually talk to Onshape from a Rust backend.

## Core Truth

There is no single REST payload that turns "design a modern luxury performance e-fuel vehicle" into a complete production blueprint.

Onshape APIs operate on geometry features, sketches, part studios, assemblies, exports, and metadata. A real Atlas implementation would use agents as orchestrators that translate engineering intent into many validated API requests over time.

## Correct Mental Model

Wrong model:

- One prompt in
- Whole vehicle out

Correct model:

1. Atlas agent computes requirements and constraints
2. Atlas backend normalizes them into a typed CAD job
3. Atlas executes many ordered Onshape operations
4. Atlas stores returned IDs, exports, and measurements
5. Atlas loops until the subcomponent is complete
6. Human review decides whether to continue

## Recommended Atlas Internal Payload

Atlas should keep its own internal request shape separate from vendor-specific Onshape payloads.

Example internal CAD job:

```json
{
  "job_type": "parametric_intake_manifold_block",
  "project_id": "atlas-efuel-ice-platform",
  "revision_id": "rev-0042",
  "document_id": "onshape-doc-id",
  "workspace_id": "onshape-workspace-id",
  "element_id": "onshape-partstudio-id",
  "constraints": {
    "material": "aluminum_6061_t6",
    "runner_depth_mm": 120,
    "runner_width_mm": 45,
    "target_power_hp": 600,
    "fuel_mode": "efuel_optimized"
  },
  "exports": ["STEP", "PDF"],
  "checks": {
    "mass_properties": true,
    "geometry_regeneration": true
  }
}
```

This is what Atlas should validate, log, review, and replay.

## Example Vendor-Specific Onshape Feature Payload

After Atlas validates the internal job, it can translate a single step into an Onshape feature request.

Example shape for one extrusion-style operation:

```json
{
  "feature": {
    "btType": "BTMFeature-134",
    "name": "E-Fuel Intake Extrusion",
    "featureType": "extrude",
    "parameters": [
      {
        "btType": "BTMParameterEnum-145",
        "parameterId": "extrudeEndType",
        "value": "BLIND"
      },
      {
        "btType": "BTMParameterQuantity-147",
        "parameterId": "depth",
        "expression": "120 mm"
      },
      {
        "btType": "BTMParameterQueryList-148",
        "parameterId": "entities",
        "queries": [
          {
            "btType": "BTMIndividualQuery-138",
            "deterministicIdList": ["SKETCH_ENTITY_ID"]
          }
        ]
      }
    ]
  }
}
```

Important boundary:

- Atlas should not treat the exact `btType` constants as stable product abstractions
- Atlas should isolate vendor-specific payload builders behind a dedicated adapter layer
- Atlas should log the internal job plus the generated outbound request for traceability

## Suggested Rust Service Boundary

Recommended layers:

- `cad_jobs`: validates incoming engineering requests
- `cad_orchestrator`: plans the ordered steps for a subcomponent
- `onshape_adapter`: signs requests and maps Atlas jobs into Onshape payloads
- `cad_artifacts`: stores exports, mass properties, and metadata
- `cad_review`: records reviewer decisions and release gates

That separation keeps Atlas portable if it later mixes Onshape, Fusion, or FreeCAD workflows.

## Example Execution Loop

For a single subcomponent, Atlas would typically:

1. Create or select the target document/workspace/element
2. Create or update the source sketch
3. Post one feature request such as extrude, loft, fillet, shell, or boolean
4. Poll or fetch regeneration status if needed
5. Request mass properties or geometry metadata
6. Export the current revision as STEP/PDF
7. Persist returned IDs and artifacts in Atlas storage
8. Decide whether the next feature can proceed

Vehicle-scale work would repeat this loop hundreds or thousands of times across parts and assemblies. That orchestration is the real product, not any one payload.

## Authentication Reality

The PDF is directionally correct that Atlas needs secure request signing instead of a casual bearer token flow.

At minimum, Atlas should:

- Keep Onshape credentials server-side only
- Sign requests in Rust, not in a client app
- Rotate keys on a schedule
- Attach request IDs for traceability
- Log failed regeneration and export attempts

## Webhooks And Async Completion

If Atlas later adopts webhooks, the right use is not "AI magic." The right use is operational continuity.

Good webhook uses:

- Regeneration finished
- Export completed
- Metadata available
- Failure callback for invalid geometry or feature execution

Atlas should treat webhook events as untrusted input until validated and tied back to a known job/revision record.

## What Still Needs To Happen On Your End

- Create a real Onshape developer setup and provision production credentials
- Decide the first narrow component family to automate instead of aiming at a full vehicle
- Define the exact internal CAD job schema Atlas will support first
- Build or choose the artifact store for STEP/PDF/mass-property outputs
- Decide how reviewer sign-off will be captured per revision
- Assign ownership for vendor API drift, because payload details can change over time

## Product Claim Boundary

Safe claim:

"Atlas can orchestrate CAD feature generation and export workflows through a controlled backend."

Unsafe claim:

"Atlas can send one REST payload and receive a complete road-ready vehicle blueprint."

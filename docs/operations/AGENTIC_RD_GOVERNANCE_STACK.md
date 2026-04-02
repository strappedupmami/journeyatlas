# Agentic R&D Governance Stack

## Purpose

This stack turns the existing BlackHaven/Atlas R&D lane into a reviewable engineering workflow:

- requirements are explicit
- design decisions are explicit
- evidence is linked to artifacts and simulation runs
- compliance packets are generated from stored state
- approvals are role-aware and timestamped
- approved baselines are snapshotted and hashable
- audit events record who changed what and why

The goal is lower startup cost through automation and reuse, not fake regulatory authority.

## Architecture

The Rust API keeps the R&D job as the canonical anchor record. Governance entities live on the same job:

- `Requirement`
- `DesignDecision`
- `DesignReview`
- `EvidenceArtifact`
- `TestOrSimulationRun`
- `ComplianceReport`
- `ApprovalRecord`
- `AuditEvent`
- `ApprovedBaseline`

This avoids a second disconnected compliance subsystem.

## Data Model

### Requirement

Captures a specific goal, constraint, or sign-off gate.

Key fields:

- stable ID
- status: `draft | in_review | approved | superseded`
- source plan version
- linked components
- linked decisions
- linked evidence
- linked reports
- linked approvals
- verification notes

### DesignDecision

Captures an architecture/toolchain/boundary choice.

Key fields:

- stable ID
- context
- decision
- rationale
- status
- requirement links
- evidence links
- affected artifacts
- review links

### EvidenceArtifact

Derived from real stored artifacts such as:

- CAD source
- validation reports
- simulation inputs/results
- review scenes
- compliance reports

### TestOrSimulationRun

Represents a named run, not a vague claim.

Key fields:

- run type
- status
- input artifact IDs
- output artifact IDs
- linked requirements
- linked decisions

### ComplianceReport

Generated from stored state.

Sections include:

- scope
- applicable requirements
- assumptions
- design description
- risk notes
- verification evidence
- open issues
- reviewer / approver data
- provenance
- automation boundary

### ApprovalRecord

This is infrastructure for real review, not fake legal authority.

Important separation:

- `ai_recommendation`
- `internal_engineering_approval`
- `external_certified_signoff`

An AI recommendation can never be silently treated as certified sign-off.

### ApprovedBaseline

A baseline locks a snapshot of the current artifact/report/requirement/decision set and stores:

- included IDs
- timestamp
- status
- snapshot hash

## Traceability Model

BlackHaven builds requirement-centric traceability rows:

- requirement
- linked component IDs
- linked decision IDs
- linked evidence IDs
- linked report IDs
- linked approval IDs
- unresolved gaps

This lets a reviewer answer:

- why was this decision made?
- what requirement does it satisfy?
- what evidence supports it?
- what changed since the last review?
- who approved it?
- what remains unresolved?

## Approval / Sign-off Flow

1. User drafts plan
2. Accepted plan seeds requirements and initial design decisions
3. Artifact generation and simulation sync evidence records
4. Compliance packet is generated from stored state
5. Reviewers record structured review notes
6. Internal engineering approval can be recorded
7. External certified sign-off can be recorded separately
8. Approved baseline is snapshotted and hashed

## Automation Boundary

Allowed:

- AI planning
- AI drafting
- evidence bundling
- traceability linking
- report generation
- approval packet assembly

Not allowed:

- representing AI as a legally valid certifier
- implying autonomous manufacturing or certification approval without human authority
- fabricating completeness when source data is missing

## Current Limits

- The governance model is now explicit, but real regulatory acceptance still depends on domain-qualified engineers and compliance experts.
- Physical validation, calibrated simulation models, material certification, and market-specific regulatory review remain external responsibilities.
- The current persistence path stores full R&D jobs in the API database as JSON; if this grows substantially, normalization may be worth doing later.

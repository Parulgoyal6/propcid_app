# PropCid Flutter Listing Migration

## Objective

Make the Flutter listing flow functionally identical to the React website.

The Flutter application should keep its own UI and UX.

Only business logic, validations, fields, dropdowns, metadata, payloads, edit mode behaviour, and API contracts should match React.

## Source of Truth (Priority Order)

1. React Website Source Code
2. docs/migration/migration-specification.md
3. docs/migration/final-architecture-review.md

If documentation conflicts with React, React is the source of truth.

## UI Specification

The React portal is the canonical design specification for the Post Property flow.

Flutter must reproduce the portal's:

- layout
- hierarchy
- headings
- labels
- helper text
- field order
- grouping
- spacing
- validation
- navigation
- interactions

Only adapt layouts where required because of mobile screen width.

Do not redesign or modernize.

Business logic from T0–T11 must remain unchanged.

## Rules

- Never invent dropdown values.
- Never invent metadata keys.
- Never invent validations.
- Never change database schema unless explicitly required.
- Work in small phases.
- Stop after every phase.
- Explain every code change before continuing.

## Current Priority

Implement only the migration work.

Ignore unrelated features unless they block compilation.

The first implementation phase is:

- Fix metadata edit-mode corruption
- Preserve metadata on update
- Fix metadata key mappings
- Implement metadata merge behaviour
- Do not begin Residential, Commercial, PG, Land or Other parity yet until Phase 0 is complete.
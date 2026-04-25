---
name: swift-analyze
description: Run SwiftLint, SwiftFormat, and optionally Periphery on Yowee Swift sources. Reports violations and auto-fixes what it can.
---

# swift-analyze

Run SwiftLint and SwiftFormat checks on the Yowee Swift sources, report all violations, then auto-fix what can be fixed automatically.

## Steps

1. **SwiftLint** — run lint, collect errors and warnings:
   ```
   swiftlint lint --quiet --config .swiftlint.yml
   ```
   - If `swiftlint` is not installed, tell the user: `brew install swiftlint`
   - Count errors vs warnings; show all output
   - Auto-fix safe violations: `swiftlint --fix --quiet --config .swiftlint.yml`

2. **SwiftFormat** — check formatting drift:
   ```
   swiftformat --lint Sources
   ```
   - If files need reformatting, auto-fix them: `swiftformat Sources`
   - Report which files were reformatted

3. **Periphery** (only if `--deep` was passed as an argument):
   ```
   periphery scan
   ```
   - If `periphery` is not installed, tell the user: `brew install periphery`
   - Report unused declarations; do NOT auto-fix (removals require human judgment)

## Reporting

After all checks, output a summary table:

| Tool | Status | Detail |
|------|--------|--------|
| SwiftLint | pass / warn / fail / skip | N errors, N warnings |
| SwiftFormat | pass / warn / skip | N files reformatted |
| Periphery | pass / warn / skip | N unused declarations |

- **fail** = errors present (block ship)
- **warn** = warnings only (review before ship)
- **pass** = clean
- **skip** = tool not installed

If any errors remain after auto-fix, list them with file:line and the rule name so the developer can address them manually.

## Scope

- Only scan `Sources/` (excluding `Sources/TestRunner`)
- Never modify test files or Package.swift
- Never suppress a lint rule inline (`// swiftlint:disable`) without a comment explaining why

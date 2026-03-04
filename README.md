# SOQL & Governor Hotspot Profiler (LWC + Apex)

Org-wide performance forensics for Salesforce teams that live in Apex.

## What it does
- **Slow transaction explorer**: surfaces transactions with high CPU/limits usage.
- **SOQL shape fingerprinting**: groups similar query shapes across logs and highlights suspicious patterns.
- **Regression detector (7/30 days)**: identifies queries whose averages moved materially.
- **Alert rules**: define thresholds and track alert events (optional nightly scheduler).

Designed to deploy cleanly into most Lightning orgs without paid add-ons.  
Uses **Tooling API debug logs (ApexLog)** as the raw signal and stores normalized metrics so dashboards don’t depend on Tooling API at read-time.

## Deploy

### Salesforce CLI
```bash
sf org login web --set-default --alias ph
sf project deploy start --source-dir force-app --target-org ph
```

### After deploy
1. Assign permission set **SOQL_Governor_Hotspot_Profiler**
2. App Launcher → **SOQL & Governor Hotspot Profiler**
3. Open **Profiler Run**
   - Start with **Light mode**
   - Use **Deep mode** when you need targeted capture windows

## Modes

### Light mode (sampled)
- Pulls up to N recent ApexLogs (default 200) over the last X days.
- Best for broad signals and daily monitoring.
- Requires: API access + ability to view logs you want to analyze.

### Deep mode (admin-triggered tracing)
- Creates a **TraceFlag** for a selected user for a short window.
- Run the target flow/transaction, then collect newly generated logs.
- Requires: setup permissions to manage trace flags/debug levels.

## Notes / limitations
- Debug log retention and access vary by org policy.
- Very large logs may be skipped if they exceed the configured fetch cap.
- Query “index suspect” detection is heuristic; treat as a lead generator, not a verdict.

## Repo layout
- `force-app/main/default/lwc/` — UI (dashboard, explorer, ingestion)
- `force-app/main/default/classes/` — controllers/services + tests
- `force-app/main/default/objects/` — normalized storage objects
- `force-app/main/default/flexipages/` + `tabs/` + `applications/` — navigation entry point

## License
MIT

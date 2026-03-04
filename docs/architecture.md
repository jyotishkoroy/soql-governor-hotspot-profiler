# Architecture

## Data flow
1. User runs a profiler session (Light / Deep).
2. LWC queries Tooling API `ApexLog` records and downloads log bodies.
3. Client-side parser extracts:
   - Transaction summary (CPU, limits, entry point)
   - SOQL occurrences (query text, rows, duration)
   - Fingerprints for query shape analysis
4. Metrics are sent to Apex in small batches and stored in custom objects.
5. Dashboard and regression panels read only custom objects (Tooling API is not required for viewing).

## Why client-side parsing?
- Avoid Apex heap/CPU issues with large logs
- Keeps ingestion resilient across org sizes
- Reduces server-side complexity while preserving a run audit trail

## Deep mode
- Uses Tooling API to create TraceFlags for selected users (admin permissions required).
- Intended for targeted capture windows (15–60 minutes).

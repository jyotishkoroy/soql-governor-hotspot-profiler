# Data Model

- `PH_Run__c` — ingestion run header and counters
- `PH_Transaction__c` — one record per ApexLog analyzed
- `PH_Query__c` — per-query occurrences linked to a transaction
- `PH_Daily_Query_Stat__c` — per-day aggregates per fingerprint hash
- `PH_Daily_Txn_Stat__c` — per-day aggregates per transaction signature
- `PH_Alert_Rule__c` — configurable thresholds
- `PH_Alert_Event__c` — fired alerts for review/audit

External IDs make ingestion idempotent (safe to re-run).

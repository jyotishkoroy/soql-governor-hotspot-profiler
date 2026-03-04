# SOQL & Governor Hotspot Profiler

This repo ships a lightweight, self-contained Salesforce app for org-wide performance forensics.

It helps teams answer:
- Which transactions are consuming CPU / limits?
- Which SOQL shapes repeat across executions?
- Did anything regress compared to the last 7/30 days?

The app relies on Tooling API debug logs (ApexLog) and stores normalized metrics in custom objects so dashboards
don’t depend on Tooling API at read-time.

See README.md for setup and operational guidance.

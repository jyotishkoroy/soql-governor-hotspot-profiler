# Operations

## Light mode
- Fast sampling of recent ApexLogs (default: last 24h, max 200 logs).
- Best for day-to-day tracking.

## Deep mode
- Admin enables tracing for a user for a short window.
- Run the business flow, then collect newly generated logs.
- Best for reproducing and diagnosing regressions.

## Storage & retention
- In very active orgs, consider a retention policy for `PH_Query__c` and `PH_Transaction__c`.
- Daily aggregates are compact and intended for long-term trending.

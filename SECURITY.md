# Security Policy

## Reporting a Vulnerability
If you find a security issue:
1. Do not open a public issue with sensitive details.
2. Open a GitHub issue requesting a private channel, or contact the maintainer.

## Security Design Notes
- Apex is `with sharing`
- Ingestion validates object access and uses `Security.stripInaccessible` before DML
- Browser Tooling API calls are same-origin and rely on the user’s session + permissions

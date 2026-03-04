# Contributing

## Local development
```bash
sf org create scratch --definition-file config/project-scratch-def.json --set-default --alias ph
sf project deploy start --source-dir force-app --target-org ph
```

## Guidelines
- Keep Apex changes covered with tests.
- Prefer small, reviewable PRs.
- Avoid org-specific assumptions (hard-coded domains, MyDomain requirements, etc.).

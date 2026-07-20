# my-sfdc-project

Salesforce DX Project — API Version 62.0

## Quick Start

```bash
# Authorize your org
sf org login web --alias myorg --set-default

# Deploy to org
sf project deploy start --source-dir force-app --target-org myorg

# Run tests
sf apex run test --target-org myorg --test-level RunLocalTests

# Retrieve from org
sf project retrieve start --source-dir force-app --target-org myorg
```

## Project Structure

```
force-app/main/default/
├── classes/          ← Apex classes
├── triggers/         ← Apex triggers
├── lwc/              ← Lightning Web Components
├── aura/             ← Aura components
├── objects/          ← Custom objects & fields
├── layouts/          ← Page layouts
├── flexipages/       ← Lightning pages
├── flows/            ← Flows
├── permissionsets/   ← Permission sets
└── staticresources/  ← Static resources

manifest/
├── package.xml               ← Retrieve manifest
└── destructiveChanges.xml    ← Deletion manifest

config/
└── project-scratch-def.json  ← Scratch org config
```

## CI/CD

This project uses GitHub Actions for automated deployments.
See `.github/workflows/` for pipeline configuration.

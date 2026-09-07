# Architecture

## Overview

Quest App uses **Clean Architecture** organized as a Melos monorepo.

## Dependency Graph

```
supabase_contracts (pure Dart, no deps)
        |
    app_core (pure Dart, no deps)
        |
    app_models (depends on app_core, supabase_contracts)
        |
  app_repositories (depends on app_models, app_core, supabase_contracts, supabase_flutter)
        |
    shared_ui (Flutter, depends on app_core)
       / \
mobile_app  admin_web  (both depend on all packages)
```

## Layer Rules

Each feature has three layers:

- **data/** — Datasources, DTOs, repository implementations
- **domain/** — Entities, repository contracts, use cases
- **presentation/** — Riverpod providers, pages, widgets

## Import Rules

- Features MUST NOT import from another feature's presentation layer
- Features may import from shared packages (app_models, app_repositories, etc.)
- All Supabase table/column/status references MUST use supabase_contracts constants
- All shared models MUST live in app_models, not duplicated per feature

## Data Flow

```
UI (Widget) -> Provider -> Use Case -> Repository Contract -> Repository Impl -> Supabase
```

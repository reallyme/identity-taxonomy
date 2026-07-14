<!--
SPDX-FileCopyrightText: Copyright © 2026 ReallyMe LLC. All rights reserved

SPDX-License-Identifier: Apache-2.0
-->

# ReallyMe Identity Taxonomy

[![taxonomy](https://github.com/reallyme/identity-taxonomy/actions/workflows/taxonomy.yml/badge.svg)](https://github.com/reallyme/identity-taxonomy/actions/workflows/taxonomy.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

### A machine-readable identity taxonomy for EUDI Wallet, eIDAS 2.0, W3C Verifiable Credentials, and OpenID4VC

The ReallyMe Identity Taxonomy is a machine-readable map for building identity
systems that are aligned with eIDAS 2.0, the EUDI Wallet Architecture and
Reference Framework, W3C DID and Verifiable Credential standards, OpenID for
Verifiable Credentials, and modern post-quantum identity profiles.

It defines a shared vocabulary for identity resources, operations,
capabilities, data types, and conformance expectations. Rather than scattering
identity semantics across SDKs, APIs, documentation, and certification tooling,
the taxonomy keeps a single auditable source of truth.

Taxonomy entries describe identity concepts in a machine-readable form that
tools can inspect, validate, and project into focused views:

```yaml
credential_formats:
  core:
    sd_jwt_vc:
      support: required
      specification: sd_jwt_vc
```

## Explore

[Browse the taxonomy](https://reallyme.github.io/identity-taxonomy/)

## Who Is This For?

This repository is intended for:

- Identity platform teams
- EUDI Wallet implementers
- SDK developers
- API designers
- Standards and interoperability teams
- Compliance and certification engineers

## What It Covers

- eIDAS 2.0 and EUDI wallet concepts, including PID, QEAA, PuB-EAA, EAA,
  relying-party registration, wallet attestations, and trust framework
  metadata.
- DID, credential, presentation, wallet, trust, audit, and status-list
  resources across SDK and hosted-service surfaces.
- Protocol capabilities for did:me, W3C Verifiable Credentials, SD-JWT VC,
  mdoc, OpenID4VCI, OpenID4VP, HAIP, and related identity standards.
- Operation metadata for stable naming, authorization scopes, event emission,
  retry behavior, security posture, and public visibility.
- Conformance views that downstream repositories can use to drive private SDK
  coverage reports, release checks, and implementation matrices.

The taxonomy is not itself a certification or conformance program. Instead, it
defines the auditable map that implementations can use to measure coverage,
identify gaps, and keep product surfaces consistent as standards evolve.

## Standards

The taxonomy incorporates concepts from:

- eIDAS 2.0
- ETSI trust-service specifications
- EUDI Wallet ARF
- ISO 18013-5 and ISO 18013-7
- OpenID4VCI
- OpenID4VP
- SD-JWT
- SD-JWT VC
- W3C DID Core
- W3C DID Resolution
- W3C Verifiable Credentials

## Repository Layout

- [`master-identity-taxonomy.yaml`](master-identity-taxonomy.yaml) is the
  authoritative taxonomy source.
- [`taxonomy-views/`](taxonomy-views/) contains generated, consumer-focused
  YAML views.
- [`docs/index.html`](docs/index.html) is the static GitHub Pages viewer.
- [`scripts/`](scripts/) contains the public lint and view-generation tools.

## Validate

Run the public taxonomy checks from the repository root:

```sh
ruby scripts/lint_taxonomy.rb
ruby scripts/generate_taxonomy_views.rb --check
```

## Generated Views

Generated views provide focused subsets of the master taxonomy for common
consumers:

- [SDK surface](taxonomy-views/sdk_surface.yaml)
- [Hosted API surface](taxonomy-views/hosted_api.yaml)
- [Protocol capabilities](taxonomy-views/protocol_capabilities.yaml)
- [Type system](taxonomy-views/type_system.yaml)
- [Operation registry](taxonomy-views/operation_registry.yaml)
- [Conformance matrix](taxonomy-views/conformance_matrix.yaml)

The view generator reads `master-identity-taxonomy.yaml`, selects stable
subsets for each consumer, writes generated YAML under `taxonomy-views/`, and
adds a generated-file header to make manual edits easy to catch in review.
Run it after changing the master taxonomy:

```sh
ruby scripts/generate_taxonomy_views.rb
```

Use check mode in CI to fail when generated views drift:

```sh
ruby scripts/generate_taxonomy_views.rb --check
```

## Versioning

The taxonomy follows semantic versioning. Generated views are derived artifacts
of the corresponding master taxonomy version.

## Consuming Repositories

Consumers should treat `master-identity-taxonomy.yaml` and the generated files
under `taxonomy-views/` as public inputs. Private SDK or service compliance
reports should live in the consuming repository when they expose in-progress
implementation status.

For local development, a consuming repository can point at a checked-out copy
with:

```sh
export REALLYME_IDENTITY_TAXONOMY_PATH=/path/to/identity-taxonomy/master-identity-taxonomy.yaml
```

## GitHub Pages

The viewer in `docs/index.html` is designed for GitHub Pages. It loads the
taxonomy YAML directly from this repository at runtime and requires no build
step.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

## Copyright And Trademarks

Copyright © 2026 by ReallyMe LLC.

ReallyMe<sup>®</sup> is a registered trademark of ReallyMe LLC.

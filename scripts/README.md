<!--
SPDX-FileCopyrightText: Copyright © 2026 ReallyMe LLC. All rights reserved

SPDX-License-Identifier: Apache-2.0
-->

# Taxonomy Scripts

These scripts operate on the public identity taxonomy in this repository.

- `ruby scripts/lint_taxonomy.rb` validates the master taxonomy.
- `ruby scripts/generate_taxonomy_views.rb` regenerates derived views under
  `taxonomy-views/`.
- `ruby scripts/generate_taxonomy_views.rb --check` fails when generated views
  are stale.

Both scripts accept `REALLYME_IDENTITY_TAXONOMY_PATH` for unusual local
layouts. The view generator also accepts
`REALLYME_IDENTITY_TAXONOMY_VIEWS_DIR`.


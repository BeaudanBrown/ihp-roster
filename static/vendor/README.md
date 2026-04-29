Vendored runtime assets:

- Bootstrap 5.3.8
- Bootstrap Icons 1.11.3
- HTMX 1.9.12
- Flatpickr from the pinned IHP checkout
- Morphdom from the pinned IHP checkout

Keep core runtime assets local and load them through `assetPath` from the
layout so production does not depend on third-party CDNs.

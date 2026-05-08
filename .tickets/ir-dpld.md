---
id: ir-dpld
status: open
deps: [ir-84gh]
links: []
created: 2026-05-08T00:01:06Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, area:nixos, area:security]
---
# Configure Stripe billing through NixOS secrets

Extend the IHP roster NixOS module so Stripe Billing can be enabled with non-secret options and secret-file/systemd credential injection.

## Design

Add services.ihpRoster.billing.stripe options for enable, priceId, currency aud, amountCents 10000, interval month, secretKeyFile, webhookSecretFile, paymentMethods, gstRegistered false, automaticTax false. Pass secret file paths or LoadCredential paths to app and worker services; do not place live keys in Nix store strings or production examples.

## Acceptance Criteria

Nix eval/module tests or focused inspection show billing env is generated only when enabled, required options assert correctly, live secrets are file-backed, and production docs include placeholders and rotation instructions.


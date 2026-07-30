let
  verificationSource = import ./verification-source.nix { root = ../../..; };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString verificationSource));
  lib = flake.inputs.nixpkgs.lib;
  evaluate =
    {
      enable ? true,
      mode ? "live",
      baseUrl ? "https://billing.example.test",
      checkoutEnabled ? false,
      ownerNavigationVisible ? false,
      priceLookupKey ? "bepis_venue_monthly_aud_100",
      priceId ? null,
      automaticTax ? false,
      taxIdCollection ? false,
      gstRegistered ? false
    }:
    lib.nixosSystem {
      system = builtins.currentSystem;
      modules = [
        flake.nixosModules.default
        ({ ... }: {
          boot.isContainer = true;
          networking.hostName = "bepis-billing-module-check";
          services.ihpRoster = {
            enable = true;
            production = true;
            domain = "billing.example.test";
            inherit baseUrl;
            databaseUrl = "postgresql:///billing_module_check";
            enableMigrations = false;
            billing.stripe = {
              inherit
                enable
                mode
                checkoutEnabled
                ownerNavigationVisible
                priceLookupKey
                priceId
                automaticTax
                taxIdCollection
                gstRegistered
                ;
              secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
              webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
            };
          };
        })
      ];
    };
  assertionsPass = evaluated: builtins.all (item: item.assertion) evaluated.config.assertions;
  valid = evaluate { };
  cfg = valid.config;
  invalidConfigurations = [
    (evaluate { enable = false; checkoutEnabled = true; })
    (evaluate { mode = "test"; })
    (evaluate { baseUrl = "http://billing.example.test"; })
    (evaluate { priceId = "price_ambiguous"; })
    (evaluate { automaticTax = true; })
  ];
in
assert assertionsPass valid;
assert builtins.all (evaluated: !(assertionsPass evaluated)) invalidConfigurations;
assert cfg.services.ihpRoster.production;
assert cfg.services.ihpRoster.billing.stripe.mode == "live";
assert cfg.services.ihpRoster.billing.stripe.checkoutEnabled == false;
assert cfg.services.ihpRoster.billing.stripe.ownerNavigationVisible == false;
assert cfg.services.ihp.additionalEnvVars.STRIPE_MODE == "live";
assert cfg.services.ihp.additionalEnvVars.STRIPE_BILLING_ENABLED == "true";
assert cfg.services.ihp.additionalEnvVars.STRIPE_CHECKOUT_ENABLED == "false";
assert cfg.services.ihp.additionalEnvVars.STRIPE_OWNER_NAVIGATION_VISIBLE == "false";
assert builtins.elem "stripe-secret-key:/run/secrets/ihp-roster-stripe-secret-key" cfg.systemd.services.app.serviceConfig.LoadCredential;
assert builtins.elem "stripe-webhook-secret:/run/secrets/ihp-roster-stripe-webhook-secret" cfg.systemd.services.worker.serviceConfig.LoadCredential;
{
  apiMode = cfg.services.ihp.additionalEnvVars.STRIPE_MODE;
  billingEnabled = cfg.services.ihp.additionalEnvVars.STRIPE_BILLING_ENABLED;
  checkoutEnabled = cfg.services.ihp.additionalEnvVars.STRIPE_CHECKOUT_ENABLED;
  ownerNavigationVisible = cfg.services.ihp.additionalEnvVars.STRIPE_OWNER_NAVIGATION_VISIBLE;
  assertions = builtins.length cfg.assertions;
  rejectedUnsafeConfigurations = builtins.length invalidConfigurations;
}

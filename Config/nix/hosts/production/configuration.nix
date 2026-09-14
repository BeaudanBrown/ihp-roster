{ self, ... }:
{
  imports = [
    ./hardware-configuration.nix
    self.nixosModules.default
  ];

  # Logging to AWS CloudWatch
  # services.vector = {
  #     enable = true;
  #     journaldAccess = true;
  #     settings = {
  #         sources.journald = {
  #             type = "journald";
  #             # Log only the services we care about
  #             include_units = ["app.service" "nginx.service" "worker.service"];
  #         };

  #         sinks.out = {
  #             group_name = "CHANGE-ME";
  #             stream_name = "CHANGE-ME";
  #             # Change the region to the correct one, e.g. `us-east-1`
  #             region = "CHANGE-ME";
  #             auth = {
  #                 access_key_id = "CHANGE-ME";
  #                 secret_access_key = "CHANGE-ME";
  #             };
  #             inputs  = ["journald"];
  #             type = "aws_cloudwatch_logs";
  #             compression = "gzip";
  #             encoding.codec = "json";
  #         };
  #     };
  # };

  # Tailnet authentication remains an out-of-band host bootstrap step.
  services.tailscale.enable = true;

  # Observability StateDirectoryQuota requires project quotas on the backing
  # filesystem. The concrete host hardware layer must retain this mount option.
  fileSystems."/".options = [ "prjquota" ];

  services.ihpRoster = {
    enable = true;
    production = true;
    domain = "CHANGE-ME.com";
    databaseUser = "ihp_roster";
    serviceUser = "ihp_roster";
    createServiceUser = true;
    managePostgres = true;
    configureNginx = true;
    httpsEnabled = true;
    acmeEmail = "CHANGE-ME@example.com";
    legalDocuments = {
      businessName = "Bepis PTY LTD";
      supportEmail = "support@bepis.lol";
      # Populate these before live payments, either with file paths managed
      # outside git or with inline *Text options in a private deployment layer.
      termsFile = null;
      privacyFile = null;
      refundsDisputesFile = null;
      cancellationFile = null;
    };
    observability = {
      otel.enable = true;
      collector.enable = true;
      tempo = {
        enable = true;
        queryAddress = "0.0.0.0";
      };
      loki = {
        enable = true;
        queryAddress = "0.0.0.0";
      };
    };
    billing.stripe = {
      # Enable after provisioning the Dashboard Product/Price, webhook endpoint,
      # Customer Portal settings, and the two secret files below. For the hidden
      # canary, set enable and checkoutEnabled true while navigation stays false.
      enable = false;
      mode = "live";
      checkoutEnabled = false;
      ownerNavigationVisible = false;
      priceLookupKey = "bepis_venue_monthly_aud_100";
      priceId = null;
      secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
      webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
      gstRegistered = false;
      automaticTax = false;
      taxIdCollection = false;
      reconciliationSweep = {
        enable = true;
        onCalendar = "daily";
        randomizedDelaySec = "30m";
      };
      # Rotate keys in Stripe Dashboard, update the secret files out-of-band,
      # then restart app.service and worker.service. Do not commit real keys.
    };
    # Leave this empty to generate a secret on first boot.
    # Put a base64-encoded 96-byte secret here for deterministic login sessions.
    sessionSecret = "";
    additionalEnvVars = {
      SMTP_HOST = "email-smtp.eu-west-1.amazonaws.com";
      SMTP_PORT = "587";
      SMTP_ENCRYPTION = "STARTTLS";

      SMTP_USER = "CHANGE-ME";
      SMTP_PASSWORD = "CHANGE-ME";

      AWS_ACCESS_KEY_ID = "CHANGE-ME";
      AWS_SECRET_ACCESS_KEY = "CHANGE-ME";
    };
  };

  # As we use a pre-built AMI on AWS,
  # it is essential to enable automatic updates.
  # @see https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.autoUpgrade.enable = true;
  system.stateVersion = "25.05";
}

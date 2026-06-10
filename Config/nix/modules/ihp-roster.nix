{ self, ihp }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    mkDefault
    mkForce
    optional
    optionalAttrs
    types
    ;

  cfg = config.services.ihpRoster;
  legalCfg = cfg.legalDocuments;
  stripeCfg = cfg.billing.stripe;
  hasJobRunner = builtins.pathExists ../../../Application/Job;
  hasServiceUser = cfg.serviceUser != null;
  effectiveServiceGroup = if cfg.serviceGroup != null then cfg.serviceGroup else cfg.serviceUser;
  schemaReadyService = if cfg.enableMigrations then "migrate.service" else "loadSchema.service";

  serviceUserConfig = optionalAttrs hasServiceUser {
    User = cfg.serviceUser;
    Group = effectiveServiceGroup;
    UMask = "0077";
  };

  defaultPackage =
    if cfg.optimized then
      self.packages.${pkgs.system}.optimized-prod-server
    else
      self.packages.${pkgs.system}.default;

  mailEnv = optionalAttrs (cfg.mailFrom != null) {
    MAIL_FROM = cfg.mailFrom;
  };

  legalTermsFile =
    if legalCfg.termsText != null then pkgs.writeText "bepis-legal-terms.txt" legalCfg.termsText else legalCfg.termsFile;
  legalPrivacyFile =
    if legalCfg.privacyText != null then pkgs.writeText "bepis-legal-privacy.txt" legalCfg.privacyText else legalCfg.privacyFile;
  legalRefundsDisputesFile =
    if legalCfg.refundsDisputesText != null then
      pkgs.writeText "bepis-legal-refunds-disputes.txt" legalCfg.refundsDisputesText
    else
      legalCfg.refundsDisputesFile;
  legalCancellationFile =
    if legalCfg.cancellationText != null then
      pkgs.writeText "bepis-legal-cancellation.txt" legalCfg.cancellationText
    else
      legalCfg.cancellationFile;
  legalFileEnv = name: file: optionalAttrs (file != null) { ${name} = toString file; };
  legalEnv =
    {
      BEPIS_LEGAL_BUSINESS_NAME = legalCfg.businessName;
      BEPIS_LEGAL_SUPPORT_EMAIL = legalCfg.supportEmail;
    }
    // legalFileEnv "BEPIS_LEGAL_TERMS_FILE" legalTermsFile
    // legalFileEnv "BEPIS_LEGAL_PRIVACY_FILE" legalPrivacyFile
    // legalFileEnv "BEPIS_LEGAL_REFUNDS_DISPUTES_FILE" legalRefundsDisputesFile
    // legalFileEnv "BEPIS_LEGAL_CANCELLATION_FILE" legalCancellationFile;

  boolEnv = value: if value then "true" else "false";
  stripeEnv = optionalAttrs stripeCfg.enable (
    {
      STRIPE_SECRET_KEY_FILE = "%d/stripe-secret-key";
      STRIPE_WEBHOOK_SECRET_FILE = "%d/stripe-webhook-secret";
      STRIPE_EXPECTED_CURRENCY = stripeCfg.currency;
      STRIPE_EXPECTED_AMOUNT_CENTS = toString stripeCfg.amountCents;
      STRIPE_EXPECTED_INTERVAL = stripeCfg.interval;
      STRIPE_EXPECTED_INTERVAL_COUNT = toString stripeCfg.intervalCount;
      STRIPE_GST_REGISTERED = boolEnv stripeCfg.gstRegistered;
      STRIPE_AUTOMATIC_TAX = boolEnv stripeCfg.automaticTax;
      STRIPE_TAX_ID_COLLECTION = boolEnv stripeCfg.taxIdCollection;
    }
    // optionalAttrs (stripeCfg.priceLookupKey != null) {
      STRIPE_PRICE_LOOKUP_KEY = stripeCfg.priceLookupKey;
    }
    // optionalAttrs (stripeCfg.priceId != null) {
      STRIPE_PRICE_ID = stripeCfg.priceId;
    }
    // optionalAttrs (stripeCfg.paymentMethodTypes != [ ]) {
      STRIPE_PAYMENT_METHOD_TYPES = lib.concatStringsSep "," stripeCfg.paymentMethodTypes;
    }
  );
  runtimeEnvironmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;
  xeroEnvironmentFiles = runtimeEnvironmentFiles ++ optional (cfg.xero.environmentFile != null) cfg.xero.environmentFile;
  stripeEnvironmentFiles = optional (stripeCfg.environmentFile != null) stripeCfg.environmentFile;
  appWorkerEnvironmentFiles = xeroEnvironmentFiles ++ stripeEnvironmentFiles;
  stripeCredentialConfig = optionalAttrs stripeCfg.enable {
    LoadCredential = [
      "stripe-secret-key:${toString stripeCfg.secretKeyFile}"
      "stripe-webhook-secret:${toString stripeCfg.webhookSecretFile}"
    ];
  };
in
{
  imports = [
    (
      {
        config,
        pkgs,
        modulesPath,
        lib,
        ...
      }:
      import "${ihp}/NixSupport/nixosModules/options.nix" {
        inherit
          self
          config
          pkgs
          modulesPath
          lib
          ;
      }
    )
    (
      {
        config,
        pkgs,
        modulesPath,
        lib,
        ...
      }:
      import "${ihp}/NixSupport/nixosModules/binaryCache.nix" {
        inherit
          config
          pkgs
          modulesPath
          lib
          ihp
          ;
        nixpkgs = pkgs.path;
      }
    )
    (
      {
        config,
        pkgs,
        modulesPath,
        lib,
        ...
      }:
      import "${ihp}/NixSupport/nixosModules/services/app.nix" {
        inherit
          config
          pkgs
          modulesPath
          lib
          self
          ;
      }
    )
    (
      {
        config,
        pkgs,
        modulesPath,
        lib,
        ...
      }:
      import "${ihp}/NixSupport/nixosModules/services/worker.nix" {
        inherit
          config
          pkgs
          lib
          self
          ;
      }
    )
    (
      {
        config,
        pkgs,
        modulesPath,
        lib,
        ...
      }:
      import "${ihp}/NixSupport/nixosModules/services/app-keygen.nix" {
        inherit
          config
          pkgs
          modulesPath
          lib
          self
          ;
      }
    )
    (
      { config, pkgs, ... }:
      import "${ihp}/NixSupport/nixosModules/services/loadSchema.nix" {
        inherit
          self
          config
          pkgs
          ihp
          ;
      }
    )
    (
      {
        config,
        pkgs,
        modulesPath,
        lib,
        ...
      }:
      import "${ihp}/NixSupport/nixosModules/services/migrate.nix" {
        inherit
          config
          pkgs
          lib
          ihp
          ;
      }
    )
  ];

  options.services.ihpRoster = {
    enable = mkEnableOption "ihp-roster application service";

    domain = mkOption {
      type = types.str;
      default = "localhost";
      description = "Public domain used for IHP base URL and optional nginx wiring.";
    };

    baseUrl = mkOption {
      type = types.str;
      default = "https://${cfg.domain}";
      description = "Base URL exposed to the application runtime.";
    };

    appPort = mkOption {
      type = types.port;
      default = 8000;
      description = "Local port the IHP app socket binds to.";
    };

    mailFrom = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional MAIL_FROM address exposed to the app environment.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional systemd environment file layered onto app/worker services and sweep jobs for shared secrets.";
    };

    sessionSecret = mkOption {
      type = types.str;
      default = "";
      description = "IHP session secret. Leave empty only when provided via environmentFile.";
    };

    sessionSecretFile = mkOption {
      type = types.path;
      default = "/var/ihp/session.aes";
      description = "Path to the generated or provisioned IHP session secret file.";
    };

    additionalEnvVars = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional non-secret environment variables for the app runtime.";
    };

    databaseUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Database URL used by the app. Required unless managePostgres is enabled.";
    };

    databaseName = mkOption {
      type = types.str;
      default = "app";
      description = "Database name used when managePostgres is enabled.";
    };

    databaseUser = mkOption {
      type = types.str;
      default = "root";
      description = "Database role used when managePostgres is enabled.";
    };

    serviceUser = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ihp-roster";
      description = "Optional Unix user used to run app, worker, migration, schema-loading, and bootstrap services.";
    };

    serviceGroup = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ihp-roster";
      description = "Optional Unix group for runtime services. Defaults to serviceUser when unset.";
    };

    createServiceUser = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to create serviceUser as a system user and group.";
    };

    managePostgres = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to provision a local Postgres database for the app.";
    };

    enableMigrations = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to run IHP migrations before starting the app.
        Disable only for pre-V1 disposable deployments that wipe and initialise the database from Schema.sql.
      '';
    };

    postgresAuthentication = mkOption {
      type = types.lines;
      default = ''
        local all postgres peer
        local ${cfg.databaseName} ${cfg.databaseUser} peer
        local all all reject
        host all all 127.0.0.1/32 scram-sha-256
        host all all ::1/128 scram-sha-256
      '';
      description = "Postgres authentication config applied when managePostgres is enabled.";
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Optional app package override. Defaults to this flake's prod package.";
    };

    optimized = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to use the optimized production package output.";
    };

    rtsFlags = mkOption {
      type = types.str;
      default = "-A96m -n4m -N";
      description = "Runtime RTS flags passed to app and worker.";
    };

    configureNginx = mkOption {
      type = types.bool;
      default = false;
      description = "Whether this module should also configure nginx and ACME for the public domain.";
    };

    httpsEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Whether optional nginx wiring should force HTTPS.";
    };

    acmeEmail = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Contact email used for ACME when configureNginx is enabled.";
    };

    bootstrap = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to create an initial super-admin account when no super-admin exists.";
      };

      secretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a sops-nix managed dotenv-style file containing the bootstrap account details.
          Expected keys: BOOTSTRAP_ACCOUNT_EMAIL and BOOTSTRAP_ACCOUNT_PASSWORD.
        '';
      };
    };

    legalDocuments = {
      businessName = mkOption {
        type = types.str;
        default = "Bepis PTY LTD";
        description = "Public business name shown on legal and Stripe activation pages.";
      };

      supportEmail = mkOption {
        type = types.str;
        default = "support@bepis.lol";
        description = "Public support email shown on legal and Stripe activation pages.";
      };

      termsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional file containing the public customer terms body.";
      };

      termsText = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Optional inline public customer terms body. Mutually exclusive with termsFile.";
      };

      privacyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional file containing the public privacy policy body.";
      };

      privacyText = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Optional inline public privacy policy body. Mutually exclusive with privacyFile.";
      };

      refundsDisputesFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional file containing the public refund and dispute policy body.";
      };

      refundsDisputesText = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Optional inline public refund and dispute policy body. Mutually exclusive with refundsDisputesFile.";
      };

      cancellationFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional file containing the public cancellation policy body.";
      };

      cancellationText = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Optional inline public cancellation policy body. Mutually exclusive with cancellationFile.";
      };
    };

    billing.stripe = {
      enable = mkEnableOption "Stripe Billing integration";

      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Optional dotenv-style Stripe environment file layered onto app and worker services.
          Use this when deployment secrets are managed as an environment namespace.
          Prefer secretKeyFile/webhookSecretFile with enable = true for file-backed production credentials.
        '';
      };

      priceLookupKey = mkOption {
        type = types.nullOr types.str;
        default = "bepis_venue_monthly_aud_100";
        description = "Stripe recurring Price lookup key. Set to null only when using priceId fallback.";
      };

      priceId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Direct Stripe Price ID fallback. Prefer priceLookupKey for normal operation.";
      };

      currency = mkOption {
        type = types.str;
        default = "aud";
        description = "Expected launch Stripe Price currency.";
      };

      amountCents = mkOption {
        type = types.int;
        default = 10000;
        description = "Expected launch Stripe Price unit amount in cents.";
      };

      interval = mkOption {
        type = types.str;
        default = "month";
        description = "Expected launch Stripe recurring interval.";
      };

      intervalCount = mkOption {
        type = types.int;
        default = 1;
        description = "Expected launch Stripe recurring interval count.";
      };

      secretKeyFile = mkOption {
        type = types.path;
        default = "/run/secrets/ihp-roster-stripe-secret-key";
        description = "Runtime file containing the Stripe secret key. The key itself must not be stored in Nix.";
      };

      webhookSecretFile = mkOption {
        type = types.path;
        default = "/run/secrets/ihp-roster-stripe-webhook-secret";
        description = "Runtime file containing the Stripe webhook signing secret. The secret itself must not be stored in Nix.";
      };

      paymentMethodTypes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Optional explicit Stripe Checkout payment method type override. Leave empty to use Dashboard configuration.";
      };

      gstRegistered = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the operator is GST registered. Must remain false for launch.";
      };

      automaticTax = mkOption {
        type = types.bool;
        default = false;
        description = "Whether Stripe automatic tax is enabled. Must remain false while GST is disabled.";
      };

      taxIdCollection = mkOption {
        type = types.bool;
        default = false;
        description = "Whether Checkout collects tax IDs. Must remain false while GST is disabled.";
      };
    };

    xero = {
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Optional dotenv-style Xero environment file layered onto app, worker,
          and Xero keepalive services. Expected keys are XERO_CLIENT_ID,
          XERO_CLIENT_SECRET, XERO_REDIRECT_URI, and XERO_TOKEN_ENCRYPTION_KEY.
        '';
      };

      keepalive = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to run the Xero connection keepalive sweep on a systemd timer.";
        };

        onCalendar = mkOption {
          type = types.str;
          default = "daily";
          description = "systemd OnCalendar expression for the Xero keepalive sweep.";
        };

        randomizedDelaySec = mkOption {
          type = types.str;
          default = "30m";
          description = "Randomized delay applied to the Xero keepalive timer.";
        };
      };
    };

    rsa.reminders = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to run the RSA expiry reminder sweep on a systemd timer.";
      };

      onCalendar = mkOption {
        type = types.str;
        default = "daily";
        description = "systemd OnCalendar expression for the RSA reminder sweep.";
      };

      randomizedDelaySec = mkOption {
        type = types.str;
        default = "30m";
        description = "Randomized delay applied to the RSA reminder timer.";
      };
    };

    publicHolidays.refresh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enqueue public holiday refresh jobs on a systemd timer.";
      };

      onCalendar = mkOption {
        type = types.str;
        default = "*-*-01 03:00:00";
        description = "systemd OnCalendar expression for the public holiday refresh sweep.";
      };

      randomizedDelaySec = mkOption {
        type = types.str;
        default = "2h";
        description = "Randomized delay applied to the public holiday refresh timer.";
      };
    };

    fwcMapd.refresh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enqueue FWC MAPD refresh jobs on a systemd timer.";
      };

      onCalendar = mkOption {
        type = types.str;
        default = "*-*-02 03:00:00";
        description = "systemd OnCalendar expression for the FWC MAPD refresh sweep.";
      };

      randomizedDelaySec = mkOption {
        type = types.str;
        default = "2h";
        description = "Randomized delay applied to the FWC MAPD refresh timer.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.databaseUrl != null || cfg.managePostgres;
          message = "services.ihpRoster requires databaseUrl unless managePostgres is enabled.";
        }
        {
          assertion = !(cfg.configureNginx && cfg.httpsEnabled) || cfg.acmeEmail != null;
          message = "services.ihpRoster.acmeEmail is required when configureNginx and httpsEnabled are enabled.";
        }
        {
          assertion = !cfg.bootstrap.enable || cfg.bootstrap.secretFile != null;
          message = "services.ihpRoster.bootstrap.secretFile is required when bootstrap.enable is true.";
        }
        {
          assertion = !cfg.createServiceUser || hasServiceUser;
          message = "services.ihpRoster.createServiceUser requires serviceUser.";
        }
        {
          assertion =
            !(cfg.createServiceUser && cfg.serviceGroup != null && cfg.serviceGroup != cfg.serviceUser);
          message = "services.ihpRoster.createServiceUser only creates a same-name group; set serviceGroup to null or serviceUser.";
        }
        {
          assertion = !(legalCfg.termsFile != null && legalCfg.termsText != null);
          message = "services.ihpRoster.legalDocuments.termsFile and termsText are mutually exclusive.";
        }
        {
          assertion = !(legalCfg.privacyFile != null && legalCfg.privacyText != null);
          message = "services.ihpRoster.legalDocuments.privacyFile and privacyText are mutually exclusive.";
        }
        {
          assertion = !(legalCfg.refundsDisputesFile != null && legalCfg.refundsDisputesText != null);
          message = "services.ihpRoster.legalDocuments.refundsDisputesFile and refundsDisputesText are mutually exclusive.";
        }
        {
          assertion = !(legalCfg.cancellationFile != null && legalCfg.cancellationText != null);
          message = "services.ihpRoster.legalDocuments.cancellationFile and cancellationText are mutually exclusive.";
        }
        {
          assertion =
            !stripeCfg.enable || ((stripeCfg.priceLookupKey != null) != (stripeCfg.priceId != null));
          message = "services.ihpRoster.billing.stripe requires exactly one of priceLookupKey or priceId when enabled.";
        }
        {
          assertion = !stripeCfg.enable || stripeCfg.currency == "aud";
          message = "services.ihpRoster.billing.stripe.currency must be aud for launch.";
        }
        {
          assertion = !stripeCfg.enable || stripeCfg.amountCents == 10000;
          message = "services.ihpRoster.billing.stripe.amountCents must be 10000 for launch.";
        }
        {
          assertion = !stripeCfg.enable || stripeCfg.interval == "month";
          message = "services.ihpRoster.billing.stripe.interval must be month for launch.";
        }
        {
          assertion = !stripeCfg.enable || stripeCfg.intervalCount == 1;
          message = "services.ihpRoster.billing.stripe.intervalCount must be 1 for launch.";
        }
        {
          assertion = !stripeCfg.enable || (!stripeCfg.gstRegistered && !stripeCfg.automaticTax && !stripeCfg.taxIdCollection);
          message = "services.ihpRoster.billing.stripe must keep gstRegistered, automaticTax, and taxIdCollection false for launch.";
        }
      ];
      services.ihp = {
        enable = true;
        domain = cfg.domain;
        baseUrl = cfg.baseUrl;
        migrations = if cfg.enableMigrations then ../../../Application/Migration else null;
        schema = ../../../Application/Schema.sql;
        httpsEnabled = cfg.httpsEnabled;
        databaseName = cfg.databaseName;
        databaseUser = cfg.databaseUser;
        databaseUrl =
          if cfg.databaseUrl != null then
            cfg.databaseUrl
          else
            "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
        sessionSecret = cfg.sessionSecret;
        sessionSecretFile = cfg.sessionSecretFile;
        additionalEnvVars = {
          IHP_TELEMETRY_DISABLED = "1";
          APP_BASE_URL = cfg.baseUrl;
        }
        // mailEnv
        // legalEnv
        // stripeEnv
        // cfg.additionalEnvVars;
        appPort = cfg.appPort;
        package = if cfg.package != null then cfg.package else defaultPackage;
        optimized = cfg.optimized;
        rtsFlags = cfg.rtsFlags;
      };

      systemd.services.app.serviceConfig = serviceUserConfig // stripeCredentialConfig // {
        EnvironmentFile = appWorkerEnvironmentFiles;
      };
      systemd.services.worker.serviceConfig = serviceUserConfig // stripeCredentialConfig // {
        EnvironmentFile = appWorkerEnvironmentFiles;
      };
      systemd.services.worker.enable = mkForce hasJobRunner;
      systemd.services.app-keygen.postStart = mkIf hasServiceUser ''
        ${pkgs.coreutils}/bin/chown ${cfg.serviceUser}:${effectiveServiceGroup} ${cfg.sessionSecretFile}
      '';
      systemd.services.loadSchema = {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        before = optional cfg.enableMigrations "migrate.service" ++ [
          "app.service"
          "worker.service"
        ];
        path = [
          pkgs.postgresql
          pkgs.gnugrep
        ];
        serviceConfig = serviceUserConfig;
        script = mkForce ''
          DB_URL=''${DATABASE_URL:-''${DEFAULT_DATABASE_URL}}
          if ${pkgs.postgresql}/bin/psql "$DB_URL" -tAc "SELECT to_regtype('public.venue_status_enum') IS NOT NULL" | grep -q t; then
              exit 0
          fi

          ${pkgs.postgresql}/bin/psql "$DB_URL" < ${self.packages.${pkgs.system}.ihp-schema}/IHPSchema.sql
          ${pkgs.postgresql}/bin/psql "$DB_URL" < ${self.packages.${pkgs.system}.schema}/Schema.sql
        '';
      };
      systemd.services.migrate = mkIf cfg.enableMigrations {
        after = [ "loadSchema.service" ];
        requires = [ "loadSchema.service" ];
        before = [
          "app.service"
          "worker.service"
        ];
        serviceConfig = serviceUserConfig;
      };
      systemd.services.app.after = [
        schemaReadyService
      ]
      ++ optional cfg.bootstrap.enable "bootstrap-account.service";
      systemd.services.app.requires = [
        schemaReadyService
      ]
      ++ optional cfg.bootstrap.enable "bootstrap-account.service";
      systemd.services.worker.after = [
        schemaReadyService
      ]
      ++ optional cfg.bootstrap.enable "bootstrap-account.service";
      systemd.services.worker.requires = [
        schemaReadyService
      ]
      ++ optional cfg.bootstrap.enable "bootstrap-account.service";
      systemd.services.bootstrap-account = mkIf cfg.bootstrap.enable {
        description = "Seed bootstrap account for ihp-roster";
        after = [ schemaReadyService ];
        requires = [ schemaReadyService ];
        before = [
          "app.service"
          "worker.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          LoadCredential = [ "bootstrap-account:${toString cfg.bootstrap.secretFile}" ];
          ExecStart = pkgs.writeShellScript "ihp-roster-bootstrap-account" ''
            export BOOTSTRAP_ACCOUNT_SECRET_FILE="$CREDENTIALS_DIRECTORY/bootstrap-account"
            exec ${if cfg.package != null then cfg.package else defaultPackage}/bin/BootstrapAccount
          '';
        }
        // serviceUserConfig;
        environment = {
          DATABASE_URL =
            if cfg.databaseUrl != null then
              cfg.databaseUrl
            else
              "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
        };
      };
      systemd.services.xero-keepalive-sweep = mkIf cfg.xero.keepalive.enable {
        description = "Enqueue Xero connection keepalive jobs for ihp-roster";
        after = [ schemaReadyService ];
        requires = [ schemaReadyService ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = xeroEnvironmentFiles;
          ExecStart = "${if cfg.package != null then cfg.package else defaultPackage}/bin/XeroKeepaliveSweep";
        }
        // serviceUserConfig;
        environment = {
          DATABASE_URL =
            if cfg.databaseUrl != null then
              cfg.databaseUrl
            else
              "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
          IHP_TELEMETRY_DISABLED = "1";
          APP_BASE_URL = cfg.baseUrl;
        }
        // mailEnv
        // cfg.additionalEnvVars;
      };
      systemd.timers.xero-keepalive-sweep = mkIf cfg.xero.keepalive.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.xero.keepalive.onCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.xero.keepalive.randomizedDelaySec;
        };
      };
      systemd.services.rsa-reminder-sweep = mkIf cfg.rsa.reminders.enable {
        description = "Enqueue RSA expiry reminder jobs for ihp-roster";
        after = [ schemaReadyService ];
        requires = [ schemaReadyService ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = runtimeEnvironmentFiles;
          ExecStart = "${if cfg.package != null then cfg.package else defaultPackage}/bin/RsaReminderSweep";
        }
        // serviceUserConfig;
        environment = {
          DATABASE_URL =
            if cfg.databaseUrl != null then
              cfg.databaseUrl
            else
              "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
          IHP_TELEMETRY_DISABLED = "1";
          APP_BASE_URL = cfg.baseUrl;
        }
        // mailEnv
        // cfg.additionalEnvVars;
      };
      systemd.timers.rsa-reminder-sweep = mkIf cfg.rsa.reminders.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.rsa.reminders.onCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.rsa.reminders.randomizedDelaySec;
        };
      };
      systemd.services.public-holiday-refresh-sweep = mkIf cfg.publicHolidays.refresh.enable {
        description = "Enqueue public holiday refresh jobs for ihp-roster";
        after = [ schemaReadyService ];
        requires = [ schemaReadyService ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = runtimeEnvironmentFiles;
          ExecStart = "${if cfg.package != null then cfg.package else defaultPackage}/bin/PublicHolidayRefreshSweep";
          NoNewPrivileges = true;
          PrivateTmp = true;
        }
        // serviceUserConfig;
        environment = {
          DATABASE_URL =
            if cfg.databaseUrl != null then
              cfg.databaseUrl
            else
              "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
          IHP_TELEMETRY_DISABLED = "1";
          APP_BASE_URL = cfg.baseUrl;
        }
        // cfg.additionalEnvVars;
      };
      systemd.timers.public-holiday-refresh-sweep = mkIf cfg.publicHolidays.refresh.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.publicHolidays.refresh.onCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.publicHolidays.refresh.randomizedDelaySec;
        };
      };
      systemd.services.fwc-mapd-refresh-sweep = mkIf cfg.fwcMapd.refresh.enable {
        description = "Enqueue FWC MAPD refresh jobs for ihp-roster";
        after = [ schemaReadyService ];
        requires = [ schemaReadyService ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = runtimeEnvironmentFiles;
          ExecStart = "${if cfg.package != null then cfg.package else defaultPackage}/bin/FwcMapdRefreshSweep";
          NoNewPrivileges = true;
          PrivateTmp = true;
        }
        // serviceUserConfig;
        environment = {
          DATABASE_URL =
            if cfg.databaseUrl != null then
              cfg.databaseUrl
            else
              "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
          IHP_TELEMETRY_DISABLED = "1";
          APP_BASE_URL = cfg.baseUrl;
        }
        // cfg.additionalEnvVars;
      };
      systemd.timers.fwc-mapd-refresh-sweep = mkIf cfg.fwcMapd.refresh.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.fwcMapd.refresh.onCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.fwcMapd.refresh.randomizedDelaySec;
        };
      };
    }
    (mkIf cfg.createServiceUser {
      users.groups.${cfg.serviceUser} = { };
      users.users.${cfg.serviceUser} = {
        isSystemUser = true;
        group = cfg.serviceUser;
      };
    })
    (mkIf cfg.managePostgres {
      services.postgresql = {
        enable = mkDefault true;
        ensureUsers = [
          {
            name = cfg.databaseUser;
            ensureDBOwnership = true;
          }
        ];
        ensureDatabases = [ cfg.databaseName ];
        authentication = mkForce cfg.postgresAuthentication;
      };
    })
    (mkIf cfg.configureNginx {
      networking.firewall.enable = true;
      networking.firewall.allowedTCPPorts = [
        22
        80
        443
      ];

      security.acme = {
        acceptTerms = true;
        defaults.email = cfg.acmeEmail;
      };

      services.nginx = {
        enable = true;
        enableReload = true;
        recommendedProxySettings = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedTlsSettings = true;
        virtualHosts.${cfg.domain} = {
          enableACME = cfg.httpsEnabled;
          forceSSL = cfg.httpsEnabled;
          locations."/" = {
            proxyPass = "http://localhost:${toString cfg.appPort}";
            proxyWebsockets = true;
            extraConfig = "proxy_ssl_server_name on;" + "proxy_pass_header Authorization;";
          };
        };
      };
    })
  ]);
}

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
  migrationDirectory = ../../../Application/Migration;
  normalizeMigrationRevision = revision:
    if revision == "0" then
      revision
    else if lib.hasPrefix "0" revision then
      normalizeMigrationRevision (lib.removePrefix "0" revision)
    else
      revision;
  migrationRevision = fileName:
    let
      match = builtins.match "([0-9]+).*\\.sql" fileName;
    in
    if match == null then null else normalizeMigrationRevision (builtins.elemAt match 0);
  migrationRevisions = builtins.filter (revision: revision != null) (
    map migrationRevision (builtins.attrNames (builtins.readDir migrationDirectory))
  );
  expectedMigrationRevisions = lib.concatStringsSep "\n" migrationRevisions;
  schemaReadyService = if cfg.enableMigrations then "schema-migrations-ready.service" else "loadSchema.service";

  serviceUserConfig = optionalAttrs hasServiceUser {
    User = cfg.serviceUser;
    Group = effectiveServiceGroup;
    UMask = "0077";
  };

  defaultPackage =
    if cfg.production then
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
  otelCfg = cfg.observability.otel;
  collectorCfg = cfg.observability.collector;
  tempoCfg = cfg.observability.tempo;
  lokiCfg = cfg.observability.loki;
  profilingCfg = cfg.observability.profiling;
  serviceRevision =
    if self ? rev then self.rev
    else if self ? dirtyRev then self.dirtyRev
    else "unknown";
  serviceVersion = builtins.substring 0 (builtins.min 12 (builtins.stringLength serviceRevision)) serviceRevision;
  otelResourceAttributes = lib.concatStringsSep "," [
    "deployment.environment.name=${otelCfg.deploymentEnvironment}"
    "service.version=${serviceVersion}"
    "service.instance.id=${config.networking.hostName}"
    "host.name=${config.networking.hostName}"
    "bepis.deployment.slot=${otelCfg.deploymentSlot}"
    "vcs.ref.head.revision=${serviceRevision}"
  ];
  observabilityEnv =
    optionalAttrs otelCfg.enable {
      IHP_ROSTER_OTEL = "1";
      IHP_ROSTER_OTEL_SHUTDOWN_TIMEOUT_MS = "2000";
      OTEL_SERVICE_NAME = otelCfg.serviceName;
      OTEL_RESOURCE_ATTRIBUTES = otelResourceAttributes;
      OTEL_EXPORTER_OTLP_ENDPOINT = otelCfg.endpoint;
      OTEL_TRACES_SAMPLER = otelCfg.sampler;
      OTEL_TRACES_SAMPLER_ARG = otelCfg.samplerArg;
      OTEL_BSP_MAX_QUEUE_SIZE = "512";
      OTEL_BSP_MAX_EXPORT_BATCH_SIZE = "128";
      OTEL_BSP_SCHEDULE_DELAY = "1000";
      OTEL_BSP_EXPORT_TIMEOUT = "1000";
      OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT = "256";
      OTEL_ATTRIBUTE_COUNT_LIMIT = "64";
      OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT = "256";
      OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT = "64";
      OTEL_SPAN_EVENT_COUNT_LIMIT = "64";
      OTEL_SPAN_LINK_COUNT_LIMIT = "16";
    }
    // optionalAttrs profilingCfg.enable {
      IHP_ROSTER_PROFILING = "1";
    };
  stripeEnv =
    {
      STRIPE_BILLING_ENABLED = boolEnv stripeCfg.enable;
      STRIPE_CHECKOUT_ENABLED = boolEnv stripeCfg.checkoutEnabled;
      STRIPE_OWNER_NAVIGATION_VISIBLE = boolEnv stripeCfg.ownerNavigationVisible;
    }
    // optionalAttrs stripeCfg.enable (
      {
        STRIPE_MODE = stripeCfg.mode;
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
  stripeAuthoritativeEnvFor = serviceName:
    stripeEnv
    // {
      APP_BASE_URL = cfg.baseUrl;
      STRIPE_MODE = stripeCfg.mode;
      STRIPE_PRICE_LOOKUP_KEY = if stripeCfg.priceLookupKey == null then "" else stripeCfg.priceLookupKey;
      STRIPE_PRICE_ID = if stripeCfg.priceId == null then "" else stripeCfg.priceId;
      STRIPE_PAYMENT_METHOD_TYPES = lib.concatStringsSep "," stripeCfg.paymentMethodTypes;
      STRIPE_SECRET_KEY_FILE = "/run/credentials/${serviceName}.service/stripe-secret-key";
      STRIPE_WEBHOOK_SECRET_FILE = "/run/credentials/${serviceName}.service/stripe-webhook-secret";
    };
  stripeAuthoritativeEnvironmentFile = serviceName:
    pkgs.writeText "ihp-roster-stripe-${serviceName}-environment" (
      (lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name}=${value}") (stripeAuthoritativeEnvFor serviceName)))
      + "\n"
    );
  runtimeEnvironmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;
  xeroEnvironmentFiles = runtimeEnvironmentFiles ++ optional (cfg.xero.environmentFile != null) cfg.xero.environmentFile;
  appWorkerEnvironmentFiles = xeroEnvironmentFiles;
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

  options.services.ihp = {
    withHoogle = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable Hoogle in the IHP dev shell and IHP_HOOGLE_PORT environment wiring.";
    };
  };

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

    observability = {
      otel = {
        enable = mkEnableOption "lightweight OpenTelemetry tracing for ihp-roster";

        serviceName = mkOption {
          type = types.str;
          default = "ihp-roster";
          description = "OTEL_SERVICE_NAME exposed to the app when OpenTelemetry tracing is enabled.";
        };

        endpoint = mkOption {
          type = types.str;
          default = "http://${cfg.observability.collector.receiverAddress}:${toString cfg.observability.collector.otlpHttpPort}";
          defaultText = "http://<collector.receiverAddress>:<collector.otlpHttpPort>";
          description = "OTLP HTTP endpoint used by the app exporter. Defaults to the local collector receiver and should remain localhost for production ingestion.";
        };

        sampler = mkOption {
          type = types.str;
          default = "parentbased_traceidratio";
          description = "OTEL_TRACES_SAMPLER used for lightweight production tracing.";
        };

        samplerArg = mkOption {
          type = types.str;
          default = "0.01";
          description = "OTEL_TRACES_SAMPLER_ARG used with the configured sampler.";
        };

        deploymentEnvironment = mkOption {
          type = types.str;
          default = if cfg.production then "production" else "development";
          description = "Low-cardinality deployment.environment.name resource value.";
        };

        deploymentSlot = mkOption {
          type = types.str;
          default = if cfg.production then "production" else "development";
          description = "Low-cardinality Bepis deployment slot resource value.";
        };
      };

      profiling = {
        enable = mkEnableOption "diagnostic request/render profiling for ihp-roster";
      };

      collector = {
        enable = mkEnableOption "local OpenTelemetry collector for ihp-roster telemetry capture";

        package = mkOption {
          type = types.package;
          default = pkgs.opentelemetry-collector-contrib;
          defaultText = "pkgs.opentelemetry-collector-contrib";
          description = "Collector package to use when production collector services are enabled by follow-on infrastructure tickets.";
        };

        receiverAddress = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address for OTLP ingestion. Keep this localhost in production; tailnet exposure is for query APIs, not ingestion.";
        };

        otlpHttpPort = mkOption {
          type = types.port;
          default = 4318;
          description = "Local OTLP/HTTP receiver port.";
        };

        otlpGrpcPort = mkOption {
          type = types.port;
          default = 4317;
          description = "Local OTLP/gRPC receiver port.";
        };

        tailnetQueryAddress = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "100.64.0.10";
          description = "Optional tailnet address for collector diagnostics/query surfaces. Does not affect OTLP ingestion, which defaults to localhost.";
        };
      };

      tempo = {
        enable = mkEnableOption "local Tempo trace storage for ihp-roster observability";

        dataDir = mkOption {
          type = types.path;
          default = "/var/lib/ihp-roster/tempo";
          description = "Local Tempo data directory. Production trace storage stays on the production host so NAS/Grafana outages do not lose capture-critical data.";
        };

        queryAddress = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "100.64.0.10";
          description = "Optional tailnet-only Tempo query listen address. Leave null to avoid exposing query APIs.";
        };
      };

      loki = {
        enable = mkEnableOption "local Loki log storage for ihp-roster observability";

        dataDir = mkOption {
          type = types.path;
          default = "/var/lib/ihp-roster/loki";
          description = "Local Loki data directory for app logs and future trace/log correlation.";
        };

        queryAddress = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "100.64.0.10";
          description = "Optional tailnet-only Loki query listen address. Leave null to avoid exposing query APIs.";
        };
      };
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
      description = "Optional app package override. Defaults to this flake's package for this deployment profile.";
    };

    production = mkOption {
      type = types.bool;
      default = false;
      description = "Use production profile: optimized output with hoogle disabled.";
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

    security = {
      requirePrivilegedStrongAuthentication = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether privileged users must complete strong authentication before
          restricted venue and platform administration. The current strong
          authentication mechanism is passkey setup/step-up; this option is
          intentionally provider-neutral for future OAuth or other factors.
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

      mode = mkOption {
        type = types.enum [ "test" "live" ];
        default = "test";
        description = "Stripe provider mode. Production billing must set live; development uses test.";
      };

      checkoutEnabled = mkOption {
        type = types.bool;
        default = false;
        description = "Whether authenticated owners may create new Stripe Checkout Sessions.";
      };

      ownerNavigationVisible = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the owner Billing link is visible. Direct-route authorization remains unchanged.";
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

      reconciliationSweep = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enqueue reconciliation jobs for known non-terminal Stripe subscriptions on a systemd timer when Stripe Billing is enabled.";
        };

        onCalendar = mkOption {
          type = types.str;
          default = "daily";
          description = "systemd OnCalendar expression for the Stripe subscription reconciliation sweep.";
        };

        randomizedDelaySec = mkOption {
          type = types.str;
          default = "30m";
          description = "Randomized delay applied to the Stripe subscription reconciliation timer.";
        };
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
          description = "Whether to run the Xero reference-sync and token-keepalive maintenance sweep on a systemd timer.";
        };

        onCalendar = mkOption {
          type = types.str;
          default = "daily";
          description = "systemd OnCalendar expression for the Xero maintenance sweep.";
        };

        randomizedDelaySec = mkOption {
          type = types.str;
          default = "30m";
          description = "Randomized delay applied to the Xero keepalive timer.";
        };
      };
    };

    liveInvalidations.outboxPruning = {
      enable = mkEnableOption "durable live-invalidation outbox pruning";

      retentionDays = mkOption {
        type = types.ints.positive;
        default = 7;
        description = "Retention in whole days for durable live-invalidation event history. Values below seven days are rejected.";
      };

      batchSize = mkOption {
        type = types.ints.positive;
        default = 1000;
        description = "Maximum event headers deleted in one pruning transaction. Values above 1000 are rejected.";
      };

      onCalendar = mkOption {
        type = types.str;
        default = "daily";
        description = "systemd OnCalendar expression for live-invalidation outbox pruning.";
      };

      randomizedDelaySec = mkOption {
        type = types.str;
        default = "30m";
        description = "Randomized delay applied to the live-invalidation outbox pruning timer.";
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
        default = "Sun *-*-* 03:00:00";
        description = "systemd OnCalendar expression for the weekly FWC MAPD refresh sweep. Keep successful refreshes within the eight-day wage-source freshness limit.";
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
          assertion = !cfg.liveInvalidations.outboxPruning.enable || hasServiceUser;
          message = "services.ihpRoster.liveInvalidations.outboxPruning requires serviceUser so the maintenance unit never runs as root.";
        }
        {
          assertion = cfg.liveInvalidations.outboxPruning.retentionDays >= 7;
          message = "services.ihpRoster.liveInvalidations.outboxPruning.retentionDays cannot be shorter than seven days.";
        }
        {
          assertion = cfg.liveInvalidations.outboxPruning.batchSize <= 1000;
          message = "services.ihpRoster.liveInvalidations.outboxPruning.batchSize cannot exceed 1000 events per transaction.";
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
          assertion = otelCfg.enable -> collectorCfg.enable || lib.hasPrefix "http://127.0.0.1:" otelCfg.endpoint || lib.hasPrefix "http://localhost:" otelCfg.endpoint;
          message = "services.ihpRoster.observability.otel.endpoint should use the local collector by default; enable observability.collector or set an explicit localhost endpoint.";
        }
        {
          assertion = collectorCfg.receiverAddress == "127.0.0.1" || collectorCfg.receiverAddress == "localhost";
          message = "services.ihpRoster.observability.collector.receiverAddress must remain localhost; use Tempo/Loki queryAddress for tailnet query exposure.";
        }
        {
          assertion = tempoCfg.queryAddress == null || tempoCfg.enable;
          message = "services.ihpRoster.observability.tempo.queryAddress requires tempo.enable.";
        }
        {
          assertion = lokiCfg.queryAddress == null || lokiCfg.enable;
          message = "services.ihpRoster.observability.loki.queryAddress requires loki.enable.";
        }
        {
          assertion = !stripeCfg.checkoutEnabled || stripeCfg.enable;
          message = "services.ihpRoster.billing.stripe.checkoutEnabled requires billing.stripe.enable.";
        }
        {
          assertion = !stripeCfg.ownerNavigationVisible || stripeCfg.enable;
          message = "services.ihpRoster.billing.stripe.ownerNavigationVisible requires billing.stripe.enable.";
        }
        {
          assertion = !cfg.production || !stripeCfg.enable || stripeCfg.mode == "live";
          message = "services.ihpRoster production billing requires billing.stripe.mode = live.";
        }
        {
          assertion = !stripeCfg.enable || stripeCfg.mode != "live" || lib.hasPrefix "https://" cfg.baseUrl;
          message = "services.ihpRoster.billing.stripe live mode requires an HTTPS services.ihpRoster.baseUrl.";
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
        migrations = if cfg.enableMigrations then migrationDirectory else null;
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
          IHP_ROSTER_REQUIRE_PRIVILEGED_STRONG_AUTH = boolEnv cfg.security.requirePrivilegedStrongAuthentication;
        }
        // mailEnv
        // legalEnv
        // observabilityEnv
        // cfg.additionalEnvVars
        // stripeEnv;
        appPort = cfg.appPort;
        package = if cfg.package != null then cfg.package else defaultPackage;
        optimized = cfg.production;
        withHoogle = !cfg.production;
        rtsFlags = cfg.rtsFlags;
      };

      systemd.services.app.serviceConfig = serviceUserConfig // stripeCredentialConfig // {
        EnvironmentFile = appWorkerEnvironmentFiles ++ [ (stripeAuthoritativeEnvironmentFile "app") ];
      };
      systemd.services.worker.serviceConfig = serviceUserConfig // stripeCredentialConfig // {
        EnvironmentFile = appWorkerEnvironmentFiles ++ [ (stripeAuthoritativeEnvironmentFile "worker") ];
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
        serviceConfig = serviceUserConfig // optionalAttrs (appWorkerEnvironmentFiles != [ ]) {
          EnvironmentFile = appWorkerEnvironmentFiles;
        };
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
        before = [ "wage-cutover.service" ];
        serviceConfig = serviceUserConfig // optionalAttrs (appWorkerEnvironmentFiles != [ ]) {
          EnvironmentFile = appWorkerEnvironmentFiles;
        };
      };
      systemd.services.wage-cutover = mkIf cfg.enableMigrations {
        description = "Backfill immutable Haskell wage facts and retire legacy SQL calculators";
        after = [ "migrate.service" ];
        requires = [ "migrate.service" ];
        before = [ "schema-migrations-ready.service" ];
        environment.DEFAULT_DATABASE_URL =
          if cfg.databaseUrl != null then
            cfg.databaseUrl
          else
            "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
        path = [ pkgs.postgresql ];
        serviceConfig = serviceUserConfig // {
          Type = "oneshot";
        } // optionalAttrs (appWorkerEnvironmentFiles != [ ]) {
          EnvironmentFile = appWorkerEnvironmentFiles;
        };
        script = ''
          DB_URL=''${DATABASE_URL:-''${DEFAULT_DATABASE_URL}}
          export DATABASE_URL="$DB_URL"
          ${if cfg.package != null then cfg.package else defaultPackage}/bin/BackfillTimesheetPayLedger
          ${pkgs.postgresql}/bin/psql "$DB_URL" -v ON_ERROR_STOP=1 \
            -f ${../../../Application/Deployment/retire-legacy-wage-calculators.sql}
        '';
      };
      systemd.services.schema-migrations-ready = mkIf cfg.enableMigrations {
        description = "Verify all deployed ihp-roster migrations are applied";
        after = [ "wage-cutover.service" ];
        requires = [ "wage-cutover.service" ];
        before = [
          "app.service"
          "worker.service"
        ] ++ optional cfg.bootstrap.enable "bootstrap-account.service";
        environment.DEFAULT_DATABASE_URL =
          if cfg.databaseUrl != null then
            cfg.databaseUrl
          else
            "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
        path = [
          pkgs.coreutils
          pkgs.postgresql
        ];
        serviceConfig = serviceUserConfig // optionalAttrs (appWorkerEnvironmentFiles != [ ]) {
          EnvironmentFile = appWorkerEnvironmentFiles;
        } // {
          Type = "oneshot";
        };
        script = ''
          DB_URL=''${DATABASE_URL:-''${DEFAULT_DATABASE_URL}}
          expected_file=$(mktemp)
          applied_file=$(mktemp)
          missing_file=$(mktemp)
          trap 'rm -f "$expected_file" "$applied_file" "$missing_file"' EXIT

          cat > "$expected_file" <<'EXPECTED_REVISIONS'
          ${expectedMigrationRevisions}
          EXPECTED_REVISIONS
          sort -o "$expected_file" "$expected_file"

          ${pkgs.postgresql}/bin/psql "$DB_URL" -v ON_ERROR_STOP=1 --tuples-only --no-align \
            --command="SELECT revision FROM schema_migrations" \
            | sort > "$applied_file"

          comm -23 "$expected_file" "$applied_file" > "$missing_file"
          if [ -s "$missing_file" ]; then
            echo "Refusing to start ihp-roster: deployed migrations are missing:" >&2
            cat "$missing_file" >&2
            exit 1
          fi
        '';
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
        // serviceUserConfig
        // optionalAttrs (appWorkerEnvironmentFiles != [ ]) {
          EnvironmentFile = appWorkerEnvironmentFiles;
        };
        environment = {
          DATABASE_URL =
            if cfg.databaseUrl != null then
              cfg.databaseUrl
            else
              "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
        };
      };
      systemd.services.billing-reconciliation-sweep = mkIf (stripeCfg.enable && stripeCfg.reconciliationSweep.enable) {
        description = "Enqueue Stripe subscription reconciliation jobs for ihp-roster";
        after = [ schemaReadyService ];
        requires = [ schemaReadyService ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${if cfg.package != null then cfg.package else defaultPackage}/bin/BillingReconciliationSweep";
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
        };
      };
      systemd.timers.billing-reconciliation-sweep = mkIf (stripeCfg.enable && stripeCfg.reconciliationSweep.enable) {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = stripeCfg.reconciliationSweep.onCalendar;
          Persistent = true;
          RandomizedDelaySec = stripeCfg.reconciliationSweep.randomizedDelaySec;
        };
      };
      systemd.services.xero-keepalive-sweep = mkIf cfg.xero.keepalive.enable {
        description = "Enqueue Xero reference-sync and token-keepalive jobs for ihp-roster";
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
      systemd.services.live-invalidation-outbox-prune = mkIf cfg.liveInvalidations.outboxPruning.enable {
        description = "Prune expired durable live-invalidation outbox events";
        after = [ schemaReadyService ];
        requires = [ schemaReadyService ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${if cfg.package != null then cfg.package else defaultPackage}/bin/LiveInvalidationOutboxPrune";
          Restart = "on-failure";
          RestartSec = "5m";
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          CapabilityBoundingSet = "";
          SystemCallArchitectures = "native";
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        }
        // serviceUserConfig;
        environment = {
          DATABASE_URL =
            if cfg.databaseUrl != null then
              cfg.databaseUrl
            else
              "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
          LIVE_INVALIDATION_OUTBOX_RETENTION_DAYS = toString cfg.liveInvalidations.outboxPruning.retentionDays;
          LIVE_INVALIDATION_OUTBOX_BATCH_SIZE = toString cfg.liveInvalidations.outboxPruning.batchSize;
        };
      };
      systemd.timers.live-invalidation-outbox-prune = mkIf cfg.liveInvalidations.outboxPruning.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.liveInvalidations.outboxPruning.onCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.liveInvalidations.outboxPruning.randomizedDelaySec;
          Unit = "live-invalidation-outbox-prune.service";
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

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
    hasJobRunner = builtins.pathExists ../../../Application/Job;

    defaultPackage =
        if cfg.optimized
            then self.packages.${pkgs.system}.optimized-prod-server
            else self.packages.${pkgs.system}.default;

    mailEnv = optionalAttrs (cfg.mailFrom != null) {
        MAIL_FROM = cfg.mailFrom;
    };
in
{
    imports = [
        ({ config, pkgs, modulesPath, lib, ... }:
            import "${ihp}/NixSupport/nixosModules/options.nix" {
                inherit self config pkgs modulesPath lib;
            }
        )
        ({ config, pkgs, modulesPath, lib, ... }:
            import "${ihp}/NixSupport/nixosModules/binaryCache.nix" {
                inherit config pkgs modulesPath lib ihp;
                nixpkgs = pkgs.path;
            }
        )
        ({ config, pkgs, modulesPath, lib, ... }:
            import "${ihp}/NixSupport/nixosModules/services/app.nix" {
                inherit config pkgs modulesPath lib self;
            }
        )
        ({ config, pkgs, modulesPath, lib, ... }:
            import "${ihp}/NixSupport/nixosModules/services/worker.nix" {
                inherit config pkgs lib self;
            }
        )
        ({ config, pkgs, modulesPath, lib, ... }:
            import "${ihp}/NixSupport/nixosModules/services/app-keygen.nix" {
                inherit config pkgs modulesPath lib self;
            }
        )
        ({ config, pkgs, ... }:
            import "${ihp}/NixSupport/nixosModules/services/loadSchema.nix" {
                inherit self config pkgs ihp;
            }
        )
        ({ config, pkgs, modulesPath, lib, ... }:
            import "${ihp}/NixSupport/nixosModules/services/migrate.nix" {
                inherit config pkgs lib ihp;
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
            description = "Optional systemd environment file layered onto app/worker services for secrets.";
        };

        sessionSecret = mkOption {
            type = types.str;
            default = "";
            description = "IHP session secret. Leave empty only when provided via environmentFile.";
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

        managePostgres = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to provision a local Postgres database for the app.";
        };

        postgresAuthentication = mkOption {
            type = types.lines;
            default = ''
                local all all trust
                host all all 127.0.0.1/32 trust
                host all all ::1/128 trust
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
                description = "Whether to seed a bootstrap super-admin account on deploy.";
            };

            email = mkOption {
                type = types.str;
                default = "admin@example.com";
                description = "Email address for the bootstrap account.";
            };

            passwordFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Path to a file containing the bootstrap account password, suitable for sops-nix secrets.";
            };

            venueName = mkOption {
                type = types.str;
                default = "Bootstrap Venue";
                description = "Venue name created or claimed for the bootstrap account.";
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
                    assertion = !cfg.bootstrap.enable || cfg.bootstrap.passwordFile != null;
                    message = "services.ihpRoster.bootstrap.passwordFile is required when bootstrap.enable is true.";
                }
            ];
            services.ihp = {
                enable = true;
                domain = cfg.domain;
                baseUrl = cfg.baseUrl;
                migrations = ../../../Application/Migration;
                schema = ../../../Application/Schema.sql;
                fixtures = ../../../Application/Fixtures.sql;
                httpsEnabled = cfg.httpsEnabled;
                databaseName = cfg.databaseName;
                databaseUser = cfg.databaseUser;
                databaseUrl =
                    if cfg.databaseUrl != null
                        then cfg.databaseUrl
                        else "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
                sessionSecret =
                    cfg.sessionSecret;
                additionalEnvVars =
                    {
                        IHP_TELEMETRY_DISABLED = "1";
                        APP_BASE_URL = cfg.baseUrl;
                    }
                    // mailEnv
                    // cfg.additionalEnvVars;
                appPort = cfg.appPort;
                package =
                    if cfg.package != null
                        then cfg.package
                        else defaultPackage;
                optimized = cfg.optimized;
                rtsFlags = cfg.rtsFlags;
            };

            systemd.services.app.serviceConfig.EnvironmentFile =
                optional (cfg.environmentFile != null) cfg.environmentFile;
            systemd.services.worker.serviceConfig.EnvironmentFile =
                optional (cfg.environmentFile != null) cfg.environmentFile;
            systemd.services.worker.enable = mkForce hasJobRunner;
            systemd.services.loadSchema = {
                wantedBy = [ "multi-user.target" ];
                before = [ "migrate.service" "app.service" "worker.service" ];
                path = [ pkgs.postgresql pkgs.gnugrep ];
                script = mkForce ''
                    DB_URL=''${DATABASE_URL:-''${DEFAULT_DATABASE_URL}}
                    if ${pkgs.postgresql}/bin/psql "$DB_URL" -tAc "SELECT to_regtype('public.venue_status_enum') IS NOT NULL" | grep -q t; then
                        exit 0
                    fi

                    ${pkgs.postgresql}/bin/psql "$DB_URL" < ${self.packages.${pkgs.system}.ihp-schema}/IHPSchema.sql
                    ${pkgs.postgresql}/bin/psql "$DB_URL" < ${self.packages.${pkgs.system}.schema}/Schema.sql
                '';
            };
            systemd.services.migrate = {
                after = [ "loadSchema.service" ];
                requires = [ "loadSchema.service" ];
                before = [ "app.service" "worker.service" ];
            };
            systemd.services.app = {
                after = [ "migrate.service" ];
                requires = [ "migrate.service" ];
            };
            systemd.services.worker = {
                after = [ "migrate.service" ];
                requires = [ "migrate.service" ];
            };
            systemd.services.bootstrap-account = mkIf cfg.bootstrap.enable {
                description = "Seed bootstrap account for ihp-roster";
                wantedBy = [ "multi-user.target" ];
                after = [ "migrate.service" ];
                requires = [ "migrate.service" ];
                before = [ "app.service" "worker.service" ];
                serviceConfig = {
                    Type = "oneshot";
                    ExecStart = "${if cfg.package != null then cfg.package else defaultPackage}/bin/BootstrapAccount";
                };
                environment = {
                    DATABASE_URL =
                        if cfg.databaseUrl != null
                            then cfg.databaseUrl
                            else "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";
                    BOOTSTRAP_ACCOUNT_EMAIL = cfg.bootstrap.email;
                    BOOTSTRAP_ACCOUNT_PASSWORD_FILE = toString cfg.bootstrap.passwordFile;
                    BOOTSTRAP_ACCOUNT_VENUE_NAME = cfg.bootstrap.venueName;
                };
            };
            systemd.services.app = mkIf cfg.bootstrap.enable {
                after = [ "bootstrap-account.service" ];
                requires = [ "bootstrap-account.service" ];
            };
            systemd.services.worker = mkIf cfg.bootstrap.enable {
                after = [ "bootstrap-account.service" ];
                requires = [ "bootstrap-account.service" ];
            };
        }
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
                authentication = cfg.postgresAuthentication;
            };
        })
        (mkIf cfg.configureNginx {
            networking.firewall.enable = true;
            networking.firewall.allowedTCPPorts = [ 22 80 443 ];

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
                        extraConfig =
                            "proxy_ssl_server_name on;"
                            + "proxy_pass_header Authorization;";
                    };
                };
            };
        })
    ]);
}

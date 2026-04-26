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

  services.ihpRoster = {
    enable = true;
    domain = "CHANGE-ME.com";
    databaseUser = "ihp_roster";
    serviceUser = "ihp_roster";
    createServiceUser = true;
    managePostgres = true;
    configureNginx = true;
    httpsEnabled = true;
    acmeEmail = "CHANGE-ME@example.com";
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

{ config, lib, ... }:

let
  stateDir = "/var/lib/authelia-main";
in
{
  services.authelia.instances.main = {
    enable = true;
    secrets = {
      jwtSecretFile = "/persist/secrets/authelia/jwt-secret";
      storageEncryptionKeyFile = "/persist/secrets/authelia/storage-encryption-key";
    };
    settings = {
      theme = "auto";
      default_2fa_method = "webauthn";
      server.address = "tcp://127.0.0.1:9091/";
      log = {
        level = "info";
        format = "text";
      };
      authentication_backend = {
        password_reset.disable = true;
        file.path = "${stateDir}/users.yml";
      };
      access_control = {
        default_policy = "deny";
        rules = [
          { domain = "money.jrdn.cx"; policy = "two_factor"; }
        ];
      };
      session.cookies = [
        {
          domain = "jrdn.cx";
          authelia_url = "https://auth.jrdn.cx";
          default_redirection_url = "https://money.jrdn.cx";
        }
      ];
      storage.local.path = "${stateDir}/db.sqlite3";
      notifier.filesystem.filename = "${stateDir}/notifications.txt";
      webauthn.display_name = "jrdn.cx";
    };
  };
}

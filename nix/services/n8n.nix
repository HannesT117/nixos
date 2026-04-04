{ config, pkgs, lib, ... }:

let
  # Wrapper that fetches a dynamic grant token from n8n's broker, then starts the runner.
  # In external mode, the broker issues one-time grant tokens via POST /runners/auth.
  taskRunnerWrapper = pkgs.writeShellScript "n8n-task-runner-wrapper" ''
    RESPONSE=$(${pkgs.curl}/bin/curl -sf -X POST \
      "http://127.0.0.1:5679/runners/auth" \
      -H "Content-Type: application/json" \
      -d "{\"token\": \"$N8N_RUNNERS_AUTH_TOKEN\"}")

    GRANT_TOKEN=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.data.token // .token // empty')

    if [ -z "$GRANT_TOKEN" ]; then
      echo "Failed to obtain grant token from broker" >&2
      exit 1
    fi

    export N8N_RUNNERS_GRANT_TOKEN="$GRANT_TOKEN"
    exec ${pkgs.n8n}/bin/n8n-task-runner
  '';
in
{

  users.users.n8n = {
    isSystemUser = true;
    group = "n8n";
    home = "/var/lib/n8n";
  };
  users.groups.n8n = {};

  services.n8n = {
    enable = true;

    environment = {
      N8N_HOST = "0.0.0.0";
      N8N_PORT = "5678";
      N8N_PROTOCOL = "https";
      WEBHOOK_URL = "https://n8n.jrdn.cx";
      N8N_EDITOR_BASE_URL = "https://n8n.jrdn.cx";
      GENERIC_TIMEZONE = "Europe/Berlin";
      N8N_RUNNERS_ENABLED = "true";
      N8N_RUNNERS_MODE = "external";
      N8N_RUNNERS_BROKER_LISTEN_ADDRESS = "0.0.0.0";
      N8N_RUNNERS_BROKER_PORT = "5679";
      N8N_RUNNERS_MAX_CONCURRENCY = "5";
    };
  };

  # Firewall
  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 5678 accept
  '';

  # Disable DynamicUser so impermanence can persist /var/lib/n8n directly.
  # See ./n8n.md
  systemd.services.n8n.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "n8n";
    Group = "n8n";
    StateDirectory = lib.mkForce "n8n";
    StateDirectoryMode = "0700";
    EnvironmentFile = "/persist/secrets/n8n-credentials";
    CapabilityBoundingSet = "";
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
    SystemCallArchitectures = "native";
  };

  # External task runner sidecar — connects to n8n's broker to execute Code nodes.
  # Auth token shared via the same credentials file as n8n.
  systemd.services.n8n-task-runner = {
    description = "n8n Task Runner (external)";
    after = [ "n8n.service" ];
    requires = [ "n8n.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      N8N_RUNNERS_TASK_BROKER_URI = "http://127.0.0.1:5679";
      GENERIC_TIMEZONE = "Europe/Berlin";
    };

    serviceConfig = {
      Type = "simple";
      ExecStart = "${taskRunnerWrapper}";
      Restart = "on-failure";
      RestartSec = "5s";
      User = "n8n";
      Group = "n8n";
      # Shares N8N_RUNNERS_AUTH_TOKEN with the n8n service
      EnvironmentFile = "/persist/secrets/n8n-credentials";
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      SystemCallArchitectures = "native";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}

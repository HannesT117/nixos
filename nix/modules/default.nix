{ inputs, pkgs, ... }: {

  # Nix settings
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
      persistent = false;
    };
    optimise = {
      automatic = true;
      dates = ["weekly"]; # run less frequently
    };
  };

  # Common packages available on all hosts
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    stow
    difftastic
  ];

  # ZSH
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    ohMyZsh = {
      enable = true;
      plugins = [ "git" "thefuck" ];
      theme = "robbyrussell";
    };
  };
  users.defaultUserShell = pkgs.zsh;

  programs.vim.enable = true;

  # Dotfiles (sparse checkout of shared/ only)
  system.activationScripts.dotfiles = ''
    if [ ! -d "/etc/dotfiles/.git" ]; then
      ${pkgs.git}/bin/git clone --no-checkout --filter=blob:none \
        https://github.com/HannesT117/dotfiles.git /etc/dotfiles
      cd /etc/dotfiles
      ${pkgs.git}/bin/git sparse-checkout init --cone
      ${pkgs.git}/bin/git sparse-checkout set shared
      ${pkgs.git}/bin/git checkout main
    else
      ${pkgs.git}/bin/git -C /etc/dotfiles fetch --all
      ${pkgs.git}/bin/git -C /etc/dotfiles reset --hard origin/main
    fi

    if [ -d "/etc/dotfiles/shared" ]; then
      for user in nonroot; do
        home=$(getent passwd "$user" | cut -d: -f6)
        if [ -d "$home" ]; then
          ${pkgs.stow}/bin/stow \
            --dir=/etc/dotfiles \
            --target="$home" \
            --restow \
            shared
          chown -Rh "$user:users" "$home/"
        fi
      done
    fi
  '';
}

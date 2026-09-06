{ pkgs, config, ... }:

{
  cachix.pull = [ "curious" ];

  # From SecretSpec.

  env.NIX_CONFIG = config.secretspec.secrets.NIX_CONFIG or "";

  packages = [
    pkgs.nixfmt
    pkgs.package-version-server
    pkgs.yaml-language-server
    pkgs.npins
  ];

  languages.nix = {
    enable = true;
    lsp.package = pkgs.nixd;
  };

  git-hooks.hooks = {
    # Validate GitHub Actions workflow syntax.
    actionlint.enable = true;

    # Keep consistent with the repository formatter.
    nixfmt.enable = true;

    prettier.enable = true;
    prettier.excludes = [
      ".*\\.age$"
      "^secrets/cache/.*"
    ];

    # Scan staged content for secrets before committing.
    gitleaks = {
      enable = true;
      name = "gitleaks";
      entry = "${pkgs.gitleaks}/bin/gitleaks git --pre-commit --redact --staged --verbose";
      pass_filenames = false;
    };
  };
}

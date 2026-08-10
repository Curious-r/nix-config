{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  # https://devenv.sh/basics/
  env.GREET = "devenv";

  # 订阅自己的 Cachix 缓存：CI 构建产物
  cachix.pull = [ "curious" ];

  # From Secret Spec
  env.NIX_CONFIG = config.secretspec.secrets.NIX_CONFIG or "";

  # https://devenv.sh/packages/
  packages = [
    pkgs.nixfmt
    pkgs.package-version-server
    pkgs.yaml-language-server
  ];

  # https://devenv.sh/languages/
  # languages.rust.enable = true;

  # https://devenv.sh/processes/
  # processes.cargo-watch.exec = "cargo-watch";

  # https://devenv.sh/services/
  # services.postgres.enable = true;

  # https://devenv.sh/scripts/
  scripts.hello.exec = ''
    echo hello from $GREET
  '';

  enterShell = ''
    hello
  '';

  # https://devenv.sh/tasks/
  # tasks = {
  #   "myproj:setup".exec = "mytool build";
  #   "devenv:enterShell".after = [ "myproj:setup" ];
  # };

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
  '';

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
    # 校验 GitHub Actions workflow 语法
    actionlint.enable = true;
    # 与 flake 里 treefmt 使用的 formatter 保持一致
    nixfmt.enable = true;
    prettier.enable = true;
    prettier.excludes = [
      ".*\\.age$"
      "^secrets/cache/.*"
    ];
    # 提交前扫描暂存内容里的密钥（gitleaks 未内置，自定义 hook）
    gitleaks = {
      enable = true;
      name = "gitleaks";
      entry = "${pkgs.gitleaks}/bin/gitleaks git --pre-commit --redact --staged --verbose";
      pass_filenames = false;
    };
  };

  # See full reference at https://devenv.sh/reference/options/
  languages = {
    nix = {
      enable = true;
      lsp.package = pkgs.nixd;
    };
  };
}

{ pkgs, ... }: {
  home.packages = [
    pkgs.llm-agents.command-code
  ];
}

{ pkgs, ... }: {
  home.packages = [
    pkgs.llm-agents.zcode
  ];
}

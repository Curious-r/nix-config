{ pkgs, ... }:
{
  home.packages = [
    pkgs.llm-agents.antigravity-cli
  ];
}

{ pkgs, ... }:
{
  home.packages = [
    pkgs.llm-agents.cc-switch-cli
  ];
}

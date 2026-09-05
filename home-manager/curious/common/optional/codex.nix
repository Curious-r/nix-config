{ pkgs, ... }:
{
  home.packages = [
    pkgs.llm-agents.codex
  ];
}

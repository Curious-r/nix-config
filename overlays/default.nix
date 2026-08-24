{
  # This one brings our custom packages from the 'pkgs' directory.
  # Note: use `final` directly, NOT `final.pkgs`. nixpkgs has a
  # self-reference `pkgs.pkgs = pkgs` for historical compatibility, so
  # `final.pkgs` technically works but is an unnecessary indirection.
  additions = final: _prev: import ../pkgs final;

  # This one contains whatever you want to overlay.
  # You can change versions, add patches, set compilation flags, anything really.
  modifications = _final: _prev: { };
}

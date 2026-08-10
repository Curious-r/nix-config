{ pkgs, ... }:
{
  programs.obs-studio = {
    enable = true;

    # Optional Nvidia hardware acceleration.
    package = (
      pkgs.obs-studio.override {
        cudaSupport = true;
      }
    );

    plugins = [
      pkgs.obs-studio-plugins.wlrobs
      pkgs.obs-studio-plugins.obs-backgroundremoval
      pkgs.obs-studio-plugins.obs-pipewire-audio-capture
      pkgs.obs-studio-plugins.obs-vaapi # optional AMD hardware acceleration
      pkgs.obs-studio-plugins.obs-gstreamer
      pkgs.obs-studio-plugins.obs-vkcapture
    ];
  };
}

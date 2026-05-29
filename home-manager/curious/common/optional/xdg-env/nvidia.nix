{ config, ... }:
{
  home.sessionVariables = {
    CUDA_CACHE_PATH = "${config.xdg.cacheHome}/nv";
  };
}

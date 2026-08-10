{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    # Optional: preload models. See https://ollama.com/library.
    loadModels = [ "hf.co/unsloth/Qwen3.5-0.8B-MTP-GGUF:UD-IQ2_M" ];
  };
}

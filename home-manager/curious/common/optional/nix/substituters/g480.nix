{ ... }:
{
  nix.settings = {
    substituters = [ "http://192.168.32.193:8501" ];
    trusted-public-keys = [
      "Server-Ideapad-G480:il4pFjxCaKM7kFAVmxRHmqYHc+cZFvfpWiBobJ6vmFQ="
    ];
  };
}

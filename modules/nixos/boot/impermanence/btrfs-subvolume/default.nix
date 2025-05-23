# Add your reusable NixOS modules to this directory, on their own file (https://nixos.wiki/wiki/Module).
# These should be stuff you would like to share with others, not your personal configurations.
{ lib, ... }:
{
  imports = [
    ./rollback.nix
    ./restore.nix
  ];
  # stage1 阶段生成持久化目录所需的选项，如果不开启 canTouchEfiVariables，
  # 系统启动时会由于依赖项失败无法挂载sysroot，这时多次尝试重新触发 initrd.target
  # 则可以在某次成功继续启动流程
  # 此外，启用 initrd systemd 也是配合 rollback 服务的需要
  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
  boot.initrd.systemd.enable = lib.mkForce true;

}

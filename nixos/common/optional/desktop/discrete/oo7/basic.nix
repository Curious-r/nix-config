{ pkgs, ... }:
{
  services = {
    gnome.gnome-keyring.enable = false;
    oo7.enable = true;
  };

  # 用于认证弹窗
  environment.systemPackages = with pkgs; [
    gcr
  ];

  # 开启一些基础的规则钩子，等 #544377 合并之后估计会冲突，到时候删除
  security.pam.services = {
    login.oo7.enable = true;
    passwd.oo7.enable = true;
  };
}

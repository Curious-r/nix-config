{ lib, ... }:
{
  i18n.defaultLocale = lib.mkDefault "zh_CN.UTF-8";
  time.timeZone = lib.mkDefault "Asia/Shanghai";
}

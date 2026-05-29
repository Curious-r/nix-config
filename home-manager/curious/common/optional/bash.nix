{ config, ... }:
{
  programs.bash = {
    enable = true;
    # 使用内置选项指定历史文件路径
    historyFile = "${config.xdg.stateHome}/bash/history";
  };
}

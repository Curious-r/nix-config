{ pkgs, lib, ... }:
{
  # all fonts are linked to /nix/var/nix/profiles/system/sw/share/X11/fonts
  fonts = {
    fontDir.enable = lib.mkDefault true;

    packages = with pkgs; [
      # icon fonts
      # material-design-icons
      # font-awesome

      # Noto 系列字体是 Google 主导的。名字的含义是「没有豆腐」（no tofu），因为缺字时显示的方框或者方框被叫作 tofu
      # Noto 系列字族名只支持英文，命名规则是 Noto Sans/Serif <变体名>
      # 其中汉字部分叫 Noto Sans/Serif CJK SC/TC/HK/JP/KR，最后一个词是地区变种
      noto-fonts # 大部分文字的常见样式，不包含汉字
      noto-fonts-cjk-serif # 汉字部分，有衬线
      noto-fonts-cjk-sans # 汉字部分，无衬线
      noto-fonts-color-emoji # 彩色的表情符号字体

      # 思源系列字体是 Adobe 主导的。其中汉字部分被称为「思源黑体」和「思源宋体」，是由 Adobe + Google 共同开发的
      # source-sans # 无衬线字体，不含汉字。字族名是Source Sans Pro（旧版）和Source Sans 3（新版），以及变体
      # source-serif # 衬线字体，不含汉字。字族名应为Source Serif Pro（旧版）或Source Serif 4（新版），以及变体
      # source-code-pro # 等宽编程字体，字族名为Source Code Pro
      # source-han-sans # 思源黑体，包含汉字，字族名为 Source Han Sans <变体名>
      # source-han-serif # 思源宋体，包含汉字，字族名为 Source Han Sans <变体名>

      # nerdfonts
      # https://github.com/NixOS/nixpkgs/blob/nixos-unstable-small/pkgs/data/fonts/nerd-fonts/manifests/fonts.json
      # nerd-fonts.symbols-only # symbols icon only
      # nerd-fonts.fira-code
      # nerd-fonts.jetbrains-mono
      # nerd-fonts.iosevka

      # An innovative superfamily of fonts for code
      # Monaspace Neon, Monaspace Argon, Monaspace Xenon, Monaspace Radon, Monaspace Krypton
      monaspace
    ];

    # user defined fonts
    # the reason there's Noto Color Emoji everywhere is to override DejaVu's
    # B&W emojis that would sometimes show instead of some Color emojis
    fontconfig = {
      useEmbeddedBitmaps = true;
      defaultFonts = {
        serif = [
          "Noto serif"
          "Noto Serif CJK SC"
          "Noto Color Emoji"
        ];
        sansSerif = [
          "Noto Sans"
          "Noto Sans CJK SC"
          "Noto Color Emoji"
        ];
        monospace = [
          "Monaspace Argon"
          "Noto Color Emoji"
          "Noto Sans Mono CJK SC"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
      hinting.style = "full";
    };
  };
}

{
  pkgs,
  ...
}:
let
  # TODO: 待 oculante 上游 1.0 版本正式发版并原生支持 file:// URI 及规范化 desktop 传参后，移除此 wrapper。
  # 当前版本（0.9.x）无法直接处理 file:// URI，且桌面文件中 Exec 默认使用 %U，导致文件管理器打开时传入 URI 报错。
  oculante-wrapper = pkgs.writeShellScript "oculante" ''
    exec ${pkgs.python3Minimal}/bin/python3 -c '
    import os, sys, urllib.parse
    args = [
        urllib.parse.unquote(urllib.parse.urlparse(arg).path) if arg.startswith("file://") else arg
        for arg in sys.argv[1:]
    ]
    os.execv("${pkgs.oculante}/bin/oculante", ["oculante", *args])
    ' "$@"
  '';

  oculante-fixed = pkgs.symlinkJoin {
    name = "oculante";
    paths = [ pkgs.oculante ];
    postBuild = ''
      rm $out/bin/oculante
      ln -s ${oculante-wrapper} $out/bin/oculante

      if [ -f "$out/share/applications/oculante.desktop" ]; then
        rm "$out/share/applications/oculante.desktop"
        sed 's/Exec=oculante %[uU]/Exec=oculante %F/g' \
          "${pkgs.oculante}/share/applications/oculante.desktop" > "$out/share/applications/oculante.desktop"
      fi
    '';
    meta = pkgs.oculante.meta or { };
  };
in
{
  home.packages = [ oculante-fixed ];
}

{ pkgs, lib, ... }:
{
  programs.zed-editor = {
    enable = true;
    extensions = [
      "nix"
    ];

    ## everything inside of these brackets are Zed options.
    userSettings = {

      agent = {
        version = "2";
        enabled = true;
        button = true;
        dock = "right";
        default_width = 640;
        default_height = 320;
        default_view = "thread";
        default_model = {
          provider = "zed.dev";
          model = "claude-sonnet-4";
        };
        single_file_review = true;
      };

      node = {
        path = lib.getExe pkgs.nodejs;
        npm_path = lib.getExe' pkgs.nodejs "npm";
      };

      hour_format = "hour24";
      auto_update = false;

      terminal = {
        alternate_scroll = "off";
        blinking = "off";
        copy_on_select = false;
        dock = "bottom";
        detect_venv = {
          on = {
            directories = [
              ".env"
              "env"
              ".venv"
              "venv"
            ];
            activate_script = "default";
          };
        };
        env = {
          TERM = "alacritty";
        };
        font_family = "Monaspace Krypton";
        font_features = {
          calt = true;
          liga = true;
          ss01 = true;
          ss02 = true;
          ss03 = true;
          ss04 = true;
          ss05 = true;
          ss06 = true;
          ss07 = true;
          ss08 = true;
          ss09 = true;
          ss10 = true;
          cv60 = true;
          cv62 = true;
        };
        font_size = 15;
        font_weight = 400;
        line_height = "comfortable";
        option_as_meta = false;
        button = true;
        shell = "system";
        toolbar = {
          title = true;
        };
        working_directory = "current_project_directory";
      };

      # tell zed to use direnv and direnv can use devenv.
      load_direnv = "direct";

      base_keymap = "VSCode";
      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };
      show_whitespaces = "all";
      ui_font_family = "Zed Plex Sans";
      ui_font_features = {
        calt = false;
      };
      ui_font_fallbacks = [ "Noto Sans CJK SC" ];
      ui_font_size = 16;
      ui_font_weight = 400;
      buffer_font_family = "Monaspace Argon";
      buffer_font_features = {
        calt = true;
        liga = true;
        ss01 = true;
        ss02 = true;
        ss03 = true;
        ss04 = true;
        ss05 = true;
        ss06 = true;
        ss07 = true;
        ss08 = true;
        ss09 = true;
        ss10 = true;
        cv60 = true;
        cv62 = true;
      };
      buffer_font_fallbacks = [ "Noto Sans CJK SC" ];
      buffer_font_size = 16;
      buffer_font_weight = 400;
    };
  };
}

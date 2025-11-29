{ pkgs, lib, ... }:
{
  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;
    extensions = [
      "nix"
    ];

    ## everything inside of these brackets are Zed options.
    userSettings = {

      agent = {
        enabled = true;
        preferred_completion_mode = "normal";
        button = true;
        dock = "right";
        default_width = 600;
        default_height = 300;
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

      # 各种字体设置
      # 编辑器字体
      buffer_font_family = "Monaspace Argon";
      buffer_font_fallbacks = [ "Noto Sans Mono CJK SC" ];
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
      buffer_font_size = 16;
      buffer_font_weight = 400;
      buffer_line_height = "comfortable";
      # UI 字体
      ui_font_family = ".ZedSans";
      ui_font_fallbacks = [ "Noto Sans CJK SC" ];
      ui_font_size = 16;
      ui_font_weight = 400;
      # AI 面板字体
      agent_ui_font_size = 16;
      agent_buffer_font_size = 14;

      helix_mode = true;
    };
  };
}

{ pkgs, lib, ... }:

{
  programs.zed-editor = {
    enable = true;
    extensions = [
      "nix"
      "toml"
    ];

    ## everything inside of these brackets are Zed options.
    userSettings = {

      assistant = {
        enabled = true;
        version = "2";
        default_open_ai_model = null;
        ### PROVIDER OPTIONS
        ### zed.dev models { claude-3-5-sonnet-latest } requires github connected
        ### anthropic models { claude-3-5-sonnet-latest claude-3-haiku-latest claude-3-opus-latest  } requires API_KEY
        ### copilot_chat models { gpt-4o gpt-4 gpt-3.5-turbo o1-preview } requires github connected
        default_model = {
          provider = "zed.dev";
          model = "claude-3-7-sonnet-latest";
        };

        inline_alternatives = [
          {
            provider = "zed.dev";
            model = "claude-3-7-sonnet-latest";
          }
        ];
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
        #{
        #                    program = "zsh";
        #};
        toolbar = {
          title = true;
        };
        working_directory = "current_project_directory";
      };

      lsp = {
        nix = {
          binary = {
            # path = lib.getExe pkgs.nixd;
            path_lookup = true;
          };
        };
      };

      languages = {
        "HEEX" = {
          language_servers = [
            "!lexical"
            "elixir-ls"
            "!next-ls"
          ];
          format_on_save = {
            external = {
              command = "mix";
              arguments = [
                "format"
                "--stdin-filename"
                "{buffer_path}"
                "-"
              ];
            };
          };
        };
      };

      ## tell zed to use direnv and direnv can use a flake.nix enviroment.
      load_direnv = "shell_hook";
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

{ ... }:
{
  programs.git = {
    enable = true;
    userName = "Curious";
    userEmail = "Curious@curious.host";
  };
  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = "Curious";
        email = "Curious@curious.host";
      };
      colors = {
        # Highlight hunks with background
        "diff removed token" = {
          bg = "#221111";
          underline = false;
        };
        "diff added token" = {
          bg = "#002200";
          underline = false;
        };
        # Alternatively, swap colors
        "diff token" = {
          reverse = true;
          underline = false;
        };
      };
    };
  };
}

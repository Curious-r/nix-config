{
  ...
}:
{
  preservation = {
    preserveAt."/persistent" = {
      directories = [
        "/var/lib/ncps"
      ];
      users = {
        curious = {
          directories = [
            "curious-services"
          ];
        };
      };
    };
  };
}

{ ... }:
{
  environment.persistence."/persistent" = {
    directories = [
      "/etc/daed"
    ];
  };
}

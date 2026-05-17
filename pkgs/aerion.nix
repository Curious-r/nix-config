{
  lib,
  stdenv,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  pkg-config,
  copyDesktopItems,
  wrapGAppsHook3,
  gtk3,
  webkitgtk_4_1,
  glib,
}:

let
  version = "0.2.3";
  commitRev = "95a57a27bf58be762e82ca25f66048d1d4504034";

  archMap = {
    "x86_64-linux" = "x86_64";
    "aarch64-linux" = "aarch64";
  };
  sysArch =
    archMap.${stdenv.hostPlatform.system}
      or (throw "Unsupported architecture: ${stdenv.hostPlatform.system}");

  shimHashes = {
    "x86_64" = "sha256-Wn0hj/L8C69KNlCFHxmVEgTpIuBlmsNewhTXayMIV2s=";
    "aarch64" = "sha256-4ZxJ1qTJYd2kC5zsHvOzAiST0SgWuezNM+iPrQT0eMY=";
  };

  credsShim = fetchurl {
    url = "https://github.com/hkdb/aerion/releases/download/v${version}/flathub-build-env-v${version}-linux-${sysArch}";
    hash = shimHashes.${sysArch};
  };

  src = fetchFromGitHub {
    owner = "hkdb";
    repo = "aerion";
    rev = commitRev;
    hash = "sha256-Bf3ezUC5Jbqqw3Z0fbWDKBj8hdpRPxuMhVtwF2sD4eQ=";
  };

  frontend = buildNpmPackage {
    pname = "aerion-frontend";
    inherit version src;

    sourceRoot = "${src.name}/frontend";

    npmDepsHash = "sha256-l42ufs3uNM7jgh1VGaj/Pw10d1Tlvnua+gvSxfyWw7Y=";

    buildPhase = ''
      npm run build
    '';

    installPhase = ''
      mkdir -p $out
      cp -r dist/* $out/
    '';
  };

in
buildGoModule {
  pname = "aerion";
  inherit version src;

  vendorHash = "sha256-yItu45n6UGbRWR1lMeknnY5SUV65AixFV8waeCLksIs=";

  nativeBuildInputs = [
    pkg-config
    copyDesktopItems
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    webkitgtk_4_1
    glib
  ];

  desktopItems = [
    "build/linux/aerion.desktop"
  ];

  tags = [
    "desktop"
    "production"
    "webkit2_41"
  ];

  preBuild = ''
    mkdir -p frontend/dist
    cp -r ${frontend}/* frontend/dist/
  '';

  postInstall = ''
    mkdir -p $out/share/applications $out/share/pixmaps
    if [ -f build/linux/aerion.png ]; then
      install -Dm644 build/linux/aerion.png $out/share/pixmaps/io.github.hkdb.Aerion.png
    fi

    cp ${credsShim} $out/bin/aerion-creds
    chmod +x $out/bin/aerion-creds
  '';

  meta = with lib; {
    description = "A standalone lightweight e-mail client inspired by Geary";
    homepage = "https://github.com/hkdb/aerion";
    license = licenses.mit;
    mainProgram = "aerion";
    maintainers = with maintainers; [ curious ];
  };
}

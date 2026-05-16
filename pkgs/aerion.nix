{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
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

  src = fetchFromGitHub {
    owner = "hkdb";
    repo = "aerion";
    rev = commitRev;
    hash = "sha256-QOYqPnmOfi60AMufuVlASP4iV4YV2KyCTXH57OEC+Kg=";
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

    if [ -f build/linux/aerion.desktop ]; then
      install -Dm644 build/linux/aerion.desktop -t $out/share/applications/
    fi

    if [ -f build/linux/aerion.png ]; then
      install -Dm644 build/linux/aerion.png $out/share/pixmaps/aerion.png
    fi
  '';

  meta = with lib; {
    description = "A standalone lightweight e-mail client inspired by Geary";
    homepage = "https://github.com/hkdb/aerion";
    license = licenses.mit;
    mainProgram = "aerion";
  };
}

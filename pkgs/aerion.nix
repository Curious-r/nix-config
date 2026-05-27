{
  lib,
  stdenv,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook3,
  gtk3,
  webkitgtk_4_1,
  glib,

  aerion-creds,
  withOAuth ? false,
}:

let
  version = "0.2.5";

  src = fetchFromGitHub {
    owner = "hkdb";
    repo = "aerion";
    rev = "v${version}";
    hash = "sha256-lAOEZICHcQu9yQmdvli1e2mt5RhvSBuWs8YazI8IN5E=";
  };

  frontend = buildNpmPackage {
    pname = "aerion-frontend";
    inherit version src;

    sourceRoot = "${src.name}/frontend";

    npmDepsHash = "sha256-bBo+oVhSfgomh3wvS5hzK05SHX1hXZzH3DJzQhGTX9s=";

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

  __structuredAttrs = true;

  vendorHash = "sha256-yItu45n6UGbRWR1lMeknnY5SUV65AixFV8waeCLksIs=";

  nativeBuildInputs = [
    pkg-config
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    wrapGAppsHook3
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    gtk3
    webkitgtk_4_1
    glib
  ];

  tags = [
    "production"
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    "desktop"
    "webkit2_41"
  ];

  preBuild = ''
    mkdir -p frontend/dist
    cp -r ${frontend}/* frontend/dist/
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux (
    ''
      install -Dm644 build/linux/aerion.png $out/share/pixmaps/io.github.hkdb.Aerion.png
      install -Dm644 build/linux/aerion.desktop $out/share/applications/io.github.hkdb.Aerion.desktop
    ''
    + lib.optionalString withOAuth ''
      rm -f $out/bin/aerion-creds
      ln -s ${aerion-creds}/bin/aerion-creds $out/bin/aerion-creds
    ''
  );

  meta = with lib; {
    description = "An Open Source Lightweight E-Mail Client";
    homepage = "https://github.com/hkdb/aerion";
    license = licenses.asl20;
    mainProgram = "aerion";
    maintainers = with maintainers; [ curious ];
  };
}

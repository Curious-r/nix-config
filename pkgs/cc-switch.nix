{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,

  cargo-tauri,
  jq,
  makeBinaryWrapper,
  moreutils,
  nodejs,
  pkg-config,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  wrapGAppsHook3,

  glib-networking,
  libayatana-appindicator,
  libsoup_3,
  openssl,
  webkitgtk_4_1,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "cc-switch";
  version = "3.20.0";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "farion1231";
    repo = "cc-switch";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mZfXwOAUEtaKklQd5Ske4XCBvk+w9hQQITWNa/wSX0Q=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      ;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-uqY6/WSVsuvfcJsbWMYenaxLp9gDguiMAyb/mepv028=";
  };

  postPatch = ''
    jq '
      del(.build.beforeBuildCommand) |
      .bundle.createUpdaterArtifacts = false |
      .plugins.updater.endpoints = []
    ' src-tauri/tauri.conf.json | sponge src-tauri/tauri.conf.json
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    jq '.bundle.macOS.signingIdentity = null' src-tauri/tauri.conf.json | sponge src-tauri/tauri.conf.json
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    # libappindicator-sys dlopens libayatana-appindicator3.so.1 at runtime; autoPatchelf can't catch it.
    substituteInPlace $cargoDepsCopy/*/libappindicator-sys-*/src/lib.rs \
      --replace-fail "libayatana-appindicator3.so.1" "${libayatana-appindicator}/lib/libayatana-appindicator3.so.1"
  '';

  cargoRoot = "src-tauri";
  buildAndTestSubdir = finalAttrs.cargoRoot;

  cargoHash = "sha256-Tv8oab2y1AnifK8EjGFXtMBiuELcDaKp7NKrGGWhC/o=";

  nativeBuildInputs = [
    cargo-tauri.hook
    jq
    moreutils
    nodejs
    pnpmConfigHook
    pnpm_10
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    pkg-config
    wrapGAppsHook3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    makeBinaryWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    glib-networking
    libayatana-appindicator
    libsoup_3
    openssl
    webkitgtk_4_1
  ];

  # tauri-build embeds frontendDist (../dist) at compile time; populate it
  # before cargo tauri build runs (beforeBuildCommand is stripped in postPatch).
  preBuild = ''
    pnpm run build:renderer
  '';

  # Upstream Cargo.lock resolves newer tauri crates than the pinned npm packages
  # (e.g. tauri 2.10 vs @tauri-apps/api 2.8). cargo tauri build errors on that;
  # the previous cargo-only packaging already shipped this combination.
  tauriBuildFlags = [ "--ignore-version-mismatches" ];

  # Skip upstream tests locally: some assume FHS paths such as /bin/echo and
  # /bin/bash, and running the large Rust test suite significantly slows builds.
  doCheck = false;

  postInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir -p "$out/bin"
    makeWrapper "$out/Applications/CC Switch.app/Contents/MacOS/cc-switch" "$out/bin/cc-switch"
  '';

  meta = {
    description = "All-in-one assistant for Claude Code, Codex, OpenCode, Gemini CLI and other AI coding agents";
    homepage = "https://ccswitch.io";
    downloadPage = "https://github.com/farion1231/cc-switch";
    changelog = "https://github.com/farion1231/cc-switch/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    mainProgram = "cc-switch";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})

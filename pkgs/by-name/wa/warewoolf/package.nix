{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  electron,
  nodejs,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  removeReferencesTo,
}:

buildNpmPackage (finalAttrs: {
  pname = "warewoolf";
  version = "2.2.1";

  src = fetchFromGitHub {
    owner = "brsloan";
    repo = "warewoolf";
    tag = "v${finalAttrs.version}";
    hash = "sha256-JtuqG6zwN+k7MoFP890vmhqL3w8IbH4QDaOPVTtrDqM=";
  };

  npmDepsHash = "sha256-FXE5IcwOpSkukiTjZWfduP5F+5fs4pjEiQ7vwMIbcMU=";

  dontNpmBuild = true;
  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
    removeReferencesTo
  ];

  installPhase = ''
    runHook preInstall

    # Drop devDependencies (electron, electron-forge) so they don't end up in the closure.
    npm prune --omit=dev

    phome="$out/share/warewoolf"
    mkdir -p "$phome"
    cp -r src "$phome/src"
    cp package.json "$phome/package.json"
    cp -r node_modules "$phome/node_modules"

    # Drop nodejs references from dependency CLI shebangs; warewoolf never invokes them.
    find "$phome/node_modules" -type f -executable -exec remove-references-to -t ${nodejs} '{}' +

    install -Dm644 src/assets/icon.png "$out/share/icons/hicolor/256x256/apps/warewoolf.png"

    makeWrapper ${lib.getExe electron} "$out/bin/warewoolf" \
      --add-flags "$phome" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --set ELECTRON_FORCE_IS_PACKAGED 1 \
      --inherit-argv0

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "warewoolf";
      desktopName = "WareWoolf";
      comment = "Simple novel writing system designed to be usable without a mouse";
      exec = "warewoolf %F";
      icon = "warewoolf";
      categories = [
        "Office"
        "WordProcessor"
      ];
      mimeTypes = [ "text/plain" ];
    })
  ];

  meta = {
    description = "Simple novel writing system designed to be usable without a mouse";
    homepage = "https://github.com/brsloan/warewoolf";
    changelog = "https://github.com/brsloan/warewoolf/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = electron.meta.platforms;
    mainProgram = "warewoolf";
  };
})

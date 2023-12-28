{ pkgs
, lib
, makeWrapper
, nodejs ? pkgs.nodejs_18
}:

let
  fetchElmDeps = pkgs.callPackage ./fetchElmDeps.nix { };

  # Haskell packages that require ghc 9.2
  hs96Pkgs = self: pkgs.haskell.packages.ghc92.override {
    overrides = self: super: with pkgs.haskell.lib.compose; with lib;
    let elmPkgs = rec {
      elm = overrideCabal (drv: {
        # sadly with parallelism most of the time breaks compilation
        enableParallelBuilding = false;
        preConfigure = fetchElmDeps {
          elmPackages = (import ./packages/elm-srcs.nix);
          elmVersion = drv.version;
          registryDat = ./registry.dat;
        };
        buildTools = drv.buildTools or [] ++ [ makeWrapper ];
        postInstall = ''
          wrapProgram $out/bin/elm \
            --prefix PATH ':' ${lib.makeBinPath [ nodejs ]}
        '';

        description = "A delightful language for reliable webapps";
        homepage = "https://elm-lang.org/";
        license = licenses.bsd3;
        maintainers = with maintainers; [ domenkozar turbomack ];
      }) (self.callPackage ./packages/elm.nix { });

      inherit fetchElmDeps;
      elmVersion = elmPkgs.elm.version;
    };
    in {
      inherit elmPkgs;
    };
  };

  hs810Pkgs = self: pkgs.haskell.packages.ghc810.override {
    overrides = self: super: with pkgs.haskell.lib.compose; with lib;
    let elmPkgs = {
      elmi-to-json = justStaticExecutables (overrideCabal (drv: {
        prePatch = ''
          substituteInPlace package.yaml --replace "- -Werror" ""
          hpack
        '';
        jailbreak = true;

        description = "Tool that reads .elmi files (Elm interface file) generated by the elm compiler";
        homepage = "https://github.com/stoeffel/elmi-to-json";
        license = licenses.bsd3;
        maintainers = [ maintainers.turbomack ];
      }) (self.callPackage ./packages/elmi-to-json.nix {}));

      elm-instrument = justStaticExecutables (overrideCabal (drv: {
        prePatch = ''
          sed "s/desc <-.*/let desc = \"${drv.version}\"/g" Setup.hs --in-place
        '';
        # Tests are failing because of missing instances for Eq and Show type classes
        doCheck = false;
        jailbreak = true;

        description = "Instrument Elm code as a preprocessing step for elm-coverage";
        homepage = "https://github.com/zwilias/elm-instrument";
        license = licenses.bsd3;
        maintainers = [ maintainers.turbomack ];
      }) (self.callPackage ./packages/elm-instrument.nix {}));
    };
    in elmPkgs // {
      inherit elmPkgs;

      # We need attoparsec < 0.14 to build elm for now
      attoparsec = self.attoparsec_0_13_2_5;

      # aeson 2.0.3.0 does not build with attoparsec_0_13_2_5
      aeson = doJailbreak self.aeson_1_5_6_0;

      # elm-instrument needs this
      indents = self.callPackage ./packages/indents.nix {};

      # elm-instrument's tests depend on an old version of elm-format, but we set doCheck to false for other reasons above
      elm-format = null;
    };
  };

  # Haskell packages that require ghc 9.2
  hs92Pkgs = self: pkgs.haskell.packages.ghc92.override {
    overrides = self: super: with pkgs.haskell.lib.compose; with lib;
    let elmPkgs = {
      /*
      The elm-format expression is updated via a script in the https://github.com/avh4/elm-format repo:
      `package/nix/build.sh`
      */
      elm-format = justStaticExecutables (overrideCabal (drv: {
        jailbreak = true;

        description = "Formats Elm source code according to a standard set of rules based on the official Elm Style Guide";
        homepage = "https://github.com/avh4/elm-format";
        license = licenses.bsd3;
        maintainers = with maintainers; [ avh4 turbomack ];
      }) (self.callPackage ./packages/elm-format.nix {}));
    };
    in elmPkgs // {
      inherit elmPkgs;

      # Needed for elm-format
      avh4-lib = doJailbreak (self.callPackage ./packages/avh4-lib.nix {});
      elm-format-lib = doJailbreak (self.callPackage ./packages/elm-format-lib.nix {});
      elm-format-test-lib = self.callPackage ./packages/elm-format-test-lib.nix {};
      elm-format-markdown = self.callPackage ./packages/elm-format-markdown.nix {};

      # elm-format requires text >= 2.0
      text = self.text_2_0_2;
      # unorderd-container's tests indirectly depend on text < 2.0
      unordered-containers = overrideCabal (drv: { doCheck = false; }) super.unordered-containers;
      # relude-1.1.0.0's tests depend on hedgehog < 1.2, which indirectly depends on text < 2.0
      relude = overrideCabal (drv: { doCheck = false; }) super.relude;
    };
  };

  nodePkgs = pkgs.callPackage ./packages/node-composition.nix {
    inherit pkgs nodejs;
    inherit (pkgs.stdenv.hostPlatform) system;
  };

in lib.makeScope pkgs.newScope (self: with self; {
  inherit fetchElmDeps nodejs;

  /* Node/NPM based dependencies can be upgraded using script `packages/generate-node-packages.sh`.

      * Packages which rely on `bin-wrap` will fail by default
        and can be patched using `patchBinwrap` function defined in `packages/lib.nix`.

      * Packages which depend on npm installation of elm can be patched using
        `patchNpmElm` function also defined in `packages/lib.nix`.
  */
  elmLib = let
    hsElmPkgs = hs96Pkgs self;
  in import ./packages/lib.nix {
    inherit lib;
    inherit (pkgs) writeScriptBin stdenv;
    inherit (hsElmPkgs.elmPkgs) elm;
  };

  elm-json = callPackage ./packages/elm-json.nix { };

  elm-test-rs = callPackage ./packages/elm-test-rs.nix { };

  elm-test = callPackage ./packages/elm-test.nix { };
} // (hs96Pkgs self).elmPkgs // (hs810Pkgs self).elmPkgs // (hs92Pkgs self).elmPkgs // (with elmLib; with (hs810Pkgs self).elmPkgs; {
  elm-verify-examples = let
    patched = patchBinwrap [elmi-to-json] nodePkgs.elm-verify-examples // {
    meta = with lib; nodePkgs.elm-verify-examples.meta // {
      description = "Verify examples in your docs";
      homepage = "https://github.com/stoeffel/elm-verify-examples";
      license = licenses.bsd3;
      maintainers = [ maintainers.turbomack ];
    };
  };
  in patched.override (old: {
    preRebuild = (old.preRebuild or "") + ''
      # This should not be needed (thanks to binwrap* being nooped) but for some reason it still needs to be done
      # in case of just this package
      # TODO: investigate, same as for elm-coverage below
      sed 's/\"install\".*/\"install\":\"echo no-op\",/g' --in-place node_modules/elmi-to-json/package.json
    '';
  });

  elm-coverage = let
      patched = patchNpmElm (patchBinwrap [elmi-to-json] nodePkgs.elm-coverage);
    in patched.override (old: {
      # Symlink Elm instrument binary
      preRebuild = (old.preRebuild or "") + ''
        # Noop custom installation script
        sed 's/\"install\".*/\"install\":\"echo no-op\"/g' --in-place package.json

        # This should not be needed (thanks to binwrap* being nooped) but for some reason it still needs to be done
        # in case of just this package
        # TODO: investigate
        sed 's/\"install\".*/\"install\":\"echo no-op\",/g' --in-place node_modules/elmi-to-json/package.json
      '';
      postInstall = (old.postInstall or "") + ''
        mkdir -p unpacked_bin
        ln -sf ${elm-instrument}/bin/elm-instrument unpacked_bin/elm-instrument
      '';
      meta = with lib; nodePkgs.elm-coverage.meta // {
        description = "Work in progress - Code coverage tooling for Elm";
        homepage = "https://github.com/zwilias/elm-coverage";
        license = licenses.bsd3;
        maintainers = [ maintainers.turbomack ];
      };
    });

    create-elm-app = patchNpmElm
    nodePkgs.create-elm-app // {
      meta = with lib; nodePkgs.create-elm-app.meta // {
        description = "Create Elm apps with no build configuration";
        homepage = "https://github.com/halfzebra/create-elm-app";
        license = licenses.mit;
        maintainers = [ maintainers.turbomack ];
      };
    };

    elm-graphql =
      nodePkgs."@dillonkearns/elm-graphql" // {
        meta = with lib; nodePkgs."@dillonkearns/elm-graphql".meta // {
          description = " Autogenerate type-safe GraphQL queries in Elm.";
          license = licenses.bsd3;
          maintainers = [ maintainers.pedrohlc ];
        };
      };

    elm-review =
      nodePkgs.elm-review // {
        meta = with lib; nodePkgs.elm-review.meta // {
          description = "Analyzes Elm projects, to help find mistakes before your users find them";
          homepage = "https://package.elm-lang.org/packages/jfmengels/elm-review/${nodePkgs.elm-review.version}";
          license = licenses.bsd3;
          maintainers = [ maintainers.turbomack ];
        };
      };

      elm-language-server = nodePkgs."@elm-tooling/elm-language-server" // {
        meta = with lib; nodePkgs."@elm-tooling/elm-language-server".meta // {
          description = "Language server implementation for Elm";
          homepage = "https://github.com/elm-tooling/elm-language-server";
          license = licenses.mit;
          maintainers = [ maintainers.turbomack ];
        };
      };

      elm-spa = nodePkgs."elm-spa".overrideAttrs  (
        old: {
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ makeWrapper old.nodejs.pkgs.node-gyp-build ];

          meta = with lib; nodePkgs."elm-spa".meta // {
            description = "A tool for building single page apps in Elm";
            homepage = "https://www.elm-spa.dev/";
            license = licenses.bsd3;
            maintainers = [ maintainers.ilyakooo0 ];
          };
        }
      );

      elm-optimize-level-2 = nodePkgs."elm-optimize-level-2" // {
        meta = with lib; nodePkgs."elm-optimize-level-2".meta // {
          description = "A second level of optimization for the Javascript that the Elm Compiler produces";
          homepage = "https://github.com/mdgriffith/elm-optimize-level-2";
          license = licenses.bsd3;
          maintainers = [ maintainers.turbomack ];
        };
      };

      elm-pages = nodePkgs."elm-pages".overrideAttrs (
        old: {
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ makeWrapper old.nodejs.pkgs.node-gyp-build ];

          # can't use `patches = [ <patch_file> ]` with a nodePkgs derivation;
          # need to patch in one of the build phases instead.
          # see upstream issue https://github.com/dillonkearns/elm-pages/issues/305 for dealing with the read-only problem
          preFixup = ''
            patch $out/lib/node_modules/elm-pages/generator/src/codegen.js ${./packages/elm-pages-fix-read-only.patch}
            patch $out/lib/node_modules/elm-pages/generator/src/init.js ${./packages/elm-pages-fix-init-read-only.patch}
          '';

          postFixup = ''
            wrapProgram $out/bin/elm-pages --prefix PATH : ${
              with pkgs.elmPackages; lib.makeBinPath [ elm elm-review elm-optimize-level-2 ]
            }
          '';

          meta = with lib; nodePkgs."elm-pages".meta // {
            description = "A statically typed site generator for Elm.";
            homepage = "https://github.com/dillonkearns/elm-pages";
            license = licenses.bsd3;
            maintainers = [ maintainers.turbomack maintainers.jali-clarke ];
          };
        }
      );

      elm-land = nodePkgs."elm-land".overrideAttrs (
        old: {
          meta = with lib; nodePkgs."elm-land".meta // {
            description = "A production-ready framework for building Elm applications.";
            homepage = "https://elm.land/";
            license = licenses.bsd3;
            maintainers = [ maintainers.zupo ];
          };
        }
      );

      lamdera = callPackage ./packages/lamdera.nix {};

      elm-doc-preview = nodePkgs."elm-doc-preview".overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ old.nodejs.pkgs.node-gyp-build ];
      });

      inherit (nodePkgs) elm-live elm-upgrade elm-xref elm-analyse elm-git-install;
    })
  )

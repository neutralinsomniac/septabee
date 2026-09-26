{
  description = "FHS environment for the Septabee DAW (upstream Linux release)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      septabeeVersion = "B";
      septabeeBuild = "T15";

      septabee-unwrapped = pkgs.stdenvNoCC.mkDerivation {
        pname = "septabee-unwrapped";
        version = "${septabeeVersion}-${septabeeBuild}";
        src = pkgs.fetchurl {
          url = "https://septabee.nekoweb.org/important_stuff/SEPTABEE_DOWNLOADS/version_${septabeeVersion}/septabee_linux_${septabeeVersion}_${septabeeBuild}.7z";
          hash = "sha256-+LE0Ukl2Mz2KIbe/ykM8GXTSlDFpyrB35hN3lIKcbnM=";
        };
        nativeBuildInputs = [
          pkgs._7zz
          pkgs.python3
        ];
        unpackPhase = "7zz x $src";
        sourceRoot = "linux";
        dontConfigure = true;
        dontBuild = true;
        # Don't let nix try to patch/strip the ELF files; the FHS env supplies a
        # normal /lib64/ld-linux-x86-64.so.2 so the stock interpreter path works.
        dontPatchELF = true;
        dontStrip = true;
        dontPatchShebangs = true;
        installPhase = ''
          mkdir -p $out/share/septabee/jit-runtime
          cp -a . $out/share/septabee/
          chmod 755 $out/share/septabee/septabee \
                    $out/share/septabee/septabee-sounds \
                    $out/share/septabee/septabee-watchdawg
        '';
      };

      runtimeDeps =
        p: with p; [
          # linked (ldd)
          stdenv.cc.cc.lib # libstdc++, libgcc_s
          zlib
          libpng
          freetype
          vulkan-loader
          pipewire
          libx11

          # dlopen'd by the GLFW/EGL/GL layer
          libglvnd # libGL, libEGL, libGLES*, libOpenGL, libGLX
          mesa # libOSMesa + software fallback
          wayland
          libdecor
          libxkbcommon
          libxcursor
          libxext
          libxinerama
          libxi
          libxrandr
          libxrender
          libxxf86vm
          libxcb

          # lets the in-app "Install" button re-download the JIT runtime if needed
          curl
          cacert

          # tinyfiledialogs backends for open/save dialogs
          zenity
          xmessage
        ];

      # Copies the store files into a writable directory on first run (or when
      # the store path changes) so the app can write caches (and, if it ever
      # wants to, a newer JIT runtime) next to the executable, then execs it.
      runScript = pkgs.writeShellScript "septabee-run" ''
        set -eu
        src=${septabee-unwrapped}/share/septabee
        dst="''${SEPTABEE_HOME:-''${XDG_DATA_HOME:-$HOME/.local/share}/septabee}"

        if [ ! -f "$dst/.store-path" ] || [ "$(cat "$dst/.store-path")" != "$src" ]; then
          mkdir -p "$dst"
          cp -rf "$src"/. "$dst/"
          chmod -R u+w "$dst"
          printf '%s\n' "$src" > "$dst/.store-path"
        fi

        exec "$dst/septabee" "$@"
      '';

      septabee = pkgs.buildFHSEnv {
        name = "septabee";
        targetPkgs = runtimeDeps;
        inherit runScript;
        extraInstallCommands = ''
          mkdir -p $out/share/applications
          cat > $out/share/applications/septabee.desktop <<'DESKTOP'
          [Desktop Entry]
          Type=Application
          Name=Septabee
          Comment=Septabee DAW
          Exec=septabee %f
          Terminal=false
          Categories=AudioVideo;Audio;
          DESKTOP
        '';
        meta = {
          description = "Septabee DAW wrapped in an FHS environment";
          homepage = "https://septabee.nekoweb.org/";
          platforms = [ system ];
          mainProgram = "septabee";
        };
      };

      # Same environment, but drops you in a shell so you can run ./septabee
      # straight from this directory (writable, no copy step).
      fhsShell = pkgs.buildFHSEnv {
        name = "septabee-fhs";
        targetPkgs = runtimeDeps;
        runScript = "bash";
      };
    in
    {
      packages.${system} = {
        inherit septabee septabee-unwrapped;
        fhs = fhsShell;
        default = septabee;
      };

      apps.${system}.default = {
        type = "app";
        program = "${septabee}/bin/septabee";
      };

      devShells.${system}.default = fhsShell.env;
    };
}

{
  lib,
  stdenvNoCC,
  fetchurl,
  curl,
  unzip,
  makeDesktopItem,
  symlinkJoin,
  writeShellScriptBin,
  gamemode,
  winetricks,
  umu-launcher-git,
  proton-ge-bin,
  pname ? "pokeone",
  location ? "$HOME/.pokeone",
  useGameMode ? true,
  # The launcher checks for updates and then starts the game. Set this to
  # false to start files/PokeOne.exe directly (no .NET or auto-updates).
  useLauncher ? true,
  # Proton renders Direct3D through DXVK (Vulkan) by default. On some
  # GPU/driver combinations that crashes or renders badly; set this to false
  # to use Wine's OpenGL-based D3D11 implementation instead.
  useDxvk ? true,
  protonPath ? "${proton-ge-bin.steamcompattool}",
  protonVerbs ? [ "waitforexitandrun" ],
  winVersion ? "win10",
  tricks ? lib.optional useLauncher "dotnet48",
  preCommands ? "",
  postCommands ? "",
}:
let
  info = builtins.fromJSON (builtins.readFile ./info.json);

  # The PokeOne installer is hosted on MediaFire, whose download links are
  # short-lived. Instead, fetch the game from the official update server the
  # launcher itself uses. The result has the same layout as C:\PokeOne.
  src = stdenvNoCC.mkDerivation {
    pname = "${pname}-game-files";
    version = "unstable-${info.updated or "unknown"}";

    nativeBuildInputs = [
      curl
      unzip
    ];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = info.hash;

    buildCommand = ''
      bash ${./fetch-game.sh} "$out"
    '';
  };

  icon = fetchurl {
    url = "https://pokeonecommunity.com/wp-content/uploads/2025/01/p1ball.svg";
    hash = "sha256-stpVroE4S63lHNINrPShTSodX7UmSOEOUnAV3/tTwe4=";
  };

  icons = stdenvNoCC.mkDerivation {
    name = "${pname}-icons";
    dontUnpack = true;
    installPhase = ''
      install -Dm644 ${icon} $out/share/icons/hicolor/scalable/apps/${pname}.svg
    '';
  };

  tricksFmt = builtins.concatStringsSep " " tricks;

  hasDotnet = lib.any (lib.hasPrefix "dotnet") tricks;

  gameMode = lib.optionalString useGameMode "${gamemode}/bin/gamemoderun";

  target = if useLauncher then "\"$LAUNCHER\"" else "\"$GAME\"";

  # Nix dedents interpolated snippets to column 0; re-indent them so the
  # generated shell script stays readable.
  indent =
    s:
    lib.concatMapStrings (line: if line == "" then "\n" else "  ${line}\n") (
      lib.splitString "\n" (lib.trim s)
    );

  # Proton pre-creates these keys, which makes the .NET 4.x installers abort
  # with "Same or higher version of .NET Framework 4 has already been
  # installed on this computer" (winetricks#2367).
  dotnetPrelude = lib.optionalString hasDotnet ''
    "$runner" "$REG" delete 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4' /f || true
    "$runner" "$REG" delete 'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4' /f || true
  '';

  # The dotnet verbs set winver to winxp and restore it when they finish, so an
  # interrupted earlier run can leave winxp behind.
  dotnetPostlude = lib.optionalString hasDotnet ''
    "$@" -q ${winVersion}

    for key in \
      'HKLM\Software\Microsoft\.NETFramework\v4.0.30319' \
      'HKLM\Software\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; do
      "$runner" "$REG" add "$key" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f
      "$runner" "$REG" add "$key" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f
    done
  '';

  script = writeShellScriptBin pname ''
    export WINEPREFIX="${location}"
    # disables vsync for OpenGL
    export vblank_mode=0

    export GAMEID="pokeone"
    export STORE="none"
    export PROTON_VERBS="${builtins.concatStringsSep "," protonVerbs}"
    export PROTONPATH="${protonPath}"
    ${lib.optionalString (!useDxvk) "export PROTON_USE_WINED3D=1"}

    PATH=${
      lib.makeBinPath [
        umu-launcher-git
        winetricks
      ]
    }:$PATH

    GAME_DIR="$WINEPREFIX/drive_c/PokeOne"
    LAUNCHER="$GAME_DIR/Launcher.exe"
    GAME="$GAME_DIR/files/PokeOne.exe"
    # umu-run needs a Windows path; passing a bare "reg" makes it look for a
    # Unix executable of that name.
    REG='C:\windows\system32\reg.exe'

    # $1 runs umu, the remaining arguments run winetricks.
    # Returns 0 when it installed the tricks, 1 when they were already there.
    install_tricks() {
      local runner="$1"
      shift
      local marker="$WINEPREFIX/.tricks-installed"

      if [ -f "$marker" ] && [ "$(<"$marker")" = "${tricksFmt}" ]; then
        return 1
      fi
    ${indent dotnetPrelude}
      "$@" -q -f ${tricksFmt}
    ${indent dotnetPostlude}
      printf '%s' "${tricksFmt}" > "$marker"
    }

    ${lib.optionalString (tricks != [ ]) ''
      mkdir -p "$WINEPREFIX"
      if install_tricks umu-run umu-run winetricks; then
        umu-run wineserver -k || true
      fi
    ''}

    # The launcher writes updates next to itself, so the game cannot run
    # straight from the read-only Nix store. Keep a writable copy instead.
    if [ ! -f "$LAUNCHER" ]; then
      mkdir -p "$GAME_DIR"
      cp -r --reflink=auto ${src}/. "$GAME_DIR/"
      chmod -R u+w "$GAME_DIR"
    fi

    ${preCommands}

    ${gameMode} umu-run ${target} "$@"

    ${postCommands}
  '';

  desktopItems = makeDesktopItem {
    name = pname;
    exec = "${script}/bin/${pname}";
    icon = pname;
    comment = "Pokémon MMO client";
    desktopName = "PokeOne";
    categories = [ "Game" ];
    keywords = [
      "pokemon"
      "mmo"
    ];
  };
in
symlinkJoin {
  name = pname;
  paths = [
    desktopItems
    script
    icons
  ];

  passthru = {
    inherit src;
    updateScript = ./update.sh;
  };

  meta = {
    description = "PokeOne Pokémon MMO client";
    homepage = "https://pokeonecommunity.com";
    license = lib.licenses.unfree;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}

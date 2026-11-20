# pokeone

[PokeOne](https://pokeonecommunity.com) is a Pokémon MMO. Only the Windows
client is packaged here: the Android version needs Waydroid and a full Android
system, while the Windows client runs well under Wine/Proton.

## How it works

The official Windows installer (`p1setup.exe`) is distributed through MediaFire,
whose direct download links expire. The game's launcher, however, keeps itself
up to date from the official update server at <http://update.poke.one>. This
package fetches the client from that server instead, so the source is stable and
always current.

On first launch the package:

1. creates a Wine prefix at `~/.pokeone` (override with `location`),
2. installs .NET Framework 4.8 with winetricks (only in launcher mode, because
   the launcher is a WPF application),
3. copies the game from the Nix store to `~/.pokeone/drive_c/PokeOne`,
4. starts `Launcher.exe` through [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher)
   with Proton GE.

The copy under `~/.pokeone` is writable on purpose: PokeOne's launcher downloads
game updates next to itself. If something breaks, delete `~/.pokeone` and run
the package again.

## Usage

```console
nix run github:fufexan/nix-gaming#pokeone
```

or add `pokeone` to `environment.systemPackages` / `home.packages`.

The first start takes a while, because the prefix has to be created and .NET has
to be installed. **Do not interrupt it.**

## Updating the packaged client

The in-game launcher updates itself, so this is mostly useful for refreshing the
default files that are copied into a new prefix:

```console
./pkgs/pokeone/update.sh
```

This re-downloads the current client from the update server and writes the new
hash to `info.json`.

## Overrides

```nix
pokeone.override {
  # Start files/PokeOne.exe directly, without the launcher or .NET.
  # The game then never phone-homes for updates, but also cannot patch itself.
  useLauncher = false;

  # Use Wine's OpenGL D3D11 instead of Proton's DXVK. Useful when the game
  # crashes right after the first loading screen on a given GPU/driver.
  useDxvk = false;

  # Disable Feral GameMode.
  useGameMode = false;

  # Use a different Proton build.
  protonPath = "${pkgs.proton-ge-bin.steamcompattool}";

  # Extra winetricks verbs.
  tricks = [ "dotnet48" "vcrun2022" ];

  # Install the prefix somewhere else.
  location = "$HOME/Games/pokeone";
}
```

Keep `WINEPREFIX` (`location`) on a real filesystem. umu-launcher runs Proton
inside a pressure-vessel container, which does not see `/tmp`, so a prefix or
game directory below `/tmp` will not work.

## Troubleshooting

- The window closes a few seconds after the Unity logo: try `useDxvk = false`.
- The launcher complains about .NET or shows an empty window: delete the
  `dotnet48` marker and restart, so the tricks are installed again:
  `rm ~/.pokeone/.tricks-installed`.
- To start over completely: `rm -rf ~/.pokeone`.
- The launcher downloads updates into `~/.pokeone/drive_c/PokeOne`, so that
  directory can grow over time; it is safe to delete (it is recreated from the
  Nix store on the next start).

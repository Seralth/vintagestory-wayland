# vintagestory-wayland

Runs the Vintage Story client natively on Wayland on Linux, and fixes the loading-screen
crash that the game hits there.

By default the game opens an X11 window, which a Wayland desktop runs through XWayland.
This small add-on starts the game on Wayland directly instead. On the laptop it was first
tested on, the game loaded noticeably faster and ran at a higher frame rate. It is also what
the Linux build of the [Native HDR](https://mods.vintagestory.at/hdr) mod needs, because
HDR output on Linux is only available to native Wayland windows.

It is not a game mod: the choice between X11 and Wayland is made before the game loads any
mods, so this has to run before the game starts. It goes into your launcher instead of the
Mods folder.

## The crash it fixes

Started on Wayland, Vintage Story 1.22 often crashes on the startup loading screen with
`KeyNotFoundException: The given key 'lightPosition' was not present in the dictionary`.
Wayland compositors send a new window its size straight away; the game handles that resize
by rebuilding its framebuffers, which (as a side effect) creates the GUI shader before it has
been compiled, and the loading screen then draws with the empty shader. The details are in
[VintageStory-Issues #9184](https://github.com/anegostudios/VintageStory-Issues/issues/9184#issuecomment-5811716499)
(the same crash is reported for Windows in
[#8807](https://github.com/anegostudios/VintageStory-Issues/issues/8807)).

This add-on skips those few loading-screen draws until the shader is ready, which is what the
game already does before the shader exists. Nothing else changes.

## Requirements

- Linux with a Wayland desktop session (KDE Plasma, GNOME, Hyprland, ...).
- Vintage Story installed normally (tarball, installer or distribution package). The
  **Flatpak build is not supported**: the add-on cannot be passed into its sandbox.

Tested with Vintage Story 1.22.7 on KDE Plasma 6.7 (Wayland), on an NVIDIA RTX 5080 laptop
and an AMD RX 7900 XTX desktop. Other Wayland desktops are expected to work but have not been
tried; reports are welcome.

On GNOME, applications draw their own window title bars. If the game's window has none, try
installing `libdecor`, which the game's windowing library uses for that.

## Install

1. Download `vintagestory-wayland-<version>.tar.gz` from
   [Releases](../../releases) and extract it.
2. In the extracted folder, run:

   ```sh
   ./install.sh
   ```

3. Start Vintage Story from your application launcher as usual.

The installer takes over your existing Vintage Story launcher entry: it keeps whatever
command started the game before, and starts it through a small wrapper
(`~/.local/bin/vintagestory-wayland`) that loads the add-on. If it cannot find your
launcher entry, pass the command that starts the game:

```sh
./install.sh '/path/to/vintagestory'
```

Everything goes into your home folder; nothing needs root.

## Check that it works

Every start adds one line to `~/.local/share/vintagestory-wayland/hook.log`:

```
[2026-09-24 03:51:05] GLFW platform Wayland, loading-screen guard on 3 methods
```

`GLFW platform Wayland` means the game is running natively on Wayland. If it says
`left to the game (...)`, the reason is in the brackets. If a game update moves what the
crash guard patches, the line says `failed (...)`; the game still starts, it just loses the
crash fix.

## Turning Wayland off

To start the game the old way for one run, set `VS_WAYLAND=0`:

```sh
VS_WAYLAND=0 ~/.local/bin/vintagestory-wayland
```

The crash guard stays active either way; it is harmless on X11. In an X11 desktop session
the add-on leaves the choice to the game on its own.

## Uninstall

```sh
./uninstall.sh
```

This puts your launcher entry back to its original command and deletes the wrapper, the
add-on and its log.

## How it works

`install.sh` points your launcher at the wrapper, which sets `DOTNET_STARTUP_HOOKS` so the
.NET runtime loads `VintageStoryWaylandHook.dll` before the game's own code runs. The hook
then:

1. asks GLFW (the library the game opens its window with) for the Wayland backend and
   initialises it, so the game's own, later initialisation keeps that choice;
2. patches `MainMenuRenderAPI.Render2DTexture`, `Draw2DShadedEdges` and `RenderRectangle`
   with [Harmony](https://github.com/pardeike/Harmony) (the copy that ships with the game)
   to skip drawing while the GUI shader has no uniform locations yet.

It loads the game's own OpenTK and Harmony; nothing from the game is included here.

## Build from source

Needs the .NET 10 SDK and an installed copy of the game:

```sh
./make-release.sh                          # game in /opt/vintagestory
VINTAGE_STORY=/path/to/game ./make-release.sh
```

This writes `dist/vintagestory-wayland-<version>.tar.gz`. To install straight from a
source checkout, build with `dotnet build src -c Release` and run `./install.sh`.

## License

MIT, see [LICENSE](LICENSE).

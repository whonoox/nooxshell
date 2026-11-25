# Nooxshell

A floating-island desktop shell for [Omarchy](https://omarchy.org), built on
[Quickshell](https://quickshell.org). Panels float over the stock Omarchy
desktop as single-vector "scoop" shapes with a compositor-level X-Ray blur.

Managed with the `nooxshell` command.

## Install

Needs Omarchy 4.0 or newer. Video wallpapers and background intros are
played by OWE, whose handover with the Omarchy shell came with 4.5: on
4.0.x the shell works with still wallpapers only, and the pickers skip
intros. The installer says which of the two you have.

```bash
git clone https://github.com/whonoox/nooxshell.git nooxshell
cd nooxshell
./install.sh --dry-run    # optional: see every change first, touch nothing
./install.sh
```

The installer asks before installing packages, backs up every file it
changes, and `./uninstall.sh` puts them all back.

Or in one line, which fetches the same repository into
`~/.cache/nooxshell/repo` and runs the installer from there:

```bash
bash <(curl -fsSL https://github.com/whonoox/nooxshell/raw/master/install.sh)
```

To install or update to a specific release, name its tag:

```bash
NOOXSHELL_REPO_REF=v1.0.4 bash <(curl -fsSL https://github.com/whonoox/nooxshell/raw/v1.0.4/install.sh)
```

### Nightly

New features land on the `nightly` branch before they are in a release.
It is the newest work and has had the least use. To install it:

```bash
NOOXSHELL_REPO_REF=nightly bash <(curl -fsSL https://github.com/whonoox/nooxshell/raw/nightly/install.sh)
```

From a clone, `git checkout nightly` and run `./install.sh`. The plain
one-line install above goes back to `master`.

Options:

```bash
./install.sh              # interactive
./install.sh --dry-run    # show what would change, touch nothing
./install.sh --yes        # accept defaults
./install.sh --theme      # also install the Nooxnpaints theme, no prompt
./install.sh --no-theme   # do not offer the theme
./install.sh --font       # install NooxFont without asking
./install.sh --no-font    # leave NooxFont out (and remove it if installed)
```

The installer also installs [NooxFont](#fonts), the shell's typeface. It
is opt-out: the prompt defaults to yes, and `--yes` takes that default.
The answer is remembered, so `nooxshell update` keeps the font current
without asking again and never brings it back if you said no. An install
from before the font shipped is asked once, on its next update.

At the end, the installer offers the companion
[Nooxnpaints theme](https://github.com/whonoox/omarchy-nooxnpaints-theme),
which lives in its own repository. It is opt-in: the prompt defaults to no,
and `--yes` leaves it out. On yes, it runs
`omarchy theme install <repo>`, which clones the theme into
`~/.config/omarchy/themes/nooxnpaints` and makes it the current theme. If
the theme is already there, it is only made current with
`omarchy theme set nooxnpaints`, so local changes in it are kept. The
repository URL is set in `manifest.json` under `theme`.

Newer Ghostty, foot and GTK 4 apps (Files and the rest) ask Hyprland not
to blur behind their windows, which leaves the wallpaper sharp behind them.
The installer adds one setting to each so they ask for the blur:
`background-blur = true` in `~/.config/ghostty/config`, `alpha=0.99` at
the top of `~/.config/foot/foot.ini`, and a `backdrop-filter` rule in
`~/.config/gtk-4.0/gtk.css` (GTK 4.24 and later). Each sits between
`nooxshell blur` markers, which the uninstaller takes out. A file that
already sets the value is left alone. Open windows pick it up when the app
is restarted.

The installer backs up every file it touches to
`~/.local/state/nooxshell/backups/<timestamp>/` and writes the
installed state to `~/.local/state/nooxshell/state.json`.

## Uninstall

```bash
./uninstall.sh
```

Restores every backed-up file, removes the Hyprland module and its require
line, restores `shell.json`, and brings the stock Omarchy shell back up.

## Shortcuts

| Key | Action |
| :--- | :--- |
| `Super+Space` | Omarchy menu |
| `Super+Alt+Space` | Apps menu |
| `Super+Esc` / power key | System menu |
| `Super+Ctrl+C` / `H` / `S` / `R` | Capture, Hardware, Share and Set reminder menus |
| `Super+Ctrl+O` | Toggles island, to see every toggle's state without changing one |
| `Super+Ctrl+E` | Emoji picker on the menu: type to search, arrows to pick, `Enter` to type it into the focused window |
| `Super+Ctrl+W` | Wi-Fi |
| `Super+Ctrl+B` | Bluetooth |
| `Super+Ctrl+T` | Time |
| `Super+Ctrl+P` | Power |
| `Super+Ctrl+A` | Volume, with every output device: `←`/`→` pick, `↑`/`↓` level, `Enter` switch to it, `Esc` or a click outside to close |
| `Super+Ctrl+Space` | Wallpaper picker |
| `Super+Shift+Ctrl+Space` | Theme picker |
| Volume / Brightness keys | Island HUDs |
| `Super+Shift+Arrows` | Swap the active window, or move the picked tile group |
| `Super+Alt+K` | Key sounds on or off |

## Tile groups

On a workspace with three or more tiled windows, a small dot sits on each
split between them. A dot stands for the windows on both sides of its
split, the way Hyprland's dwindle layout divided them. Picking a dot closes
the gaps between those windows, so they read as one piece and it is clear
which windows move together.

- Hover a dot to pick its group for as long as the pointer stays on it.
  Click the dot to keep the group picked; click it again to let go.
- `Super+Shift+Arrows` moves the picked group one step, trading places with
  its neighbour on that side. With nothing picked, the keys swap the active
  window as in stock Omarchy. A group moved with the keys stays picked
  until Super is released.
- Drag a dot onto a window, or onto another dot, to trade the two.

The dots stay away from a workspace with a fullscreen window, a special
workspace on top, or a tabbed window group.

## Key sounds

`Super+Alt+K`, or the keyboard button in the toggle island, plays a
mechanical switch sound on every key press and release, with its own sound
for Space and Backspace, a pistol shot for Enter and for `Super+W`, which
closes the window (with the usual click when the key comes back up), and a
slightly different one for each row.
The set is a smooth linear switch in the style of Gateron Milky Yellow,
recorded on Alpaca switches (from [kbsim](https://github.com/tplai/kbsim),
MIT). With them on, locking the screen also plays a lock click, however it
locks: `Super+Ctrl+L`, the menu, going idle or closing the lid.

The sounds play only through the laptop's built-in speaker, even while
music goes to Bluetooth or HDMI. Headphones in the laptop's own jack share
that sound card, so they hear them too. `key_sound_volume` in
`config.toml` sets how loud they are. On or off is remembered across
restarts.

## Managing the shell

```bash
nooxshell --version     # installed version, branch and commit
nooxshell status        # instance, IPC health, available targets
nooxshell doctor        # check for stray instances and theme problems
nooxshell restart
nooxshell log -f
nooxshell toggle menu
```

Two Quickshell instances are always running: the stock Omarchy shell at
`/usr/share/omarchy/shell` and the islands at `~/.config/quickshell`. The
CLI scopes every operation to the islands instance with `qs --path`.

If every panel appears twice, once in the live theme colors and once in the
default palette, a stray instance is running. `nooxshell doctor`
identifies it and `nooxshell doctor --fix` stops it.

## Configuration

`~/.config/quickshell/config.toml` holds the user settings. Edits apply
live as soon as the file is saved.

```toml
rounding = 20                # corner radius in px for the islands, their scoops and the windows (0-20)
gaps = 4                     # px between windows and to the screen edge, and the islands' border (2-12, even)
active_opacity = 0.87        # how see-through the focused window is (0.3-1, 1 is solid)
inactive_opacity = 0.87      # the same for the other windows
two_column_app_grid = true   # the apps menu two to a line; false for a single list
hide_delay = 3.5             # seconds an island stays after popping up on its own (0.5-60)
workspace_hide_factor = 0.43 # the workspace bar's wait as a fraction of hide_delay (0-1, or 0-100 as %)
key_sound_volume = 80        # loudness of the key sounds on the built-in speaker (0-100)
```

Hyprland's window rounding, gaps and opacity follow these values, so set
them here rather than in `looknfeel.lua`. The see-through windows are what
let the blurred, grainy wallpaper show behind them, as behind the islands;
Omarchy's own per-app opacity (terminals, Glassy windows) multiplies on
top, so its Opaque window mode no longer makes windows solid: set both
opacities to 1 for that. An odd `gaps` rounds down to the even
number below it, so the gap between two windows splits evenly. Reinstalling keeps your copy.

## Layout

```
install.sh / uninstall.sh     one-click installer and rollback
manifest.json                 declarative deployment manifest
config.toml                   user settings (rounding, gaps, app grid, hide delays)
bin/nooxshell           management CLI
hypr/                         Hyprland bindings, layer rules, autostart
shims/                        command interceptors for ~/.local/bin
*.qml, *.js                   the shell
decorations/                  vector assets
fonts/                        NooxFont and its license
```

## Fonts

The shell's typeface is **NooxFont**, the display face cut from the
Nooxshell wordmark: every glyph is a rounded block with bites taken out of
it, on the grid of the Nooxshell icon. Every island title and readout is
set in it.

It ships in [`fonts/`](fonts) and the installer puts it in
`~/.local/share/fonts/nooxshell/` (see [Install](#install) for opting
out); the uninstaller removes it. Without it the titles use the system
font and everything still works. `nooxshell doctor` reports which one is
in use.

NooxFont was made by Noox, for Nooxshell first, and is free for anyone to
use: it is licensed under the
[SIL Open Font License 1.1](fonts/OFL.txt). You may use it in anything,
embed it, modify it and share it; you may not sell the font on its own.

## Documentation

- [docs/one_click_installable_shell_plan.md](docs/one_click_installable_shell_plan.md) — distribution plan and the verified facts behind it
- [QUICKSHELL_ARCHITECTURE.md](QUICKSHELL_ARCHITECTURE.md) — how the shell works internally

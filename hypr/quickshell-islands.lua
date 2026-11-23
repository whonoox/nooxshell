-- Floating island desktop shell for Omarchy.
--
-- Loaded from ~/.config/hypr/hyprland.lua with:
--
--   require("hypr.quickshell-islands")
--
-- The module name must live under the "hypr." prefix: Omarchy's Lua
-- bootstrap only clears package.loaded for the "default.hypr", "hypr" and
-- "omarchy.current.theme" prefixes, so a top-level module would never be
-- re-executed by `hyprctl reload`.
--
-- This file is the single source of truth for everything the islands need
-- from Hyprland. install.sh removes the equivalent hand-written blocks from
-- bindings.lua, looknfeel.lua and autostart.lua so nothing is bound twice.

-- Ensure ~/.local/bin takes precedence over /usr/share/omarchy/bin for custom user shims
local home = os.getenv("HOME")
if home and home ~= "" then
  hl.env("PATH", home .. "/.local/bin:" .. (os.getenv("PATH") or ""))
end

local bin = (home and home ~= "") and (home .. "/.local/bin/") or ""

local M = {}

-- The shell's global shortcuts are registered by the Quickshell instance and
-- dispatched straight into its event loop, so a keypress never spawns a
-- process. Unbinding first drops the Omarchy default for that combination.
--
-- Every key Omarchy binds to a menu route is listed, not only Super+Space.
-- From 4.5 Omarchy dispatches them to its own menu plugin, which the
-- installer disables, so a key left out here opens the stock menu until the
-- Omarchy shell restarts, then nothing at all. On 4.0.x they ran
-- omarchy-menu, which the shim already routes here.
M.bindings = {
  { key = "SUPER + SPACE", desc = "Omarchy menu", dispatch = "quickshell:menuToggle" },
  { key = "SUPER + SHIFT + code:201", desc = "Omarchy menu", dispatch = "quickshell:menuToggle" },
  { key = "SUPER + ALT + SPACE", desc = "Apps menu", dispatch = "quickshell:appsToggle" },
  { key = "SUPER + ESCAPE", desc = "System menu", dispatch = "quickshell:systemToggle" },
  { key = "XF86PowerOff", desc = "Power menu", dispatch = "quickshell:systemToggle", opts = { locked = true } },
  { key = "SUPER + CTRL + C", desc = "Capture menu", dispatch = "quickshell:captureToggle" },
  { key = "SUPER + CTRL + O", desc = "Toggle menu", dispatch = "quickshell:togglesToggle" },
  { key = "SUPER + CTRL + H", desc = "Hardware menu", dispatch = "quickshell:hardwareToggle" },
  { key = "SUPER + CTRL + S", desc = "Share", dispatch = "quickshell:shareToggle" },
  { key = "SUPER + CTRL + R", desc = "Set reminder", dispatch = "quickshell:reminderSetToggle" },
  { key = "SUPER + CTRL + W", desc = "Wifi HUD and Panel", dispatch = "quickshell:wifiToggle" },
  { key = "SUPER + CTRL + B", desc = "Bluetooth HUD and Panel", dispatch = "quickshell:bluetoothToggle" },
  { key = "SUPER + CTRL + T", desc = "Time HUD and Panel", dispatch = "quickshell:timeToggle" },
  { key = "SUPER + CTRL + P", desc = "Power HUD and Panel", dispatch = "quickshell:batteryToggle" },
  { key = "SUPER + CTRL + D", desc = "Brightness HUD and Panel", dispatch = "quickshell:brightnessToggle" },
  { key = "SUPER + CTRL + A", desc = "Volume HUD and Output devices", dispatch = "quickshell:audioToggle" },
  { key = "SUPER + CTRL + SPACE", desc = "Wallpaper switcher", dispatch = "quickshell:wallpaperToggle" },
  { key = "SUPER + SHIFT + CTRL + SPACE", desc = "Theme switcher", dispatch = "quickshell:themeToggle" },
  { key = "SUPER + ALT + N", desc = "Notification DND toggle", dispatch = "quickshell:notifToggle" },
  { key = "SUPER + ALT + M", desc = "Microphone mute toggle", dispatch = "quickshell:micToggle" },
  { key = "SUPER + ALT + C", desc = "Cursor X-Ray toggle", dispatch = "quickshell:cursorXRayToggle" },
  { key = "SUPER + ALT + I", desc = "Stay awake toggle", dispatch = "quickshell:stayAwakeToggle" },
  { key = "SUPER + ALT + L", desc = "Night light toggle", dispatch = "quickshell:nightLightToggle" },
  { key = "SUPER + ALT + K", desc = "Key sounds toggle", dispatch = "quickshell:keySoundsToggle" },
  { key = "XF86RFKill", desc = "Airplane mode toggle", dispatch = "quickshell:airplaneToggle" },
}

-- Hardware keys. Omarchy binds these to the same command names by default;
-- the shims in ~/.local/bin shadow the packaged binaries, so the islands HUD
-- answers instead of the stock OSD.
--
-- Mute has to be taken over too: Omarchy binds it to its shell's own
-- audio.mute-toggle shortcut, which never runs a command a shim could catch
-- and shows the stock OSD. A toggle does not repeat while held.
M.hardware_bindings = {
  { key = "XF86AudioRaiseVolume", desc = "Volume up", cmd = bin .. "omarchy-audio-output-volume +10" },
  { key = "XF86AudioLowerVolume", desc = "Volume down", cmd = bin .. "omarchy-audio-output-volume -10" },
  { key = "XF86AudioMute", desc = "Mute", cmd = bin .. "omarchy-audio-output-volume mute-toggle", repeating = false },
  { key = "XF86MonBrightnessUp", desc = "Brightness up", cmd = bin .. "omarchy-brightness-display +10%" },
  { key = "XF86MonBrightnessDown", desc = "Brightness down", cmd = bin .. "omarchy-brightness-display 10%-" },
  { key = "XF86AudioMicMute", desc = "Microphone mute toggle", cmd = "omarchy-audio-input-mute" },
}

-- Panel surfaces that get the compositor-level X-Ray blur: a hairline border
-- rendered at near-zero opacity acts as an aperture, so only the frosted
-- edge around each island is blurred and the interior stays crisp.
--
-- Only the panel surfaces are listed. The full-screen backdrops
-- (quickshell-wallpaper-grid) and the invisible twin-dismiss catchers
-- (wifi-panel-twin-dismiss, bluetooth-panel-twin-dismiss) are deliberately
-- excluded: they are opaque or fully transparent, so blurring them does
-- nothing but costs a pass.
M.island_namespaces = {
  "workspaces-panel-main",
  "time-panel-main",
  "wifi-panel-main",
  "bluetooth-panel-main",
  "audio-panel-main",
  "brightness-panel-main",
  "battery-panel-main",
  "notification-panel-main",
  "toggle-panel-main",
  "cursor-xray-main",
  "quickshell-omarchy-menu",
  "scoop-v2-inspector",
  "quickshell",
}

local function escape_pattern(text)
  -- Hyprland matches namespaces with a regular expression, so only the
  -- characters that are metacharacters there need escaping. The namespace
  -- names here are plain lowercase and dashes.
  return (text:gsub("([%.%+%[%]%(%)%^%$%|%?%*%\\])", "%%%1"))
end

-- The shell's user settings live in config.toml next to the QML. The shell
-- watches the file and pushes changes to Hyprland live; reading it here as
-- well keeps a `hyprctl reload` from reverting them. Only flat
-- `key = number` lines are needed (whole or decimal), so this is not a full
-- TOML parser.
M.config_path = (home or "") .. "/.config/quickshell/config.toml"

local function read_config()
  local config = {}
  local file = io.open(M.config_path, "r")
  if not file then
    return config
  end
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(%-?%d*%.?%d+)")
    if key and tonumber(value) then
      config[key] = tonumber(value)
    end
  end
  file:close()
  return config
end

M.config = read_config()

-- rounding in config.toml, as Theme.qml reads it: whole pixels, capped at
-- 20, the most the islands are laid out for. Missing or negative gives 20.
function M.rounding()
  local r = M.config.rounding
  if not r or r < 0 then
    return 20
  end
  return math.floor(math.min(r, 20))
end

-- active_opacity and inactive_opacity in config.toml, as Theme.qml reads
-- them: 0.3-1, 1 for solid windows. Missing or unreadable gives 0.87, the
-- see-through that lets the blur and grain show behind every window.
function M.opacity(key)
  local value = M.config[key]
  if not value then
    return 0.87
  end
  return math.min(1, math.max(0.3, value))
end

-- gaps in config.toml as Theme.clampGaps reads it: within 2-12 and even,
-- an odd value rounding down, so gaps_in is a whole pixel. Missing or
-- unreadable gives the default 4.
function M.gaps()
  local g = M.config.gaps
  if not g or g < 0 then
    return 4
  end
  g = math.min(12, math.max(2, g))
  return g - g % 2
end

-- The X-Ray effect needs the global decoration blur.
--
-- A layer rule asking for xray does nothing while
-- decoration:blur:enabled is false, which is Omarchy's default. The layer
-- rule below would then be applied and produce no visible effect at all.
--
-- The shell therefore owns these settings rather than depending on the
-- user's look'n'feel: without them the islands render flat, which is the
-- single most visible difference between the shell working and not.
--
-- The values match the ones this desktop was tuned with, so on a machine
-- that already has them the result is identical. The rounding and the gaps
-- come from the same config.toml as Theme.rounding and Theme.borderWidth,
-- so the island corners and borders line up with the windows.
function M.decorations()
  local gaps = M.gaps()
  hl.config({
    general = {
      -- The gaps are part of the same calculation as the shell's own
      -- border. The scoops are drawn with a border of gaps_out, and the
      -- gap between two windows is the same again (gaps_in on each side),
      -- so the islands and the windows sit in one rhythm.
      gaps_in = math.floor(gaps / 2),
      gaps_out = gaps,
      border_size = 0,
    },
    decoration = {
      rounding = M.rounding(),

      -- How see-through windows are, focused and not. Omarchy leaves most
      -- windows solid, which hides the blur and its grain; these let them
      -- show behind every window. Omarchy's own per-app opacity rules
      -- (terminals, Glassy mode) multiply on top.
      active_opacity = M.opacity("active_opacity"),
      inactive_opacity = M.opacity("inactive_opacity"),

      blur = {
        enabled = true,
        size = 10,
        passes = 2,
        noise = 0.15,
        contrast = 0.75,
      },
    },
  })
end

function M.apply()
  for _, binding in ipairs(M.bindings) do
    hl.unbind(binding.key)
    o.bind(binding.key, binding.desc, hl.dsp.global(binding.dispatch), binding.opts)
  end

  for _, binding in ipairs(M.hardware_bindings) do
    hl.unbind(binding.key)
    o.bind(binding.key, binding.desc, binding.cmd, { locked = true, repeating = binding.repeating ~= false })
  end

  local namespaces = {}
  for _, namespace in ipairs(M.island_namespaces) do
    table.insert(namespaces, escape_pattern(namespace))
  end

  hl.layer_rule({
    match = { namespace = "^(" .. table.concat(namespaces, "|") .. ")$" },
    blur = true,
    xray = true,
    ignore_alpha = 0.005,
  })

  -- The islands and the cursor X-Ray share the Overlay layer (see
  -- Theme.islandLayer). Within a layer Hyprland draws higher orders first,
  -- so a lower order lands on top: keep the X-Ray cursor above an island
  -- that opens after it.
  hl.layer_rule({
    match = { namespace = "^cursor-xray-main$" },
    order = -1,
  })

  -- The pickers animate themselves: they open zoomed into the wallpaper on
  -- screen and close zoomed into the new one, so any layer animation of
  -- Hyprland's own shows up as a frame that pops in or fades out over a
  -- desktop it already matches.
  hl.layer_rule({
    match = { namespace = "^(quickshell-wallpaper-grid|quickshell-theme-grid)$" },
    no_anim = true,
    animation = "none",
  })
end

-- The shell is started here so the islands come up with the session.
-- --no-duplicate keeps a second launcher from spawning a rival instance.
-- The wallpaper is Omarchy's own (its background plugin and OWE), which
-- Omarchy starts itself.
function M.autostart()
  o.launch_on_start("qs --no-duplicate")
end

-- Tile groups: moving a whole branch of the dwindle tree at once.
--
-- Dwindle keeps a binary tree of splits, but its own commands only ever act
-- on the parent of one window, so a branch of several windows cannot be
-- moved. The shell (TileGroups.qml) works the tree out from the window
-- geometry, draws a dot on each split, and decides what the new tree should
-- be. This side then rebuilds the workspace into exactly that tree.
--
-- The rebuild floats every window but the first, then tiles them back one at
-- a time: each window is opened next to the window it was split from, with
-- the side preselected and the ratio set right after, which is the same path
-- dwindle takes for a new window. It all runs inside one call, so the
-- compositor never draws the windows half rebuilt, only the windows sliding
-- from their old places to the new ones.
--
-- A tree is { a = "<address>" } for a window, or
-- { s = "v" | "h", r = <ratio>, c = { first, second } } for a split, where
-- "v" puts the children side by side and "h" stacks them. The ratio is
-- dwindle's own, where 1 is an even split.
QsTiles = QsTiles or {}
M.tiles = QsTiles

-- Set by the shell while a dot is hovered or picked, so Super+Shift+arrows
-- moves that group instead of the active window.
QsTiles.armed = false

-- A reload must not leave the previous Super listener behind.
if QsTiles.super_watch then
  pcall(function()
    QsTiles.super_watch:remove()
  end)
  QsTiles.super_watch = nil
end

local function window_selector(address)
  return "address:" .. address
end

local function first_window(node)
  while node.c do
    node = node.c[1]
  end
  return node.a
end

local function tree_windows(node, out)
  out = out or {}
  if node.c then
    tree_windows(node.c[1], out)
    tree_windows(node.c[2], out)
  else
    table.insert(out, node.a)
  end
  return out
end

local function tile_branch(node, window)
  if not node.c then
    return
  end

  local other = first_window(node.c[2])
  hl.dispatch(hl.dsp.focus({ window = window_selector(window) }))
  hl.dispatch(hl.dsp.layout("preselect " .. (node.s == "v" and "r" or "d")))
  hl.dispatch(hl.dsp.window.float({ action = "disable", window = window_selector(other) }))
  hl.dispatch(hl.dsp.focus({ window = window_selector(window) }))
  hl.dispatch(hl.dsp.layout(string.format("splitratio %.4f exact", node.r or 1)))

  tile_branch(node.c[1], window)
  tile_branch(node.c[2], other)
end

-- Rebuild the workspace of the tree's windows into `tree`. The tree has to
-- hold exactly that workspace's tiled windows; anything else means the shell
-- worked from an old picture, and the call fails rather than guess.
--
-- Dwindle takes layout messages for the focused monitor's workspace only;
-- focusing the tree's windows on the way makes that the right one.
function QsTiles.apply(tree)
  if type(tree) ~= "table" then
    error("qs-tiles: nothing to rebuild")
  end

  local windows = tree_windows(tree)
  local anchor = hl.get_window(window_selector(windows[1]))
  local workspace = anchor and anchor.workspace
  if not workspace or not workspace.visible then
    error("qs-tiles: the workspace is not on screen")
  end
  if workspace.has_fullscreen then
    error("qs-tiles: the workspace has a fullscreen window")
  end

  local wanted = {}
  for _, address in ipairs(windows) do
    wanted[address] = true
  end

  local tiled = 0
  for _, window in ipairs(hl.get_workspace_windows(workspace.id)) do
    if window.mapped and not window.floating then
      if window.group then
        error("qs-tiles: tabbed groups are not supported")
      end
      if not wanted[window.address] then
        error("qs-tiles: the tree is out of date")
      end
      tiled = tiled + 1
    end
  end
  if tiled ~= #windows then
    error("qs-tiles: the tree is out of date")
  end

  local active = hl.get_active_window()
  local cursor = hl.get_cursor_pos()

  for index = 2, #windows do
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = window_selector(windows[index]) }))
  end
  tile_branch(tree, windows[1])

  -- Focusing each window on the way warps the pointer; put both back.
  if active then
    hl.dispatch(hl.dsp.focus({ window = window_selector(active.address) }))
  end
  if cursor then
    hl.dispatch(hl.dsp.cursor.move({ x = cursor.x, y = cursor.y }))
  end
end

-- A group moved with the keys slides out from under the pointer, which would
-- drop the pick at once. The shell keeps it while Super is held and is told
-- here when Super comes up. The key listener only exists for that stretch.
--
-- Super is recognised by elimination, so a remapped Super (Caps Lock as
-- Super, say) works too: during a key move only Super, Shift and the arrows
-- are held, so a release of anything but Shift or an arrow is Super's.
local KEEP_HOLD_KEYCODES = {
  [50] = true, -- Shift_L
  [62] = true, -- Shift_R
  [111] = true, -- Up
  [113] = true, -- Left
  [114] = true, -- Right
  [116] = true, -- Down
}

local function watch_super_release()
  if QsTiles.super_watch then
    return
  end
  QsTiles.super_watch = hl.on("input.keyboard.key", function(keycode, _, state)
    if state ~= 0 or KEEP_HOLD_KEYCODES[keycode] then
      return
    end
    local watch = QsTiles.super_watch
    QsTiles.super_watch = nil
    if watch then
      pcall(function()
        watch:remove()
      end)
    end
    hl.dispatch(hl.dsp.global("quickshell:tilesHoldEnd"))
  end)
end

-- Super+Shift+arrows swaps the active window, as in Omarchy, unless a group
-- is armed: then the shell moves the group.
function QsTiles.key_move(dir)
  if QsTiles.armed then
    watch_super_release()
    local names = { l = "Left", r = "Right", u = "Up", d = "Down" }
    hl.dispatch(hl.dsp.global("quickshell:tilesMove" .. names[dir]))
  else
    hl.dispatch(hl.dsp.window.swap({ direction = dir }))
  end
end

function M.tile_bindings()
  local directions = {
    { key = "LEFT", dir = "l", desc = "left" },
    { key = "RIGHT", dir = "r", desc = "right" },
    { key = "UP", dir = "u", desc = "up" },
    { key = "DOWN", dir = "d", desc = "down" },
  }

  for _, direction in ipairs(directions) do
    local key = "SUPER + SHIFT + " .. direction.key
    hl.unbind(key)
    o.bind(key, "Swap window or tile group " .. direction.desc, function()
      QsTiles.key_move(direction.dir)
    end)
  end
end

-- Key sounds. While the shell has them on, every key press and release is
-- sent to it as the name of the sound to play, never as the key: one of the
-- five rows (keySoundR0 for the number row to keySoundR4 for the bottom),
-- Space, Enter or Backspace, and keySoundUp* for a release. The shell turns
-- the listener on and off with QsKeys.set, and again after a reload, which
-- starts with it off. With the sounds off there is no listener at all.
QsKeys = QsKeys or {}
M.keys = QsKeys

if QsKeys.watch then
  pcall(function()
    QsKeys.watch:remove()
  end)
  QsKeys.watch = nil
end

-- XKB keycodes (evdev + 8), as the key event reports them. Anything not
-- listed, such as the modifiers and the arrows, sounds as the bottom row.
local KEY_SOUNDS = { [65] = "Space", [36] = "Enter", [104] = "Enter", [22] = "Backspace" }
do
  local function span(sound, first, last)
    for code = first, last do
      KEY_SOUNDS[code] = sound
    end
  end
  local function each(sound, codes)
    for _, code in ipairs(codes) do
      KEY_SOUNDS[code] = sound
    end
  end
  span("R0", 10, 21) -- 1 to =
  span("R0", 67, 76) -- F1 to F10
  each("R0", { 9, 49, 95, 96, 119 }) -- Esc, `, F11, F12, Delete
  span("R1", 23, 35) -- Tab, Q to ]
  each("R1", { 51 }) -- \
  span("R2", 38, 48) -- A to '
  each("R2", { 66 }) -- Caps Lock
  span("R3", 52, 61) -- Z to /
  each("R3", { 50, 62 }) -- the Shifts
end

local KEY_RELEASES = { Space = "UpSpace", Enter = "UpEnter", Backspace = "UpBackspace" }

-- Super+W closes the window, so it fires the same shot as Enter. Only
-- Super on its own: Super+Shift+W and Super+Ctrl+W do other things.
local W, SUPERS = 25, { 133, 134 }
local OTHER_MODS = { 37, 105, 50, 62, 64, 108 } -- Ctrl, Shift, Alt

local function closesWindow(pressed)
  if not (pressed[SUPERS[1]] or pressed[SUPERS[2]]) then
    return false
  end
  for _, code in ipairs(OTHER_MODS) do
    if pressed[code] then
      return false
    end
  end
  return true
end

-- Keys that go down (or up) within CHORD_MS of each other sound as one.
-- Laptop firmware sends some function keys as shortcuts, Super+P,
-- Super+Shift+S or Ctrl+Alt+Tab, two or three keys within 1-5 ms of each
-- other, and a click for each stacked into a buzz. Two keys a person
-- presses are at least about 10 ms apart, and closer than that two clicks
-- would be heard as one anyway.
local CHORD_MS = 8

-- How long after the press a key that reports no release of its own
-- sounds as coming up (see QsKeys.set).
local TAP_MS = 100

function QsKeys.set(on)
  if QsKeys.watch then
    pcall(function()
      QsKeys.watch:remove()
    end)
    QsKeys.watch = nil
  end
  -- A real switch is silent while held. A held key arrives as a release
  -- and a press over and over, each pair carrying the time of the first
  -- press, so an event with the time of its key's press is a repeat. Each
  -- event can also arrive twice, so a press already sounded at that time,
  -- or a release of a key not down, is skipped too. pressed[keycode] is
  -- the time of the key's press while it is down.
  --
  -- Some hardware keys (brightness, mic mute, airplane mode on an IdeaPad)
  -- send their press and release together, with the same time, the moment
  -- the key goes down; nothing comes when it is let go. A release with its
  -- press's time is therefore held back for TAP_MS: a held key's repeat
  -- press follows it at once and cancels it, and otherwise it sounds as
  -- the key coming up, about as long after the press as a real tap. A
  -- press with a new time always sounds, whatever pressed[] says.
  QsKeys.pressed = {}
  QsKeys.downSound = {}
  QsKeys.upSeq = (QsKeys.upSeq or 0) + 1
  QsKeys.pendingUp = {}
  QsKeys.lastDown = nil
  QsKeys.lastUp = nil
  if not on then
    return
  end
  QsKeys.watch = hl.on("input.keyboard.key", function(keycode, time, state)
    local pressed = QsKeys.pressed
    -- A release sounds like its press: the shot's own up click after
    -- Super+W, even when Super came up first.
    local sound = QsKeys.downSound[keycode] or KEY_SOUNDS[keycode] or "R4"
    if state == 0 then
      if pressed[keycode] == nil then
        return
      end
      if pressed[keycode] == time then
        QsKeys.upSeq = QsKeys.upSeq + 1
        local seq = QsKeys.upSeq
        QsKeys.pendingUp[keycode] = seq
        hl.timer(function()
          if QsKeys.pendingUp[keycode] ~= seq then
            return
          end
          QsKeys.pendingUp[keycode] = nil
          QsKeys.pressed[keycode] = nil
          QsKeys.downSound[keycode] = nil
          hl.dispatch(hl.dsp.global("quickshell:keySound" .. (KEY_RELEASES[sound] or "Up")))
        end, { timeout = TAP_MS, type = "oneshot" })
        return
      end
      pressed[keycode] = nil
      QsKeys.downSound[keycode] = nil
      QsKeys.pendingUp[keycode] = nil
      -- Events can arrive a millisecond out of order, hence math.abs.
      local chord = QsKeys.lastUp ~= nil and math.abs(time - QsKeys.lastUp) < CHORD_MS
      QsKeys.lastUp = time
      if chord then
        return
      end
      sound = KEY_RELEASES[sound] or "Up"
    else
      if pressed[keycode] == time then
        QsKeys.pendingUp[keycode] = nil
        return
      end
      pressed[keycode] = time
      QsKeys.pendingUp[keycode] = nil
      sound = (keycode == W and closesWindow(pressed)) and "Enter" or (KEY_SOUNDS[keycode] or "R4")
      QsKeys.downSound[keycode] = sound
      local chord = QsKeys.lastDown ~= nil and math.abs(time - QsKeys.lastDown) < CHORD_MS
      QsKeys.lastDown = time
      if chord then
        return
      end
    end
    hl.dispatch(hl.dsp.global("quickshell:keySound" .. sound))
  end)
end

M.decorations()
M.apply()
M.tile_bindings()
M.autostart()

return M

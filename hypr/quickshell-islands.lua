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
M.bindings = {
  { key = "SUPER + SPACE", desc = "Omarchy menu", dispatch = "quickshell:menuToggle" },
  { key = "SUPER + ALT + SPACE", desc = "Apps menu", dispatch = "quickshell:appsToggle" },
  { key = "SUPER + CTRL + W", desc = "Wifi HUD and Panel", dispatch = "quickshell:wifiToggle" },
  { key = "SUPER + CTRL + B", desc = "Bluetooth HUD and Panel", dispatch = "quickshell:bluetoothToggle" },
  { key = "SUPER + CTRL + T", desc = "Time HUD and Panel", dispatch = "quickshell:timeToggle" },
  { key = "SUPER + CTRL + P", desc = "Power HUD and Panel", dispatch = "quickshell:batteryToggle" },
  { key = "SUPER + CTRL + D", desc = "Brightness HUD and Panel", dispatch = "quickshell:brightnessToggle" },
  { key = "SUPER + CTRL + SPACE", desc = "Wallpaper switcher", dispatch = "quickshell:wallpaperToggle" },
  { key = "SUPER + SHIFT + CTRL + SPACE", desc = "Theme switcher", dispatch = "quickshell:themeToggle" },
  { key = "SUPER + ALT + N", desc = "Notification DND toggle", dispatch = "quickshell:notifToggle" },
  { key = "SUPER + ALT + M", desc = "Microphone mute toggle", dispatch = "quickshell:micToggle" },
  { key = "SUPER + ALT + C", desc = "Cursor X-Ray toggle", dispatch = "quickshell:cursorXRayToggle" },
  { key = "SUPER + ALT + I", desc = "Stay awake toggle", dispatch = "quickshell:stayAwakeToggle" },
  { key = "SUPER + ALT + L", desc = "Night light toggle", dispatch = "quickshell:nightLightToggle" },
  { key = "XF86RFKill", desc = "Airplane mode toggle", dispatch = "quickshell:airplaneToggle" },
}

-- Hardware keys. Omarchy binds these to the same command names by default;
-- the shims in ~/.local/bin shadow the packaged binaries, so the islands HUD
-- answers instead of the stock OSD.
M.hardware_bindings = {
  { key = "XF86AudioRaiseVolume", desc = "Volume up", cmd = bin .. "omarchy-audio-output-volume +10" },
  { key = "XF86AudioLowerVolume", desc = "Volume down", cmd = bin .. "omarchy-audio-output-volume -10" },
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
  -- Drop Omarchy default audio binding so SUPER + CTRL + A is free
  hl.unbind("SUPER + CTRL + A")

  for _, binding in ipairs(M.bindings) do
    hl.unbind(binding.key)
    o.bind(binding.key, binding.desc, hl.dsp.global(binding.dispatch))
  end

  for _, binding in ipairs(M.hardware_bindings) do
    hl.unbind(binding.key)
    o.bind(binding.key, binding.desc, binding.cmd, { locked = true, repeating = true })
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

M.decorations()
M.apply()
M.autostart()

return M

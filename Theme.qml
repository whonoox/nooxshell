pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string colorsPath: home + "/.local/state/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"
    // User settings shared with the Hyprland module (see config.toml).
    readonly property string configPath: Quickshell.shellPath("config.toml")

    // Theme Mode ("dark" | "light")
    property string mode: "dark"
    readonly property bool isLight: mode === "light"

    // Primary Accents
    property color accent: "#82FB9C"
    property color brand: accent
    readonly property color brandBgc: Qt.rgba(accent.r, accent.g, accent.b, isLight ? 0.2 : 0.25)

    // Full Palette Colors
    property color red: "#50f872"
    property color yellow: "#50f7d4"
    property color orange: "#50f7a3"
    property color green: "#00946d"
    property color cyan: "#7cf8f7"
    property color blue: "#829dd4"
    property color magenta: "#86a7df"
    property color brown: "#287b51"

    // Surfaces & Depth: Dynamic theme background color
    property color themeBackground: isLight ? "#ffffff" : "#0B0C16"
    readonly property color bgc: themeBackground
    readonly property color background: bgc
    property color darkBackground: isLight ? "#f0f0f0" : "#080910"
    property color darkerBackground: isLight ? "#e5e5e5" : "#06060c"
    property color lighterBackground: isLight ? "#f8f8f8" : "#151828"
    property color surface: lighterBackground
    property color selection: isLight ? "#e2e8f0" : "#1f253a"

    // Text & Hierarchy
    property color foreground: isLight ? "#1a1a1a" : "#ddf7ff"
    readonly property color fgc: foreground
    property color brightForeground: isLight ? "#000000" : "#ddf7ff"
    property color lightForeground: isLight ? "#4a5568" : "#b5c5db"
    property color darkForeground: isLight ? "#718096" : "#6a6e95"
    property color muted: isLight ? "#a0aec0" : "#2d3450"
    property color urgent: red

    // The one selection state every island shares: whatever the keyboard
    // cursor or the pointer is on sits on a plate of selectedFill edged in
    // selectedBorder. A plain item (a row, a neutral button) takes the plate
    // as its own fill and border. A control whose fill means something (a
    // switch that is on, a Connect button) keeps that fill, and the plate
    // shows as a halo around it instead; see SelectionHalo.qml.
    readonly property color selectedFill: selection
    readonly property color selectedBorder: darkForeground
    readonly property real selectedBorderWidth: 1
    readonly property real selectedHaloPad: spacing / 2

    // The layer every island, panel and picker sits on. Overlay, not Top:
    // Hyprland lets a Top surface over a fullscreen window only if it
    // mapped after the window went fullscreen, and pushes every Top surface
    // already on screen beneath it (in the scrolling layout, on more
    // occasions still). So a pinned island, like a critical battery, was
    // covered by any fullscreen app, and on a scrolling workspace every
    // island was. Overlay is always drawn above fullscreen windows. The
    // cursor X-Ray shares the layer and is kept on top of the islands by a
    // layer rule in hypr/quickshell-islands.lua.
    readonly property int islandLayer: WlrLayer.Overlay

    // Dimensions
    //
    // borderWidth is gaps in config.toml: the same value is pushed to
    // Hyprland as gaps_out, with gaps_in at half of it, so the scoops are
    // drawn with the same border as the gap between two windows and the
    // gap to the screen edge, and the islands and the windows sit in one
    // rhythm. It is kept even (gaps_in has to be a whole pixel) and within
    // minGaps-maxGaps; see clampGaps.
    //
    // rounding comes from config.toml and is pushed to Hyprland's
    // decoration:rounding, so window corners follow the islands. It is
    // capped at unit: the panels are laid out so their scoops fit at any
    // radius up to it, and a wider curve would outgrow the content.
    property int rounding: 20
    // two_column_app_grid in config.toml: the apps menu two to a line, or
    // the single list every other menu uses.
    property bool twoColumnAppGrid: true

    // hide_delay in config.toml, in seconds: how long an island that popped
    // up on its own (time, Wi-Fi, Bluetooth, audio, brightness, battery)
    // stays before it slides away.
    property int hideDelay: 3500
    // workspace_hide_factor: the workspace bar leaves sooner, this fraction
    // of hideDelay (1.5s of the default 3.5s).
    property real workspaceHideFactor: 1500 / 3500
    readonly property int workspaceHideDelay: Math.max(100, Math.round(hideDelay * workspaceHideFactor))

    // key_sound_volume in config.toml, as a fraction: how loud the key
    // sounds play on the built-in speaker, on top of its own volume.
    property real keySoundVolume: 0.8

    // The toggle HUD keeps its own shorter wait, 2.5s of the default 3.5s,
    // and follows hide_delay in the same proportion.
    readonly property int toggleHideDelay: Math.max(100, Math.round(hideDelay * 2500 / 3500))
    // Layout unit for island content: padding, header heights and label
    // sizes. The islands were laid out against a fixed 20px radius, so
    // this keeps their content the same size whatever rounding is. Only
    // the room a panel leaves for its scoop curves (rounding + borderWidth
    // margins) follows rounding.
    readonly property int unit: 20
    readonly property real spacing: 6
    property int borderWidth: 4
    readonly property int minGaps: 2
    readonly property int maxGaps: 12
    // Radius of the off-screen turn that ends each scoop flare (see
    // ScoopContour). On screen it leaves the border running on along the
    // screen edge for sqrt((c + d)^2 - c^2) px past the flare, which at
    // 1.5 * borderWidth is 2 * borderWidth. scoopCapOverhang is how far that
    // reaches past the scoop's own bounds, plus a pixel for antialiasing;
    // panels whose window is no bigger than the scoop pad by it.
    readonly property real scoopCapRadius: borderWidth * 1.5
    readonly property int scoopCapOverhang: Math.ceil(Math.sqrt(Math.pow(scoopCapRadius + borderWidth, 2) - scoopCapRadius * scoopCapRadius) - borderWidth) + 1
    // Typography
    //
    // The brand font is not bundled with the shell: it is a personal
    // typeface that lives in the system font directory on the machines
    // that have it. Resolve it at runtime from the installed families, so
    // a machine without it falls back to the system font instead of
    // rendering with a missing family.
    readonly property string brandFontName: "Nuuxfont"
    readonly property bool hasBrandFont: Qt.fontFamilies().indexOf(brandFontName) >= 0
    readonly property string brandFont: hasBrandFont ? brandFontName : fontFamily
    // The system font: "monospace", which fontconfig resolves to the font
    // `omarchy font set` chose.
    readonly property string fontFamily: "monospace"

    // Island titles: the time, the Wi-Fi and Bluetooth names and the slider
    // readouts, all set in brandFont. The monospace fallback is far wider
    // and heavier than the brand face at the same pixel size, so it is set
    // smaller and lighter to read at the same weight.
    readonly property int titleSize: hasBrandFont ? 16 : 13
    // The day name in the expanded time island.
    readonly property int headlineSize: hasBrandFont ? 22 : 17
    readonly property int titleWeight: hasBrandFont ? Font.Bold : Font.DemiBold
    // Height of a capital at titleSize. The two faces sit at different
    // heights inside their line boxes, so a title is aligned by its
    // baseline, half a cap height below the centre it should sit on.
    readonly property real titleCapHeight: titleCaps.tightBoundingRect.height
    // Body height shared by the islands on the top edge (time, workspaces,
    // Wi-Fi, Bluetooth), so their bottom edges line up: one title line
    // padded by unit, plus the border. It excludes the scoop flares, which
    // the corner islands add below it along the screen edge.
    readonly property int topIslandHeight: Math.ceil(titleCaps.height) + unit + borderWidth
    // The battery, volume and brightness panels share one height: four
    // bars of sideSegmentHeight, each with a gap, and one readout line,
    // plus the flares above and below (rounding + 2 * spacing each) and
    // room for the scoop's edge caps.
    readonly property int sideSegmentHeight: 18
    // Their width: a 34px column of bars, the spacing on the inner side and
    // the border on both, 48 at the default gaps. The column keeps its width
    // and the island grows with the border, as every other island does.
    readonly property int sidePanelWidth: 34 + spacing + 2 * borderWidth
    readonly property int sidePanelHeight: 4 * (sideSegmentHeight + spacing / 2) + Math.ceil(titleCaps.height)
        + 2 * (rounding + spacing * 2) + 2 * scoopCapOverhang
    property TextMetrics titleCaps: TextMetrics {
        font.family: root.brandFont
        font.pixelSize: root.titleSize
        font.weight: root.titleWeight
        text: "H"
    }

    function parseToml(raw) {
        var map = {}
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line || line.startsWith("#") || line.startsWith("[")) continue
            var idx = line.indexOf("=")
            if (idx === -1) continue
            var k = line.substring(0, idx).trim()
            var rawVal = line.substring(idx + 1).trim()
            var match = rawVal.match(/^["']([^"']*)["']/)
            var v = match ? match[1] : rawVal.split("#")[0].trim()
            map[k] = v
        }
        return map
    }

    function loadColors(text) {
        if (!text) return
        var d = parseToml(text)
        if (d.mode) {
            root.mode = d.mode.toLowerCase()
        }

        if (d.accent) root.accent = d.accent
        if (d.background) root.themeBackground = d.background
        if (d.dark_background) root.darkBackground = d.dark_background
        if (d.darker_background) root.darkerBackground = d.darker_background
        if (d.lighter_background) root.lighterBackground = d.lighter_background
        if (d.selection) root.selection = d.selection
        if (d.foreground) root.foreground = d.foreground
        if (d.bright_foreground) root.brightForeground = d.bright_foreground
        if (d.light_foreground) root.lightForeground = d.light_foreground
        if (d.dark_foreground) root.darkForeground = d.dark_foreground
        if (d.muted) root.muted = d.muted
        if (d.red) root.red = d.red
        if (d.yellow) root.yellow = d.yellow
        if (d.orange) root.orange = d.orange
        if (d.green) root.green = d.green
        if (d.cyan) root.cyan = d.cyan
        if (d.blue) root.blue = d.blue
        if (d.magenta) root.magenta = d.magenta
        if (d.brown) root.brown = d.brown
    }

    function loadConfig(text) {
        if (!text) return
        var d = parseToml(text)

        // Percent, 0-100. Missing or unreadable keeps 80.
        var keyVolume = parseFloat(d.key_sound_volume)
        root.keySoundVolume = isFinite(keyVolume)
            ? Math.min(100, Math.max(0, keyVolume)) / 100 : 0.8

        // A missing or unreadable value keeps the default (true).
        var twoColumns = String(d.two_column_app_grid || "").toLowerCase()
        root.twoColumnAppGrid = twoColumns !== "false"

        // Seconds, decimals allowed; 0.5 to 60. Missing or unreadable keeps 3.5.
        var delay = parseFloat(d.hide_delay)
        root.hideDelay = isFinite(delay) && delay > 0
            ? Math.round(Math.min(60, Math.max(0.5, delay)) * 1000) : 3500

        // A fraction of hide_delay, 0-1; a value above 1 is read as a
        // percentage (43 = 0.43). Missing or unreadable keeps 1.5 / 3.5.
        var factor = parseFloat(d.workspace_hide_factor)
        if (isFinite(factor) && factor > 1) factor = factor / 100
        root.workspaceHideFactor = isFinite(factor) && factor > 0
            ? Math.min(1, factor) : 1500 / 3500

        // Pushed to Hyprland on every load, not only on a change: the file
        // may have been edited while the shell was down, and Hyprland only
        // rereads it on a reload. The Hyprland module reads the same values
        // the same way (hypr/quickshell-islands.lua), so a reload agrees.
        var decoration = []

        // A missing or unreadable rounding keeps what the shell has.
        var r = parseInt(d.rounding, 10)
        if (isFinite(r) && r >= 0) {
            r = Math.min(r, root.unit)
            root.rounding = r
            decoration.push("rounding = " + r)
        }

        // How see-through windows are, focused and not: 0.3-1, 1 for solid.
        // Missing or unreadable is 0.87.
        decoration.push("active_opacity = " + windowOpacity(d.active_opacity))
        decoration.push("inactive_opacity = " + windowOpacity(d.inactive_opacity))

        // Missing or unreadable is the default 4, as in the Hyprland module.
        var g = clampGaps(parseInt(d.gaps, 10)) || 4
        root.borderWidth = g

        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ decoration = { " + decoration.join(", ")
            + " }, general = { gaps_in = " + (g / 2) + ", gaps_out = " + g + " } })"])
    }

    // gaps from config.toml as the shell uses it, or 0 when unreadable. Kept
    // even so gaps_in, half of it, is a whole pixel and two windows sit
    // exactly one gap apart: an odd value rounds down (5 is 4). Held within
    // minGaps-maxGaps, the widths the islands are laid out for. The Hyprland
    // module (hypr/quickshell-islands.lua) applies the same rule.
    function clampGaps(g) {
        if (!isFinite(g) || g < 0) return 0
        g = Math.min(root.maxGaps, Math.max(root.minGaps, g))
        return g - g % 2
    }

    function windowOpacity(value) {
        var o = parseFloat(value)
        return isFinite(o) ? Math.min(1, Math.max(0.3, o)) : 0.87
    }

    property FileView configFile: FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadConfig(text())
        onFileChanged: reload()
    }

    property FileView themeNameFile: FileView {
        id: themeNameFile
        path: root.themeNamePath
        watchChanges: true
        printErrors: false
        onLoaded: colorsReloadTimer.restart()
        onFileChanged: {
            reload()
            colorsReloadTimer.restart()
        }
    }

    property Timer colorsReloadTimer: Timer {
        id: colorsReloadTimer
        interval: 50
        repeat: false
        onTriggered: {
            colorsFile.reload()
            if (colorsFile.text()) {
                root.loadColors(colorsFile.text())
            }
        }
    }

    property FileView colorsFile: FileView {
        id: colorsFile
        path: root.colorsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadColors(text())
        onFileChanged: {
            reload()
            if (text()) {
                root.loadColors(text())
            }
        }
    }

    Component.onCompleted: {
        themeNameFile.reload()
        colorsFile.reload()
        if (colorsFile.text()) {
            root.loadColors(colorsFile.text())
        }
    }
}

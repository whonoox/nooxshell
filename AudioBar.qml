import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Output volume island, pinned to the left edge and built to the same language
// as BatteryBar: a vertical pill that slides off-screen to hide, with four
// bars that fill to the current level in half-bar steps.
//
// It expands the way wiremix's Output Devices tab works: every output that can
// play right now gets a meter of its own, side by side, growing out from the
// edge. Collapsed, only the first column shows -- the default output. Click a
// column to make it the default, scroll on it to set its level, click its
// bottom bar to mute it. Super+Ctrl+A opens the island expanded and closes it;
// clicking the default column expands and collapses it.
//
// State is read through pactl rather than Quickshell's Pipewire service. The
// Pipewire node for the default sink never leaves `ready=false` with zero
// channels here, so `sink.audio.volume` reads 0 and writes are discarded --
// verified against wpctl, which kept reporting the real level. bin/audio-outputs
// reads the same sinks omarchy-audio-output-volume does, so the bar and the OSD
// agree.
//
// Changes to the default output go through the omarchy helpers rather than
// pactl directly, so adjusting it from the bar raises the same OSD the volume
// keys do. The other outputs have no helper to go through and are set with
// pactl, on the sink that really carries their level.
Scope {
    id: root

    // One entry per output, default first; see bin/audio-outputs.
    //   { index, name, isDefault, volume, muted, kind, target, description }
    // volume is 0.0 - 1.0 and may exceed 1.0; the meter clamps.
    property var devices: []

    // The default output, mirrored for the collapsed view and the OSD logic.
    property real volume: 0
    property bool muted: false
    property bool available: false
    property string defaultName: ""

    property bool hideBar: true
    property bool isExpanded: false
    // Set by the island's HoverHandler: the pointer on it holds it open.
    property bool hovered: false

    // Keyboard cursor over the expanded columns: Left and Right move it, Up
    // and Down set that output's level, Enter makes it the default and
    // collapses onto it, Escape closes the island.
    property int selectedIndex: 0

    // The screen the island expanded on. Expanded, it covers that screen with
    // a click-to-dismiss overlay, as Wi-Fi does, so it stays put there rather
    // than following the focused monitor.
    property var pinnedScreen: null

    // The focus ring sits in the gap around a column.
    readonly property real ringPad: Theme.selectedHaloPad

    property real lastToggleTime: 0

    // Column metrics. One column keeps the island at the width the side
    // panels share (Theme.sidePanelWidth); each extra output adds a column of
    // the same width.
    readonly property real collapsedWidth: Theme.sidePanelWidth
    readonly property real columnWidth: collapsedWidth - Theme.spacing - 2 * Theme.borderWidth
    // Expanded spacing: wider between outputs, and between the four bars of
    // each. Collapsed, the bars keep the gap the side panels share, so the
    // meter still matches battery and brightness.
    readonly property real columnGap: Theme.spacing * 2
    readonly property real segmentGap: root.isExpanded ? Theme.spacing : Theme.spacing / 2

    // Expanded, the island also grows taller: each of the four bars doubles,
    // which reads slimmer and leaves the panel room for more controls. The
    // collapsed meter keeps the height the side panels share.
    // The rounded ends of the meter follow the island: concentric with its
    // corners, whose fill turns at rounding - borderWidth, less the gap
    // (spacing - borderWidth) the bars keep from that fill edge.
    readonly property real barRadius: Math.max(4, Theme.rounding - Theme.spacing)

    readonly property real expandedExtraHeight: 4 * Theme.sideSegmentHeight
    readonly property real panelHeight: Theme.sidePanelHeight + (root.isExpanded ? root.expandedExtraHeight : 0)

    function pillWidth(columns) {
        var n = Math.max(1, columns)
        return root.collapsedWidth + (n - 1) * (root.columnWidth + root.columnGap)
    }

    // Four bars, lit in eighths: the next bar shows at half strength
    // before it fills, so two steps share each bar.
    function stepsFor(device) {
        if (!device || device.muted || device.volume <= 0) return 0
        return Math.min(8, Math.max(1, Math.ceil(device.volume * 8)))
    }

    // The default output is drawn in the brand colour, the others dimmed, so
    // the expanded island still says which one is playing.
    function accentFor(device) {
        return device && device.isDefault ? Theme.brand : Theme.lightForeground
    }

    function trackFor(device) {
        if (device && device.isDefault) return Theme.brandBgc
        var c = Theme.lightForeground
        return Qt.rgba(c.r, c.g, c.b, Theme.isLight ? 0.2 : 0.25)
    }

    // Bar 1 is the bottom one.
    function barColor(device, bar) {
        var steps = root.stepsFor(device)
        var boosted = device && device.volume > 1.0
        if (steps >= 2 * bar) return (bar === 4 && boosted ? Theme.yellow : root.accentFor(device))
        if (steps === 2 * bar - 1) return Qt.tint(root.trackFor(device), Qt.alpha(root.accentFor(device), 0.5))
        return root.trackFor(device)
    }

    function glyphFor(device) {
        if (!device) return ""
        switch (device.kind) {
            case "bluetooth": return ""
            case "headphones": return ""
            case "monitor": return ""
            case "usb": return ""
            default: return device.muted ? "" : ""
        }
    }

    // Refreshes the meters. Called on open, on a short timer while visible, and
    // immediately after any change this bar makes so the segments never lag
    // behind the OSD.
    function refresh() {
        if (probeProcess.running) {
            root.refreshQueued = true
            return
        }
        probeProcess.running = true
    }
    property bool refreshQueued: false

    function reveal() {
        PopoutCoordinator.claimHud("audio")
        root.hideBar = false
        autoHide.restart()
    }

    function expand() {
        root.reveal()
        root.isExpanded = true
        root.refresh()
    }

    function collapse() {
        root.isExpanded = false
        autoHide.restart()
    }

    // Default output first, the rest in pactl's order. While expanded the
    // columns keep their places, so a click never moves the column under the
    // pointer; the new default moves to the front once the island collapses.
    function ordered(list) {
        var result = []
        var i
        if (root.isExpanded && root.devices.length > 0) {
            for (i = 0; i < root.devices.length; i++) {
                for (var j = 0; j < list.length; j++) {
                    if (list[j].name === root.devices[i].name) { result.push(list[j]); break }
                }
            }
            for (i = 0; i < list.length; i++) {
                if (result.indexOf(list[i]) === -1) result.push(list[i])
            }
            return result
        }
        for (i = 0; i < list.length; i++) if (list[i].isDefault) result.push(list[i])
        for (i = 0; i < list.length; i++) if (!list[i].isDefault) result.push(list[i])
        return result
    }

    // Replaces one output's entry; a new array so every binding re-evaluates.
    function patch(name, changes) {
        var next = []
        for (var i = 0; i < root.devices.length; i++) {
            var d = root.devices[i]
            var copy = {}
            for (var k in d) copy[k] = d[k]
            if (d.name === name) for (var c in changes) copy[c] = changes[c]
            next.push(copy)
        }
        root.devices = next
    }

    // Relative steps, so the OSD the helpers raise matches what the bar shows.
    function nudge(percent) {
        if (!root.available) return
        var action = percent >= 0 ? "+" + Math.round(percent) : "-" + Math.abs(Math.round(percent))
        Quickshell.execDetached(["omarchy-audio-output-volume", action])
        root.reveal()
        settle.restart()
    }

    function toggleMute() {
        if (!root.available) return
        Quickshell.execDetached(["omarchy-audio-output-volume", "mute-toggle"])
        root.reveal()
        settle.restart()
    }

    // The default output goes through the helpers above. Any other output is
    // set directly, with the helper's rules: steps stop at 0 and 100, and a
    // level change unmutes.
    function nudgeDevice(device, percent) {
        if (!device) return
        if (device.isDefault) { root.nudge(percent); return }

        var current = Math.round(device.volume * 100)
        var next = percent >= 0 ? Math.min(100, current + percent) : Math.max(0, current + percent)
        Quickshell.execDetached(["sh", "-c", 'pactl set-sink-mute "$1" 0; pactl set-sink-volume "$1" "$2%"',
            "sh", device.target, String(next)])
        root.patch(device.name, { volume: next / 100, muted: false })
        autoHide.restart()
        settle.restart()
    }

    function toggleMuteDevice(device) {
        if (!device) return
        if (device.isDefault) { root.toggleMute(); return }

        Quickshell.execDetached(["pactl", "set-sink-mute", device.target, "toggle"])
        root.patch(device.name, { muted: !device.muted })
        autoHide.restart()
        settle.restart()
    }

    // Moves playing streams too, the same as the Omarchy output switcher.
    function makeDefault(device) {
        if (!device || device.isDefault) return
        Quickshell.execDetached(["omarchy-audio-output-set-default", String(device.index), device.name])

        var next = []
        for (var i = 0; i < root.devices.length; i++) {
            var d = root.devices[i]
            var copy = {}
            for (var k in d) copy[k] = d[k]
            copy.isDefault = d.name === device.name
            next.push(copy)
        }
        root.devices = next
        root.defaultName = device.name
        root.volume = device.volume
        root.muted = device.muted
        autoHide.restart()
        settle.restart()
    }

    // Super+Ctrl+A goes straight to every output; pressed again, it closes.
    // The volume keys still raise the collapsed meter on their own.
    function cycle() {
        if (!root.hideBar && root.isExpanded) root.hideBar = true
        else root.expand()
    }

    IpcHandler {
        target: "audioBar"

        function toggle(): string { root.cycle(); return root.hideBar ? "closed" : (root.isExpanded ? "expanded" : "open") }
        function open(): string { root.reveal(); root.refresh(); return "ok" }
        function expand(): string { root.expand(); return "ok" }
        function close(): string { root.hideBar = true; return "ok" }
        function refresh(): string { root.refresh(); return "ok" }
        function mute(): string { root.toggleMute(); return "ok" }
        function raise(): string { root.nudge(10); return "ok" }
        function lower(): string { root.nudge(-10); return "ok" }
        function ping(): string { return "ok" }
    }

    GlobalShortcut {
        name: "audioToggle"
        description: "Open the Volume HUD with every output device, close it on the next press"
        appid: "quickshell"
        onPressed: {
            // Drop only the duplicate event of one keypress, so a single
            // press never opens and immediately closes the island.
            var now = Date.now()
            if (now - root.lastToggleTime < 40) return
            root.lastToggleTime = now
            root.cycle()
        }
    }

    Process {
        id: probeProcess
        command: [Quickshell.shellPath("bin/audio-outputs")]
        stdout: StdioCollector {
            waitForEnd: true
            // `this.text`, not a signal argument: onStreamFinished passes no
            // parameter, so reading one yields undefined and the meter never
            // leaves zero.
            onStreamFinished: {
                var lines = String(this.text || "").trim().split("\n")
                var list = []
                for (var i = 0; i < lines.length; i++) {
                    var f = lines[i].split("\t")
                    if (f.length < 8 || f[1] === "") continue
                    list.push({
                        index: parseInt(f[0]),
                        name: f[1],
                        isDefault: f[2] === "1",
                        // pactl allows volumes above 100%; keep them, the meter clamps.
                        volume: Math.max(0, (parseFloat(f[3]) || 0) / 100),
                        muted: f[4] === "1",
                        kind: f[5],
                        target: f[6] || f[1],
                        description: f.slice(7).join(" ")
                    })
                }

                if (list.length === 0) {
                    root.devices = []
                    root.available = false
                    root.volume = 0
                    root.muted = false
                    root.defaultName = ""
                    return
                }

                var current = null
                for (i = 0; i < list.length; i++) if (list[i].isDefault) { current = list[i]; break }
                if (!current) current = list[0]

                // Only a real level or mute change on the default output, or a
                // new default output, raises the bar; see the pactl subscriber.
                var changed = root.available && root.defaultName !== ""
                    && (current.name !== root.defaultName
                        || current.volume !== root.volume
                        || current.muted !== root.muted)

                root.devices = root.ordered(list)
                root.available = true
                root.defaultName = current.name
                root.volume = current.volume
                root.muted = current.muted

                if (changed && root._initialized) root.reveal()
            }
        }
        // A refresh asked for mid-probe runs once this one is done, so a
        // change made during it is never missed.
        onExited: {
            if (root.refreshQueued) {
                root.refreshQueued = false
                Qt.callLater(root.refresh)
            }
        }
    }

    property bool _initialized: false

    Process {
        id: pactlSubscriber
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                // Sinks also report 'change' whenever playback starts or stops
                // (state, latency), and "on sink-input" events fire per stream,
                // so neither means the volume moved. Re-probe on a sink, server
                // (default output) or card (port plugged) event and let the
                // probe decide whether to reveal. "sink #" never matches
                // "sink-input #".
                if (/'(new|remove|change)' on (sink|server|card) #/.test(line)) {
                    root.refresh()
                }
            }
        }
        onExited: restartSubscriberTimer.restart()
    }

    Timer {
        id: restartSubscriberTimer
        interval: 1000
        onTriggered: pactlSubscriber.running = true
    }

    Component.onCompleted: {
        root.refresh()
        Qt.callLater(function() {
            root._initialized = true
        })
    }

    onHideBarChanged: {
        if (!root.hideBar) {
            PopoutCoordinator.claimHud("audio")
            autoHide.restart()
        } else {
            PopoutCoordinator.releaseHud("audio")
            autoHide.stop()
        }
    }

    // Expanded, the island is a panel like Wi-Fi's: it claims the popout slot
    // so an open Wi-Fi, Bluetooth or menu panel closes, and it stays until it
    // is dismissed instead of timing out. Expanding starts the cursor on the
    // default output, which is in front; collapsing puts it back in front.
    onIsExpandedChanged: {
        if (root.isExpanded) {
            root.selectedIndex = 0
            root.pinnedScreen = islandVariants.activeScreen
            PopoutCoordinator.claim("audio")
            autoHide.stop()
        } else {
            // Closing collapses the island before it slides off, so it stays
            // on its screen until it is gone; slideAnim unpins it then.
            if (!root.hideBar) root.pinnedScreen = null
            PopoutCoordinator.release("audio")
            root.devices = root.ordered(root.devices)
        }
    }

    onDevicesChanged: {
        if (root.selectedIndex >= root.devices.length)
            root.selectedIndex = Math.max(0, root.devices.length - 1)
    }

    function handleKey(event) {
        var device = root.devices[root.selectedIndex]
        switch (event.key) {
            case Qt.Key_Left:
                root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                break
            case Qt.Key_Right:
                root.selectedIndex = Math.min(root.devices.length - 1, root.selectedIndex + 1)
                break
            case Qt.Key_Up:
                root.nudgeDevice(device, 10)
                break
            case Qt.Key_Down:
                root.nudgeDevice(device, -10)
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.makeDefault(device)
                root.collapse()
                break
            case Qt.Key_Escape:
                root.hideBar = true
                break
            default:
                return
        }
        event.accepted = true
    }

    Connections {
        target: PopoutCoordinator
        function onActiveHudChanged() {
            if (PopoutCoordinator.activeHud !== "" && PopoutCoordinator.activeHud !== "audio") {
                root.hideBar = true
            }
        }
        function onActiveChanged() {
            if (root.isExpanded && PopoutCoordinator.active !== "" && PopoutCoordinator.active !== "audio") {
                root.hideBar = true
            }
        }
    }

    Timer {
        id: autoHide
        interval: Theme.hideDelay
        // Never while expanded: that view stays until it is dismissed. A
        // click restarts the timer while the pointer is still on the island;
        // leaving restarts it again.
        onTriggered: if (!root.hovered && !root.isExpanded) root.hideBar = true
    }

    // After a change the helper has not necessarily talked to pactl yet, so
    // re-probe once things have settled rather than only on the poll tick.
    Timer {
        id: settle
        interval: 180
        onTriggered: root.refresh()
    }

    Timer {
        interval: 900
        repeat: true
        running: !root.hideBar && root.available
        onTriggered: root.refresh()
    }

    // One output's meter: four bars around its level, its kind on the bottom
    // bar. The same column the collapsed island has always shown.
    readonly property var placeholderDevice: ({
        index: -1, name: "", isDefault: true, volume: 0, muted: false,
        kind: "speaker", target: "", description: ""
    })

    component DeviceMeter: Item {
        id: meter
        required property int index
        readonly property var device: root.devices[index] || root.placeholderDevice

        width: root.columnWidth

        // Keyboard cursor: the shared selection plate (Theme.selected*),
        // behind the bars and reaching into the gap around them. Its corners
        // follow the end bars' as drawn -- Qt clamps a corner to half the
        // bar's shorter side -- plus that reach, so the curves stay
        // concentric.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -root.ringPad
            radius: Math.min(root.barRadius, topBar.width / 2, topBar.height / 2) + root.ringPad
            color: Theme.selectedFill
            border.width: Theme.selectedBorderWidth
            border.color: Theme.selectedBorder
            opacity: root.isExpanded && root.selectedIndex === meter.index ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: {
                root.selectedIndex = meter.index
                if (meter.device.isDefault) {
                    if (root.isExpanded) root.collapse()
                    else root.expand()
                } else {
                    root.makeDefault(meter.device)
                }
            }
            onWheel: function (wheel) {
                root.nudgeDevice(meter.device, wheel.angleDelta.y > 0 ? 10 : -10)
                wheel.accepted = true
            }
        }

        FlexboxLayout {
            anchors.fill: parent
            direction: FlexboxLayout.Column
            alignItems: FlexboxLayout.AlignCenter
            gap: root.segmentGap
            Behavior on gap { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            // Bar 4 (top)
            Rectangle {
                id: topBar
                topLeftRadius: root.barRadius
                topRightRadius: root.barRadius
                bottomLeftRadius: 4
                bottomRightRadius: 4
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.barColor(meter.device, 4)
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            // Bar 3
            Rectangle {
                radius: 4
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.barColor(meter.device, 3)
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Text {
                readonly property bool boosted: meter.device.volume > 1.0
                text: String(Math.round(Math.min(1, meter.device.volume) * 100)) + (boosted ? "+" : "")
                color: meter.device.muted ? Theme.red : root.accentFor(meter.device)
                font.family: Theme.brandFont
                font.pixelSize: boosted ? Theme.titleSize - 3 : Theme.titleSize
                font.weight: Theme.titleWeight
                font.capitalization: Font.AllUppercase
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            // Bar 2
            Rectangle {
                radius: 4
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.barColor(meter.device, 2)
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            // Bar 1 (bottom): the output's kind, and its mute switch.
            Rectangle {
                topLeftRadius: 4
                topRightRadius: 4
                bottomLeftRadius: root.barRadius
                bottomRightRadius: root.barRadius
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.barColor(meter.device, 1)
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: root.glyphFor(meter.device)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: root.stepsFor(meter.device) >= 1
                        ? Theme.bgc
                        : (meter.device.muted ? Theme.red : root.accentFor(meter.device))
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: root.toggleMuteDevice(meter.device)
                    onWheel: function (wheel) {
                        root.nudgeDevice(meter.device, wheel.angleDelta.y > 0 ? 10 : -10)
                        wheel.accepted = true
                    }
                }
            }
        }
    }

    // Other monitors get a click-to-dismiss overlay while the island is
    // expanded, as Wi-Fi's twin windows do.
    Variants {
        model: root.isExpanded && !root.hideBar && root.pinnedScreen
            ? Quickshell.screens.filter(function (s) { return s !== root.pinnedScreen })
            : []

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "audio-panel-twin-dismiss"
            WlrLayershell.layer: Theme.islandLayer
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.hideBar = true
            }
        }
    }

    BarVariants {
        id: islandVariants
        // Pinned while expanded; otherwise the focused monitor, as before.
        model: root.pinnedScreen
            ? [root.pinnedScreen]
            : (islandVariants.activeScreen ? [islandVariants.activeScreen] : [])

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: false

            // The whole screen, like Wi-Fi: collapsed, the mask keeps all of it
            // but the pill click-through; expanded, it takes every click so one
            // anywhere off the island dismisses it.
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            WlrLayershell.namespace: "audio-panel-main"
            WlrLayershell.layer: Theme.islandLayer
            // Exclusive for as long as the island is expanded; collapsing or
            // closing returns the keyboard.
            WlrLayershell.keyboardFocus: root.isExpanded && !root.hideBar
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            color: "transparent"

            mask: Region {
                item: root.isExpanded ? null : (!root.hideBar ? pillContainer : null)
                width: root.isExpanded ? panelWindow.width : 0
                height: root.isExpanded ? panelWindow.height : 0
            }

            // Behind the island: a click anywhere else closes it.
            MouseArea {
                anchors.fill: parent
                enabled: root.isExpanded
                acceptedButtons: Qt.AllButtons
                onPressed: root.hideBar = true
            }

            Item {
                id: keyScope
                focus: true
                Keys.onPressed: function (event) {
                    if (root.isExpanded) root.handleKey(event)
                }

                Connections {
                    target: root
                    function onIsExpandedChanged() {
                        if (root.isExpanded) Qt.callLater(function () { keyScope.forceActiveFocus() })
                    }
                }
            }

            Item {
                id: pillContainer
                width: root.pillWidth(root.isExpanded ? root.devices.length : 1)
                // Collapsed, the height the other side panels share (see
                // Theme.sidePanelHeight); expanded, taller. Centred on the left
                // edge either way, so it grows up and down together.
                height: root.panelHeight - 2 * Theme.scoopCapOverhang
                y: Math.round((parent.height - height) / 2)
                // Set once, not bound: the width animates as the island
                // expands, and a binding on it would throw the pill back
                // off-screen. slideAnim owns x from here on.
                Component.onCompleted: x = -(width + 10)

                Behavior on width {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on height {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }

                NumberAnimation {
                    id: slideAnim
                    target: pillContainer
                    property: "x"
                    duration: 250
                    easing.type: Easing.OutCubic
                    onFinished: {
                        if (root.hideBar) {
                            panelWindow.visible = false
                            root.pinnedScreen = null
                        }
                    }
                }

                // Closing while expanded shrinks the island back to one column
                // first and slides it off once the 250ms resize has settled,
                // the way the time island closes.
                Timer {
                    id: slideOutDelay
                    interval: 250
                    onTriggered: pillContainer.slideOut()
                }

                function slideOut() {
                    slideAnim.stop()
                    slideAnim.from = pillContainer.x
                    slideAnim.to = -(pillContainer.width + 10)
                    slideAnim.start()
                }

                Connections {
                    target: root
                    function onHideBarChanged() {
                        if (!root.hideBar) {
                            panelWindow.visible = true
                            slideOutDelay.stop()
                            slideAnim.stop()
                            slideAnim.from = pillContainer.x
                            slideAnim.to = 0
                            slideAnim.start()
                        } else if (root.isExpanded) {
                            slideAnim.stop()
                            root.isExpanded = false
                            slideOutDelay.restart()
                        } else {
                            pillContainer.slideOut()
                        }
                    }
                }

                // Hover anywhere on the island holds it open.
                HoverHandler {
                    onHoveredChanged: {
                        root.hovered = hovered
                        if (!hovered) autoHide.restart()
                    }
                }

                // Unified single-vector background contour (position: centerLeft)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "centerLeft"
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                    borderWidth: Theme.borderWidth
                }

                // Wheel anywhere off the meters steps the default output. It
                // also takes clicks on the pill's padding, so they never reach
                // the dismiss area behind it.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onWheel: function (wheel) {
                        root.nudge(wheel.angleDelta.y > 0 ? 10 : -10)
                        autoHide.restart()
                        wheel.accepted = true
                    }
                }

                // Columns past the first are clipped while collapsed and
                // uncovered as the island widens.
                Item {
                    z: 1
                    anchors.fill: parent
                    // Pulled out by ringPad so the focus ring is not clipped;
                    // the Row puts the columns back where they were.
                    anchors.topMargin: Theme.rounding + Theme.spacing * 2 - root.ringPad
                    anchors.bottomMargin: Theme.rounding + Theme.spacing * 2 - root.ringPad
                    anchors.leftMargin: Theme.borderWidth - root.ringPad
                    anchors.rightMargin: Theme.spacing + Theme.borderWidth - root.ringPad
                    clip: true

                    Row {
                        x: root.ringPad
                        y: root.ringPad
                        height: parent.height - 2 * root.ringPad
                        spacing: root.columnGap

                        // A count, not the array: the poll replaces the
                        // array every tick, and an array model would rebuild
                        // every column and drop their colour animations.
                        Repeater {
                            model: Math.max(1, root.devices.length)

                            DeviceMeter {
                                height: parent.height
                            }
                        }
                    }
                }
            }
        }
    }
}

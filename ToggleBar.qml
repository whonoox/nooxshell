import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    // Corner island: hidden by default, pops up on trigger, auto-hides like other HUD bars
    property bool hideBar: true
    property string lastTriggered: "none" // "notif" | "mic" | "none"
    property bool _initialized: false

    function reveal(triggerSource) {
        root.lastTriggered = triggerSource || "none"
        root.hideBar = false
        autoHideTimer.restart()
    }

    Timer {
        id: autoHideTimer
        interval: Theme.toggleHideDelay
        onTriggered: {
            root.hideBar = true
            root.lastTriggered = "none"
        }
    }

    // Super+Ctrl+O: shows the island to read every toggle's state without
    // changing any, hiding again like a reveal does; pressed while it is
    // showing, it hides it at once.
    function toggleShown() {
        if (root.hideBar) {
            root.reveal("none")
        } else {
            autoHideTimer.stop()
            root.hideBar = true
            root.lastTriggered = "none"
        }
        return root.hideBar ? "closed" : "open"
    }

    function toggleNotif() {
        ToggleState.toggleDnd()
        root.reveal("notif")
    }

    function toggleMic() {
        ToggleState.toggleMic()
        root.reveal("mic")
    }

    function toggleCursor() {
        ToggleState.toggleCursorXRay()
        root.reveal("cursor")
    }

    function toggleAwake() {
        ToggleState.toggleStayAwake()
        root.reveal("awake")
    }

    function toggleFnLock() {
        ToggleState.toggleFnLock()
        root.reveal("fnlock")
    }

    function toggleAirplane() {
        ToggleState.toggleAirplane()
        root.reveal("airplane")
    }

    function toggleNightLight() {
        ToggleState.toggleNightLight()
        root.reveal("nightlight")
    }

    function toggleKeySounds() {
        ToggleState.toggleKeySounds()
        root.reveal("keys")
    }

    // Super+Alt+. switches to the next input language (English, Sera, ...).
    function cycleInput() {
        if (!ToggleState.cycleInput(false)) return "not running"
        root.reveal("input")
        return "ok"
    }

    // Fcitx keeps a language per window, so the reading also changes as
    // focus moves between windows typing in different ones. Only a change
    // within one window is a switch (a trigger key pressed in it, or a
    // click on the island) and pops the island up.
    property var _inputWindow: null
    property string _inputPrevious: ""

    Connections {
        target: ToggleState
        function onMicMutedChanged() {
            if (root._initialized) {
                root.reveal("mic")
            }
        }
        function onDndChanged() {
            if (root._initialized) {
                root.reveal("notif")
            }
        }
        function onCursorXRayChanged() {
            if (root._initialized) {
                root.reveal("cursor")
            }
        }
        function onStayAwakeChanged() {
            if (root._initialized) {
                root.reveal("awake")
            }
        }
        function onFnLockChanged() {
            if (root._initialized && ToggleState.fnLockAvailable) {
                root.reveal("fnlock")
            }
        }
        function onCapsLockChanged() {
            if (root._initialized) {
                root.reveal("capslock")
            }
        }
        function onAirplaneModeChanged() {
            if (root._initialized) {
                root.reveal("airplane")
            }
        }
        function onNightLightChanged() {
            if (root._initialized) {
                root.reveal("nightlight")
            }
        }
        function onKeySoundsChanged() {
            if (root._initialized) {
                root.reveal("keys")
            }
        }
        function onInputMethodChanged() {
            var window = Hyprland.activeToplevel
            var switched = root._inputPrevious !== "" && ToggleState.inputMethod !== ""
                && window === root._inputWindow
            root._inputWindow = window
            root._inputPrevious = ToggleState.inputMethod
            if (root._initialized && switched && ToggleState.inputAvailable) {
                root.reveal("input")
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            root._initialized = true
        })
    }

    // ------------------------------------------------------------------
    // Global Shortcuts
    // ------------------------------------------------------------------
    GlobalShortcut {
        name: "toggleBarToggle"
        description: "Show or hide the toggles island"
        appid: "quickshell"
        onPressed: root.toggleShown()
    }

    GlobalShortcut {
        name: "notifToggle"
        description: "Toggle notifications Do Not Disturb"
        appid: "quickshell"
        onPressed: root.toggleNotif()
    }

    GlobalShortcut {
        name: "micToggle"
        description: "Toggle microphone mute"
        appid: "quickshell"
        onPressed: root.toggleMic()
    }

    GlobalShortcut {
        name: "cursorXRayToggle"
        description: "Toggle Cursor X-Ray mode"
        appid: "quickshell"
        onPressed: root.toggleCursor()
    }

    GlobalShortcut {
        name: "stayAwakeToggle"
        description: "Toggle stay awake idle inhibition"
        appid: "quickshell"
        onPressed: root.toggleAwake()
    }

    GlobalShortcut {
        name: "airplaneToggle"
        description: "Toggle airplane mode"
        appid: "quickshell"
        onPressed: root.toggleAirplane()
    }

    GlobalShortcut {
        name: "nightLightToggle"
        description: "Toggle night light blue light filter"
        appid: "quickshell"
        onPressed: root.toggleNightLight()
    }

    GlobalShortcut {
        name: "keySoundsToggle"
        description: "Toggle key sounds"
        appid: "quickshell"
        onPressed: root.toggleKeySounds()
    }

    GlobalShortcut {
        name: "inputCycle"
        description: "Switch to the next input language"
        appid: "quickshell"
        onPressed: root.cycleInput()
    }

    // ------------------------------------------------------------------
    // IPC Handler
    // ------------------------------------------------------------------
    IpcHandler {
        target: "toggleBar"

        function toggle(): string {
            return root.toggleShown()
        }

        function open(): string {
            root.reveal("none")
            return "open"
        }

        function close(): string {
            root.hideBar = true
            return "closed"
        }

        function toggleNotif(): string {
            root.toggleNotif()
            return ToggleState.dnd ? "dnd_on" : "dnd_off"
        }

        function toggleMic(): string {
            root.toggleMic()
            return ToggleState.micMuted ? "muted" : "live"
        }

        function toggleCursor(): string {
            root.toggleCursor()
            return ToggleState.cursorXRay ? "on" : "off"
        }

        function toggleAwake(): string {
            root.toggleAwake()
            return ToggleState.stayAwake ? "awake_on" : "awake_off"
        }

        function toggleFnLock(): string {
            root.toggleFnLock()
            return ToggleState.fnLock ? "fnlock_on" : "fnlock_off"
        }

        function toggleAirplane(): string {
            root.toggleAirplane()
            return ToggleState.airplaneMode ? "airplane_on" : "airplane_off"
        }

        function toggleNightLight(): string {
            root.toggleNightLight()
            return ToggleState.nightLight ? "nightlight_on" : "nightlight_off"
        }

        function toggleKeySounds(): string {
            root.toggleKeySounds()
            return ToggleState.keySounds ? "keys_on" : "keys_off"
        }

        function cycleInput(): string {
            return root.cycleInput()
        }

        function revealInput(): string {
            root.reveal("input")
            return "ok"
        }

        function inputStatus(): string {
            return ToggleState.inputMethod
        }

        function revealMic(): string {
            root.reveal("mic")
            return "ok"
        }

        function revealNotif(): string {
            root.reveal("notif")
            return "ok"
        }

        function revealCursor(): string {
            root.reveal("cursor")
            return "ok"
        }

        function revealAwake(): string {
            root.reveal("awake")
            return "ok"
        }

        function revealFnLock(): string {
            root.reveal("fnlock")
            return "ok"
        }

        function revealAirplane(): string {
            root.reveal("airplane")
            return "ok"
        }

        function revealNightLight(): string {
            root.reveal("nightlight")
            return "ok"
        }

        function notifStatus(): string {
            return ToggleState.dnd ? "dnd_on" : "dnd_off"
        }

        function micStatus(): string {
            return ToggleState.micMuted ? "muted" : "live"
        }

        function cursorStatus(): string {
            return ToggleState.cursorXRay ? "on" : "off"
        }

        function awakeStatus(): string {
            return ToggleState.stayAwake ? "awake_on" : "awake_off"
        }

        function capsLockStatus(): string {
            return ToggleState.capsLock ? "capslock_on" : "capslock_off"
        }

        function fnLockStatus(): string {
            return ToggleState.fnLock ? "fnlock_on" : "fnlock_off"
        }

        function airplaneStatus(): string {
            return ToggleState.airplaneMode ? "airplane_on" : "airplane_off"
        }

        function nightLightStatus(): string {
            return ToggleState.nightLight ? "nightlight_on" : "nightlight_off"
        }

        function keySoundsStatus(): string {
            return ToggleState.keySounds ? "keys_on" : "keys_off"
        }

        function status(): string {
            return JSON.stringify({
                notifDnd: ToggleState.dnd,
                micMuted: ToggleState.micMuted,
                cursorXRay: ToggleState.cursorXRay,
                stayAwake: ToggleState.stayAwake,
                fnLock: ToggleState.fnLock,
                fnLockAvailable: ToggleState.fnLockAvailable,
                fnLockSource: ToggleState.fnLockSource,
                capsLock: ToggleState.capsLock,
                capsLockAvailable: ToggleState.capsLockAvailable,
                airplaneMode: ToggleState.airplaneMode,
                nightLight: ToggleState.nightLight,
                keySounds: ToggleState.keySounds,
                inputMethod: ToggleState.inputMethod,
                inputMethods: ToggleState.inputMethods,
                visible: !root.hideBar,
                lastTriggered: root.lastTriggered
            })
        }
    }

    // ------------------------------------------------------------------
    // Panel Window (Bottom-Left Corner)
    // ------------------------------------------------------------------
    BarVariants {
        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            visible: false

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "toggle-panel-main"
            WlrLayershell.layer: Theme.islandLayer
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Only the two arms take input; the space inside the L lets
            // clicks through to the windows behind.
            mask: Region {
                item: verticalArmArea
                Region { item: horizontalArmArea }
            }

            Item {
                id: verticalArmArea
                anchors.left: cardContainer.left
                anchors.top: cardContainer.top
                anchors.bottom: cardContainer.bottom
                width: cardContainer.band + Theme.borderWidth
            }

            Item {
                id: horizontalArmArea
                anchors.left: cardContainer.left
                anchors.right: cardContainer.right
                anchors.bottom: cardContainer.bottom
                height: cardContainer.band + Theme.borderWidth
            }

            // Bottom-Left Anchored Card Container
            Item {
                id: cardContainer
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                // The L slides in and out diagonally, out past the screen's
                // corner: 0 is in place, 1 all the way out. Like the other
                // islands it goes just past its own depth and 10 more; here
                // that is an arm's thickness, since moving the island's full
                // size would leave it off screen for most of the slide.
                property real outward: 1
                readonly property real travel: band + Theme.borderWidth + 10
                anchors.leftMargin: -outward * travel
                anchors.bottomMargin: -outward * travel

                // How thick each arm is, the padding around a toggle across
                // it, the space between toggles, and the corner slot both
                // groups start past. edge is the flare and border beyond
                // an arm's end.
                readonly property real band: 44
                readonly property real pad: (band - 24) / 2
                readonly property real gap: Theme.spacing * 1.5
                readonly property real cornerSlot: pad + 24 + gap
                readonly property real edge: Theme.rounding + Theme.borderWidth

                width: cornerSlot + inputGroup.implicitWidth + Theme.spacing * 2 + edge
                height: edge + Theme.spacing * 2 + systemGroup.implicitHeight + cornerSlot

                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                NumberAnimation {
                    id: slideAnim
                    target: cardContainer
                    property: "outward"
                    duration: 250
                    easing.type: Easing.OutCubic
                    onFinished: {
                        if (root.hideBar) {
                            panelWindow.visible = false
                        }
                    }
                }

                Connections {
                    target: root
                    function onHideBarChanged() {
                        if (!root.hideBar) {
                            panelWindow.visible = true
                            slideAnim.stop()
                            slideAnim.from = cardContainer.outward
                            slideAnim.to = 0
                            slideAnim.start()
                        } else {
                            slideAnim.stop()
                            slideAnim.from = cardContainer.outward
                            slideAnim.to = 1
                            slideAnim.start()
                        }
                    }
                }

                Component.onCompleted: {
                    if (!root.hideBar) {
                        panelWindow.visible = true
                        cardContainer.outward = 0
                    }
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            autoHideTimer.stop()
                        } else {
                            autoHideTimer.restart()
                        }
                    }
                }

                // An L in the corner: the system toggles stand up the left
                // screen edge, the input ones run along the bottom, and the
                // two arms meet in the corner. Both arms are band thick and
                // laid out on one grid of slots, so the empty corner slot
                // keeps the column and the row in step.
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "bottomLeftCorner"
                    armRight: cardContainer.band
                    armTop: cardContainer.height - cardContainer.band
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                    borderWidth: Theme.borderWidth
                }

                // System: notifications, mic, idle, radios, screen.
                Column {
                    id: systemGroup
                    x: cardContainer.pad
                    y: cardContainer.edge + Theme.spacing * 2
                    spacing: cardContainer.gap


                    // 1. Notification DND Toggle (No button background, no border)
                    Item {
                        id: notifButton
                        width: 24
                        height: 24

                        readonly property bool isDnd: ToggleState.dnd
                        readonly property bool isTriggered: root.lastTriggered === "notif"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: notifMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: notifRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: notifButton.isDnd ? "decorations/bell-slash.svg" : "decorations/bell.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: notifRawIcon
                            source: notifRawIcon
                            colorization: 1.0
                            colorizationColor: !notifButton.isDnd
                                ? Theme.brand
                                : (notifButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: notifMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleNotif()
                        }
                    }

                    // 2. Microphone Mute Toggle (No button background, no border)
                    Item {
                        id: micButton
                        width: 24
                        height: 24

                        readonly property bool isMuted: ToggleState.micMuted
                        readonly property bool isTriggered: root.lastTriggered === "mic"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: micMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: micRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: micButton.isMuted ? "decorations/microphone-slash.svg" : "decorations/microphone.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: micRawIcon
                            source: micRawIcon
                            colorization: 1.0
                            colorizationColor: !micButton.isMuted
                                ? Theme.brand
                                : (micButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: micMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleMic()
                        }
                    }

                    // 3. Stay Awake (Idle Inhibition) Toggle (No button background, no border)
                    Item {
                        id: awakeButton
                        width: 24
                        height: 24

                        readonly property bool isAwake: ToggleState.stayAwake
                        readonly property bool isTriggered: root.lastTriggered === "awake"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: awakeMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: awakeRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: "decorations/coffee.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: awakeRawIcon
                            source: awakeRawIcon
                            colorization: 1.0
                            colorizationColor: awakeButton.isAwake
                                ? Theme.brand
                                : (awakeButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: awakeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleAwake()
                        }
                    }

                    // 4. Airplane Mode Toggle (No button background, no border)
                    Item {
                        id: airplaneButton
                        width: 24
                        height: 24

                        readonly property bool isAirplane: ToggleState.airplaneMode
                        readonly property bool isTriggered: root.lastTriggered === "airplane"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: airplaneMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: airplaneRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: "decorations/airplane.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: airplaneRawIcon
                            source: airplaneRawIcon
                            colorization: 1.0
                            colorizationColor: airplaneButton.isAirplane
                                ? Theme.brand
                                : (airplaneButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: airplaneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleAirplane()
                        }
                    }

                    // 5. Night Light Toggle (No button background, no border)
                    Item {
                        id: nightLightButton
                        width: 24
                        height: 24

                        readonly property bool isNightLight: ToggleState.nightLight
                        readonly property bool isTriggered: root.lastTriggered === "nightlight"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: nightLightMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: nightLightRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: "decorations/moon.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: nightLightRawIcon
                            source: nightLightRawIcon
                            colorization: 1.0
                            colorizationColor: nightLightButton.isNightLight
                                ? Theme.brand
                                : (nightLightButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: nightLightMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleNightLight()
                        }
                    }
                }

                // Input: Fn lock, Caps Lock, input language, and the two
                // touches on input, cursor X-Ray and key sounds.
                Row {
                    id: inputGroup
                    x: cardContainer.cornerSlot
                    y: cardContainer.height - cardContainer.band + cardContainer.pad
                    spacing: cardContainer.gap


                    // 6. Fn Lock Toggle (No button background, no border)
                    Item {
                        id: fnLockButton
                        width: 24
                        height: 24
                        visible: ToggleState.fnLockAvailable

                        readonly property bool isFnLock: ToggleState.fnLock
                        readonly property bool isTriggered: root.lastTriggered === "fnlock"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: fnLockMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: fnLockRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: "decorations/function.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: fnLockRawIcon
                            source: fnLockRawIcon
                            colorization: 1.0
                            colorizationColor: fnLockButton.isFnLock
                                ? Theme.brand
                                : (fnLockButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: fnLockMouse
                            anchors.fill: parent
                            // A Dell's Fn lock can only be shown; Fn+Esc sets it.
                            enabled: ToggleState.fnLockSettable
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleFnLock()
                        }
                    }

                    // 7. Caps Lock indicator. It only shows the lock, which
                    // the shell cannot set (see ToggleState), and pops the
                    // island up when it changes, for keys without a light.
                    Item {
                        id: capsLockButton
                        width: 24
                        height: 24
                        visible: ToggleState.capsLockAvailable

                        readonly property bool isCapsLock: ToggleState.capsLock
                        readonly property bool isTriggered: root.lastTriggered === "capslock"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered

                        scale: isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9)
                        opacity: isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85)

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: capsLockRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: "decorations/capslock.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: capsLockRawIcon
                            source: capsLockRawIcon
                            colorization: 1.0
                            colorizationColor: capsLockButton.isCapsLock ? Theme.brand : Theme.darkForeground
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }
                    }

                    // 8. Input language: the language being typed, as two or
                    // three letters, always lit: it is a reading, not an on
                    // and off. A click switches to the next one. Shown
                    // only with more than one language set up in Fcitx.
                    Item {
                        id: inputButton
                        width: Math.max(24, inputText.implicitWidth + 6)
                        height: 24
                        visible: ToggleState.inputAvailable

                        readonly property bool isTriggered: root.lastTriggered === "input"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: inputMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Text {
                            id: inputText
                            anchors.centerIn: parent
                            text: ToggleState.inputShortLabel
                            font.family: Theme.displayFont
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.brand
                        }

                        MouseArea {
                            id: inputMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycleInput()
                        }
                    }

                    // 9. Cursor X-Ray Toggle (No button background, no border)
                    Item {
                        id: cursorButton
                        width: 24
                        height: 24

                        readonly property bool isXRay: ToggleState.cursorXRay
                        readonly property bool isTriggered: root.lastTriggered === "cursor"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: cursorMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: cursorRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: "decorations/cursor.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: cursorRawIcon
                            source: cursorRawIcon
                            colorization: 1.0
                            colorizationColor: cursorButton.isXRay
                                ? Theme.brand
                                : (cursorButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: cursorMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleCursor()
                        }
                    }

                    // 10. Key Sounds Toggle (No button background, no border)
                    Item {
                        id: keysButton
                        width: 24
                        height: 24

                        readonly property bool isKeys: ToggleState.keySounds
                        readonly property bool isTriggered: root.lastTriggered === "keys"
                        readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                        readonly property bool isHovered: keysMouse.containsMouse

                        scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                        opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Image {
                            id: keysRawIcon
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: "decorations/keyboard.svg"
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: keysRawIcon
                            source: keysRawIcon
                            colorization: 1.0
                            colorizationColor: keysButton.isKeys
                                ? Theme.brand
                                : (keysButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                            Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: keysMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleKeySounds()
                        }
                    }
                }
            }
        }
    }
}

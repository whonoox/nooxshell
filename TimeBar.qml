import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    property bool hudVisible: false
    property bool isExpanded: false
    readonly property bool hideAll: !hudVisible && !isExpanded
    property real lastToggleTime: 0
    property int lastHourlyNotifiedHour: (new Date()).getHours()

    // ------------------------------------------------------------------
    // Reminders (see Reminders.qml)
    // ------------------------------------------------------------------
    // A reminder going off pops the island with the alarm ringing beside
    // the time and the reminder's text beneath it, until clicked or for
    // reminderRingTime. That is the only place a reminder's text shows.
    // Setting or clearing one only pops the island as the hourly glance
    // does, the alarm shaking once as a new one is added. Listing them
    // (`omarchy reminder show`) opens the expanded view, which gives each
    // pending reminder's time and how long is left. While any is pending
    // the alarm sits beside the time.
    readonly property int reminderRingTime: 20000
    property string noticeTitle: ""
    property string noticeBody: ""
    property bool ringing: false
    // Bumped to give the alarm a single shake, for a notice.
    property int nudgeSerial: 0
    property int lastReminderCount: 0
    readonly property bool showNotice: noticeTitle !== "" || noticeBody !== ""
    readonly property bool showAlarmIcon: showNotice || inputOpen || Reminders.count > 0

    // ------------------------------------------------------------------
    // Reminder input (Super+Ctrl+R), beneath the time
    // ------------------------------------------------------------------
    // The same two steps as Omarchy's own reminder window: how many
    // minutes, then an optional message, each confirmed with Enter. An
    // empty first step, Escape or a click outside puts it away. It then
    // runs omarchy-reminder exactly as that window does, and the
    // confirmation shows here like any other reminder notice.
    property bool inputOpen: false
    property string inputStep: "minutes"
    property string inputMinutes: ""
    property string inputError: ""
    // Bumped to clear the field: on opening and between the steps.
    property int inputSerial: 0
    readonly property real inputWidth: 260

    function openReminderInput() {
        root.clearNotice()
        root.isExpanded = false
        root.hudVisible = true
        root.inputStep = "minutes"
        root.inputMinutes = ""
        root.inputError = ""
        root.inputOpen = true
        root.inputSerial++
        root.nudgeSerial++
    }

    function closeReminderInput() {
        root.inputOpen = false
        root.inputError = ""
        if (!root.isExpanded) root.hudVisible = false
    }

    function submitReminderInput(value) {
        var text = String(value || "").trim()
        if (root.inputStep === "minutes") {
            if (!text) {
                root.closeReminderInput()
                return
            }
            if (!/^[0-9]+$/.test(text) || Number(text) <= 0) {
                root.inputError = "Enter the number of minutes"
                return
            }
            root.inputMinutes = String(Number(text))
            root.inputError = ""
            root.inputStep = "message"
            root.inputSerial++
            return
        }
        var args = ["omarchy-reminder", root.inputMinutes]
        if (text) args.push(text)
        Quickshell.execDetached(args)
        // The island stays up: the confirmation lands on it in a moment.
        root.inputOpen = false
        autoHideTimer.restart()
    }

    Connections {
        target: Reminders
        function onInputRequested() { root.openReminderInput() }
    }

    GlobalShortcut {
        name: "reminderSetToggle"
        description: "Set a reminder on the time island"
        appid: "quickshell"
        onPressed: root.inputOpen ? root.closeReminderInput() : root.openReminderInput()
    }

    function showFiredReminder(message) {
        root.noticeTitle = Reminders.firedTitle
        root.noticeBody = String(message || "")
        root.ringing = true
        if (!root.isExpanded) root.hudVisible = true
        noticeTimer.interval = root.reminderRingTime
        noticeTimer.restart()
    }

    function clearNotice() {
        noticeTimer.stop()
        root.ringing = false
        root.noticeTitle = ""
        root.noticeBody = ""
    }

    Connections {
        target: Reminders
        function onFired(message) { root.showFiredReminder(message) }
        function onNotice(listing) {
            if (root.inputOpen) return
            if (listing) {
                root.isExpanded = true
                root.hudVisible = false
            } else if (!root.isExpanded) {
                root.hudVisible = true
            }
            autoHideTimer.restart()
        }
        // A reminder added: one shake as the alarm appears beside the time.
        function onCountChanged() {
            if (Reminders.count > root.lastReminderCount) root.nudgeSerial++
            root.lastReminderCount = Reminders.count
        }
    }

    Timer {
        id: noticeTimer
        onTriggered: {
            root.clearNotice()
            if (!root.isExpanded) root.hudVisible = false
        }
    }

    onIsExpandedChanged: if (isExpanded) Reminders.refresh()

    function msUntilNextHour() {
        var now = new Date()
        var nextHour = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0)
        return Math.max(1000, nextHour.getTime() - now.getTime())
    }

    function triggerHourlyGlance(force) {
        var now = new Date()
        var hr = now.getHours()
        if (!force && root.lastHourlyNotifiedHour === hr) return
        root.lastHourlyNotifiedHour = hr

        // Pop out if forced or at the turn of the hour (within 2 minutes of :00)
        if (force || now.getMinutes() <= 2) {
            if (!root.isExpanded) {
                root.hudVisible = true
            }
            autoHideTimer.restart()
        }
    }

    // Hourly Popout Timer: dynamically schedules to the exact millisecond of the next hour
    Timer {
        id: hourlyTimer
        interval: root.msUntilNextHour()
        repeat: true
        running: true
        onTriggered: {
            root.triggerHourlyGlance()
            interval = root.msUntilNextHour()
        }
    }

    SystemClock {
        id: clock
        precision: root.hideAll ? SystemClock.Minutes : SystemClock.Seconds
        onDateChanged: {
            var d = clock.date
            if (d && d.getMinutes() === 0) {
                root.triggerHourlyGlance()
            }
        }
    }

    readonly property string time: Qt.formatDateTime(clock.date, "hh:mm:ss AP")
    readonly property string day: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
    readonly property string date: Qt.formatDateTime(clock.date, "MMM dd, yyyy")

    onHideAllChanged: {
        if (hideAll) {
            isExpanded = false
            hudVisible = false
            clearNotice()
            inputOpen = false
        }
    }

    Component.onCompleted: {
        root.hudVisible = true
    }

    // Auto-hide Timer: Active for both views, auto-collapsing and moving off-screen
    Timer {
        id: autoHideTimer
        interval: Theme.hideDelay
        // A reminder on show keeps the island up on its own timer.
        running: !root.hideAll && !root.showNotice && !root.inputOpen
        onTriggered: {
            root.isExpanded = false
            root.hudVisible = false
        }
    }

    // IPC Handler
    IpcHandler {
        target: "timeBar"
        function toggle() {
            if (root.hideAll) {
                root.hudVisible = true
                root.isExpanded = false
                autoHideTimer.restart()
            } else if (root.hudVisible && !root.isExpanded) {
                root.isExpanded = true
                root.hudVisible = false
                autoHideTimer.restart()
            } else {
                root.isExpanded = false
                root.hudVisible = false
                autoHideTimer.stop()
            }
        }
        function open() {
            root.hudVisible = true
            root.isExpanded = false
            autoHideTimer.restart()
        }
        function expand() {
            root.isExpanded = true
            root.hudVisible = false
            autoHideTimer.restart()
        }
        function close() {
            root.isExpanded = false
            root.hudVisible = false
            autoHideTimer.stop()
        }
        function hourlyGlance() {
            root.triggerHourlyGlance(true)
        }
        function remind() {
            root.openReminderInput()
        }
    }

    // Global Shortcut Handler
    GlobalShortcut {
        name: "timeToggle"
        description: "Show Time HUD on first press, expand Date on second press"
        appid: "quickshell"
        onPressed: {
            // Only a duplicate event from one keypress is dropped. The old
            // 250ms guard also swallowed the second press of a quick double
            // tap, so show-then-expand only worked when pressed slowly.
            var now = Date.now()
            if (now - root.lastToggleTime < 40) return
            root.lastToggleTime = now

            if (root.hideAll) {
                // 1st Press: Show time glance HUD
                root.hudVisible = true
                root.isExpanded = false
                autoHideTimer.restart()
            } else if (root.hudVisible && !root.isExpanded) {
                // 2nd Press: Expand into date view and reset timer
                root.isExpanded = true
                root.hudVisible = false
                autoHideTimer.restart()
            } else {
                // 3rd Press or while expanded: Collapse and close
                root.isExpanded = false
                root.hudVisible = false
            }
        }
    }

    // Main Top-Center Island Window
    BarVariants {
        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: !root.hideAll || (cardContainer.y > -(cardContainer.height + 10))

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "time-panel-main"
            WlrLayershell.layer: Theme.islandLayer
            // Typing goes to the reminder input while it is open, and only then.
            WlrLayershell.keyboardFocus: root.inputOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Strict mask: only the visible island captures input; 100% click-through
            // elsewhere. While the reminder input is open the whole screen does, so a
            // click outside the island can put it away.
            mask: Region {
                item: root.inputOpen ? null : (!root.hideAll ? cardContainer : null)
                width: root.inputOpen ? panelWindow.width : 0
                height: root.inputOpen ? panelWindow.height : 0
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.inputOpen
                onClicked: root.closeReminderInput()
            }

            // ================================================================
            // Centered Top-Anchored Card Container
            // Smoothly expands width and height, slides vertically off-screen
            // ================================================================
            Item {
                id: cardContainer
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.hideAll ? -(height + 20) : 0

                // The content is padded by Theme.unit and keeps its size; the
                // flares on either side take rounding + borderWidth each, so the card
                // widens and narrows with the rounding instead.
                // The time, with room for the alarm beside it while it shows.
                readonly property real headerWidth: timeText.implicitWidth
                    + (root.showAlarmIcon ? Theme.titleSize + Theme.spacing : 0)
                // A long reminder wraps rather than stretching the island.
                readonly property real noticeMaxWidth: 420
                readonly property real noticeWidth: Math.min(noticeMaxWidth,
                    Math.max(noticeTitleText.implicitWidth, noticeBodyText.implicitWidth))

                width: Math.max(headerWidth + Theme.unit,
                        root.showNotice ? noticeWidth + Theme.unit * 2 : 0,
                        root.inputOpen ? root.inputWidth + Theme.unit * 2 : 0,
                        root.isExpanded
                            ? Math.max(headerWidth, dayText.implicitWidth, dateText.implicitWidth, upcomingColumn.implicitWidth) + Theme.unit * 2
                            : 0)
                    + 2 * (Theme.rounding + Theme.borderWidth)

                readonly property real noticeHeight: root.showNotice ? noticeColumn.implicitHeight + Theme.spacing * 2 : 0
                readonly property real inputHeight: root.inputOpen ? inputColumn.implicitHeight + Theme.spacing * 2 : 0

                height: summaryHeader.height
                    + noticeHeight
                    + inputHeight
                    + (root.isExpanded ? detailsColumn.implicitHeight + Theme.spacing * 2 : 0)
                    + Theme.borderWidth

                Behavior on width {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on height {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                // Unified single-vector background contour (position: topCenter)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "topCenter"
                    color: Theme.bgc
                    radius: Theme.rounding
                }

                // Main Content Container
                Item {
                    id: background
                    anchors.fill: parent
                    anchors.leftMargin: Theme.rounding + Theme.borderWidth
                    anchors.rightMargin: Theme.rounding + Theme.borderWidth
                    anchors.bottomMargin: Theme.borderWidth
                    clip: true

                    // Click to cycle between collapsed and expanded views with timer reset
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.inputOpen) return
                            // A reminder on show is put away by a click.
                            if (root.showNotice) {
                                root.clearNotice()
                                if (!root.isExpanded) root.hudVisible = false
                                return
                            }
                            root.isExpanded = !root.isExpanded
                            autoHideTimer.restart()
                            if (root.isExpanded) {
                                root.hudVisible = false
                            } else {
                                root.hudVisible = true
                            }
                        }
                    }

                    // ====================================================
                    // 1. SUMMARY (Time Header - Always Visible)
                    // ====================================================
                    Item {
                        id: summaryHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Theme.topIslandHeight - Theme.borderWidth

                        Text {
                            id: timeText
                            anchors.horizontalCenter: parent.horizontalCenter
                            // Off centre by half the alarm, so the pair is centred.
                            anchors.horizontalCenterOffset: root.showAlarmIcon ? (alarmIcon.size + Theme.spacing) / 2 : 0
                            Behavior on anchors.horizontalCenterOffset {
                                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }
                            // Centered above the whole border stroke, not just
                            // its outer half: the inner half reads as edge, not
                            // space, and centering on the full fill sat the time
                            // visibly low.
                            anchors.baseline: parent.verticalCenter
                            anchors.baselineOffset: Theme.titleCapHeight / 2 - Theme.borderWidth / 2
                            text: root.time
                            color: Theme.brand
                            font.family: Theme.brandFont
                            font.pixelSize: Theme.titleSize
                            font.weight: Theme.titleWeight
                            font.capitalization: Font.AllUppercase
                        }

                        // Phosphor's alarm, split into its body and its two
                        // bells so they can shake apart when it rings.
                        Item {
                            id: alarmIcon
                            readonly property int size: Theme.titleSize
                            width: size
                            height: size
                            anchors.right: timeText.left
                            anchors.rightMargin: Theme.spacing
                            // Level with the time's capitals; see timeText.
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -Theme.borderWidth / 2
                            opacity: root.showAlarmIcon ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            // Padded so the bells are not clipped as they swing.
                            Item {
                                id: alarmArt
                                readonly property real pad: alarmIcon.size / 3
                                anchors.centerIn: parent
                                width: alarmIcon.size + pad * 2
                                height: alarmIcon.size + pad * 2
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.brand
                                }

                                Image {
                                    x: alarmArt.pad
                                    y: alarmArt.pad
                                    width: alarmIcon.size
                                    height: alarmIcon.size
                                    sourceSize.width: alarmIcon.size * 2
                                    sourceSize.height: alarmIcon.size * 2
                                    source: "decorations/alarm-body.svg"
                                    // About the middle of the dial, not of the square.
                                    transform: Rotation {
                                        id: bodyTilt
                                        origin.x: alarmIcon.size / 2
                                        origin.y: alarmIcon.size * 136 / 256
                                    }
                                }

                                Image {
                                    x: alarmArt.pad
                                    y: alarmArt.pad
                                    width: alarmIcon.size
                                    height: alarmIcon.size
                                    sourceSize.width: alarmIcon.size * 2
                                    sourceSize.height: alarmIcon.size * 2
                                    source: "decorations/alarm-bells.svg"
                                    transform: [
                                        Rotation {
                                            id: bellTilt
                                            origin.x: alarmIcon.size / 2
                                            origin.y: alarmIcon.size * 136 / 256
                                        },
                                        Translate { id: bellHop }
                                    ]
                                }
                            }

                            // Ringing: the clock jumps, rocks on its feet and
                            // its bells rattle faster than it rocks, then a
                            // breath, and again. Each burst finishes before it
                            // stops, so the alarm always comes to rest upright.
                            SequentialAnimation {
                                running: root.ringing && panelWindow.visible
                                loops: Animation.Infinite
                                alwaysRunToEnd: true

                                ParallelAnimation {
                                    SequentialAnimation {
                                        NumberAnimation { target: alarmArt; property: "scale"; to: 1.25; duration: 110; easing.type: Easing.OutQuad }
                                        PauseAnimation { duration: 420 }
                                        NumberAnimation { target: alarmArt; property: "scale"; to: 1.0; duration: 240; easing.type: Easing.InOutQuad }
                                    }
                                    SequentialAnimation {
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: -12; duration: 60 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: 12; duration: 110 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: -10; duration: 110 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: 10; duration: 110 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: -6; duration: 100 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: 4; duration: 90 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: 0; duration: 80; easing.type: Easing.OutQuad }
                                    }
                                    SequentialAnimation {
                                        SequentialAnimation {
                                            loops: 6
                                            NumberAnimation { target: bellTilt; property: "angle"; to: 16; duration: 50 }
                                            NumberAnimation { target: bellTilt; property: "angle"; to: -16; duration: 50 }
                                        }
                                        NumberAnimation { target: bellTilt; property: "angle"; to: 0; duration: 40 }
                                    }
                                    SequentialAnimation {
                                        loops: 6
                                        NumberAnimation { target: bellHop; property: "y"; to: -alarmIcon.size / 12; duration: 50 }
                                        NumberAnimation { target: bellHop; property: "y"; to: 0; duration: 50 }
                                    }
                                }
                                // A good breath between bursts, so it rings
                                // rather than buzzes: about one every 2.2s.
                                PauseAnimation { duration: 1500 }
                            }

                            // A notice: one small shake.
                            SequentialAnimation {
                                id: nudgeAnim
                                ParallelAnimation {
                                    SequentialAnimation {
                                        NumberAnimation { target: alarmArt; property: "scale"; to: 1.15; duration: 90; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: alarmArt; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.InOutQuad }
                                    }
                                    SequentialAnimation {
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: -10; duration: 60 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: 8; duration: 90 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: -4; duration: 80 }
                                        NumberAnimation { target: bodyTilt; property: "angle"; to: 0; duration: 70; easing.type: Easing.OutQuad }
                                    }
                                }
                            }

                            Connections {
                                target: root
                                function onNudgeSerialChanged() { if (!root.ringing) nudgeAnim.restart() }
                            }
                        }
                    }

                    // ====================================================
                    // 1b. REMINDER (beneath the time while one shows)
                    // ====================================================
                    ColumnLayout {
                        id: noticeColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: summaryHeader.bottom
                        anchors.leftMargin: Theme.spacing * 2
                        anchors.rightMargin: Theme.spacing * 2
                        spacing: Theme.spacing
                        visible: root.showNotice
                        opacity: root.showNotice ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.selection
                        }

                        Text {
                            id: noticeTitleText
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.noticeTitle
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: Theme.lightForeground
                            font.family: Theme.brandFont
                            font.pixelSize: 11
                            font.weight: Theme.titleWeight
                            font.capitalization: Font.AllUppercase
                        }

                        // What the reminder says, in the time's colour when
                        // it is going off.
                        Text {
                            id: noticeBodyText
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.noticeBody
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: root.ringing ? Theme.brand : Theme.foreground
                            font.family: root.ringing ? Theme.brandFont : Theme.fontFamily
                            font.pixelSize: root.ringing ? Theme.titleSize : 13
                            font.weight: root.ringing ? Theme.titleWeight : Font.Normal
                        }
                    }

                    // ====================================================
                    // 1c. REMINDER INPUT (Super+Ctrl+R)
                    // ====================================================
                    ColumnLayout {
                        id: inputColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: summaryHeader.bottom
                        anchors.topMargin: cardContainer.noticeHeight
                        anchors.leftMargin: Theme.spacing * 2
                        anchors.rightMargin: Theme.spacing * 2
                        spacing: Theme.spacing
                        visible: root.inputOpen
                        opacity: root.inputOpen ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.selection
                        }

                        // What was wrong with the last try, or on the message
                        // step how long the reminder is for. The minutes step
                        // has only its placeholder.
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.inputError
                                || (root.inputStep === "message"
                                    ? "In " + root.inputMinutes + (root.inputMinutes === "1" ? " minute" : " minutes")
                                    : "")
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            color: root.inputError ? Theme.urgent : Theme.lightForeground
                            font.family: Theme.brandFont
                            font.pixelSize: 11
                            font.weight: Theme.titleWeight
                            font.capitalization: Font.AllUppercase
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: reminderField.implicitHeight + Theme.spacing

                            TextInput {
                                id: reminderField
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: TextInput.AlignHCenter
                                color: Theme.foreground
                                selectionColor: Theme.brandBgc
                                selectedTextColor: Theme.brightForeground
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                clip: true
                                selectByMouse: true
                                inputMethodHints: root.inputStep === "minutes" ? Qt.ImhDigitsOnly : Qt.ImhNone
                                maximumLength: root.inputStep === "minutes" ? 5 : 200

                                onTextEdited: root.inputError = ""
                                onAccepted: root.submitReminderInput(text)
                                Keys.onEscapePressed: function (event) {
                                    if (text) text = ""
                                    else root.closeReminderInput()
                                    event.accepted = true
                                }

                                Text {
                                    anchors.fill: parent
                                    visible: !reminderField.text
                                    text: root.inputStep === "message" ? "Reminder message..." : "Remind in minutes..."
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.darkForeground
                                    font: reminderField.font
                                }

                                Connections {
                                    target: root
                                    function onInputSerialChanged() {
                                        reminderField.text = ""
                                        Qt.callLater(function () { reminderField.forceActiveFocus() })
                                    }
                                }
                            }
                        }
                    }

                    // ====================================================
                    // 2. DETAILS (Day & Date - Visible when expanded)
                    // ====================================================
                    ColumnLayout {
                        id: detailsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: summaryHeader.bottom
                        anchors.topMargin: cardContainer.noticeHeight + cardContainer.inputHeight
                        anchors.leftMargin: Theme.spacing * 2
                        anchors.rightMargin: Theme.spacing * 2
                        spacing: Theme.spacing
                        visible: root.isExpanded
                        opacity: root.isExpanded ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.selection
                        }

                        // Day of the Week (Prominent in grey / lightForeground)
                        Text {
                            id: dayText
                            Layout.alignment: Qt.AlignHCenter
                            text: root.day
                            color: Theme.lightForeground
                            font.family: Theme.brandFont
                            font.pixelSize: Theme.headlineSize
                            font.weight: Theme.titleWeight
                            font.capitalization: Font.AllUppercase
                        }

                        // Formatted Date (matched to the time)
                        Text {
                            id: dateText
                            Layout.alignment: Qt.AlignHCenter
                            text: root.date
                            color: Theme.brand
                            font.family: Theme.brandFont
                            font.pixelSize: Theme.titleSize
                            font.weight: Theme.titleWeight
                            font.capitalization: Font.AllUppercase
                        }

                        // Pending reminders, soonest first.
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.selection
                            visible: Reminders.count > 0
                        }

                        ColumnLayout {
                            id: upcomingColumn
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Theme.spacing / 2
                            visible: Reminders.count > 0

                            Repeater {
                                model: Reminders.pending

                                delegate: RowLayout {
                                    id: upcomingRow
                                    required property var modelData
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: Theme.spacing

                                    Text {
                                        text: upcomingRow.modelData.atTime
                                        textFormat: Text.PlainText
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        text: Reminders.remainingText(upcomingRow.modelData.at, clock.date.getTime())
                                        textFormat: Text.PlainText
                                        color: Theme.darkForeground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

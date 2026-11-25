import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Quickshell.Io


Scope{  
    id: root
    readonly property var battery: UPower.displayDevice
    
    property bool hideBar: true

    // Desktops and machines running straight off the mains still get a
    // display device from UPower, just one that is not present and reads 0%.
    // Without this, that 0% counts as critical and pins the bar on screen.
    // Waiting for ready keeps the bar from flashing up as critical before
    // the first reading arrives on a laptop too.
    readonly property bool hasBattery: !!battery && battery.ready && battery.isPresent

    readonly property int batteryState: UPower.displayDevice.state
    // Running off the battery, as opposed to the mains. A worn-out battery
    // on the charger can sit at a few percent as "not charging", "pending
    // charge" or even "fully charged", so the charge state alone cannot
    // tell a draining battery from one that is just plugged in.
    //
    // Not named onBattery: QML takes a name of "on" and a capital for a
    // signal handler, and such a property keeps its first value (false, as
    // the battery is not ready yet) for good, so the bolt never left and
    // the bar was never pinned on a critical battery.
    readonly property bool runningOnBattery: hasBattery && UPower.onBattery
    // Only a draining battery is critical: a low reading on the mains is not
    // going to run out, and pinning the bar for it would never let go.
    readonly property bool criticalBattery: runningOnBattery && battery.percentage <= 0.20
    readonly property bool lowBattery: battery.percentage <= 0.25
    readonly property bool mediumBattery: battery.percentage <= 0.50
    readonly property bool highBattery: battery.percentage <= 0.75
    readonly property bool fullBattery: battery.percentage === 1.00

    onCriticalBatteryChanged: {
        if (criticalBattery) {
            root.hideBar = false
        }
    }

    // A battery that goes away (or never turns out to be there) takes the
    // bar with it, critical or not.
    onHasBatteryChanged: {
        if (!hasBattery) {
            autoHide.stop()
            root.hideBar = true
        }
    }

    function reveal() {
        if (hasBattery && !criticalBattery) {
            root.hideBar = false
            autoHide.restart()
        }
    }

    onBatteryStateChanged: {
        root.reveal()
    }

    onHideBarChanged: {
        if (!root.hideBar && !criticalBattery) {
            autoHide.restart()
        } else {
            autoHide.stop()
        }
    }

    Timer {
        id: autoHide
        interval: Theme.hideDelay
        onTriggered: {
            root.hideBar = true
        }
    }

    // IPC Handler
    IpcHandler {
        target: "batteryBar"
        function toggle() {
            if (hasBattery && !criticalBattery) {
                if (root.hideBar) {
                    root.reveal()
                } else {
                    root.hideBar = true
                    autoHide.stop()
                }
            }
        }
        function open() {
            root.reveal()
        }
        function close() {
            if (!criticalBattery) {
                root.hideBar = true
                autoHide.stop()
            }
        }
    }

    GlobalShortcut {
        name: "batteryToggle"
        description: "Show the current battery information with the panel window"
        appid: "quickshell"
        onPressed: {
            if (root.hasBattery && !criticalBattery) {
                if (root.hideBar) {
                    root.reveal()
                } else {
                    root.hideBar = true
                    autoHide.stop()
                }
            }
        }
    }

    Component.onCompleted: {
        if (criticalBattery) {
            root.hideBar = false
        }
    }

    BarVariants {
        PanelWindow {
            id: panelWindow
            required property var modelData

            screen: modelData
            visible: false

            anchors.right: true

            WlrLayershell.namespace: "battery-panel-main"
            WlrLayershell.layer: Theme.islandLayer
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            implicitWidth: Theme.sidePanelWidth
            // Same height as the other side panels; see Theme.sidePanelHeight.
            implicitHeight: Theme.sidePanelHeight
            color: "transparent"

            mask: Region {
                item: !root.hideBar ? pillContainer : null
            }

            Item {
                id: pillContainer
                width: parent.width
                height: parent.height - 2 * Theme.scoopCapOverhang
                y: Theme.scoopCapOverhang
                x: width + 10

                Component.onCompleted: {
                    if (!root.hideBar) {
                        panelWindow.visible = true
                        pillContainer.x = 0
                    }
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
                        }
                    }
                }

                Connections {
                    target: root
                    function onHideBarChanged() {
                        if (!root.hideBar) {
                            panelWindow.visible = true
                            slideAnim.stop()
                            slideAnim.from = pillContainer.x
                            slideAnim.to = 0
                            slideAnim.start()
                        } else {
                            slideAnim.stop()
                            slideAnim.from = pillContainer.x
                            slideAnim.to = pillContainer.width + 10
                            slideAnim.start()
                        }
                    }
                }

                // Unified single-vector background contour (position: centerRight)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "centerRight"
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                    borderWidth: Theme.borderWidth
                }

                FlexboxLayout {
                    id: batteryFlex
                    anchors.fill: parent
                    anchors.topMargin: Theme.rounding + Theme.spacing * 2
                    anchors.bottomMargin: Theme.rounding + Theme.spacing * 2
                    anchors.leftMargin: Theme.spacing + Theme.borderWidth
                    anchors.rightMargin: Theme.borderWidth
                    direction: FlexboxLayout.Column
                    alignItems: FlexboxLayout.AlignCenter
                    gap: Theme.spacing / 2

                    Rectangle {
                        topLeftRadius: Theme.rounding
                        topRightRadius: Theme.rounding
                        bottomLeftRadius: 4
                        bottomRightRadius: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.highBattery ? Theme.brandBgc : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Rectangle {
                        radius: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.mediumBattery ? Theme.brandBgc : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        text: Math.round(root.battery.percentage * 100)
                        color: root.criticalBattery ? "red" : Theme.brand
                        font.family: Theme.displayFont
                        font.pixelSize: Theme.readoutSize
                        font.weight: Theme.titleWeight
                        font.capitalization: Font.AllUppercase
                    }
                    Rectangle {
                        radius: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.lowBattery ? Theme.brandBgc : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Rectangle {
                        id: batteryBottom
                        topLeftRadius: 4
                        topRightRadius: 4
                        bottomLeftRadius: Theme.rounding
                        bottomRightRadius: Theme.rounding
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.criticalBattery ? "red" : root.lowBattery ? "orange" : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }

                Image {
                    id: chargingIcon
                    anchors.bottom: batteryFlex.bottom
                    anchors.bottomMargin: Theme.spacing / 2
                    anchors.horizontalCenter: batteryFlex.horizontalCenter
                    // On the mains, charging or not, so a battery that never
                    // charges past a few percent still shows it is plugged in.
                    visible: root.hasBattery && !root.runningOnBattery
                    source: root.criticalBattery ? "decorations/lightning-fill-red.svg" : "decorations/lightning-fill.svg"
                    width: 14
                    height: 14
                    sourceSize.width: 14
                    sourceSize.height: 14
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }
}

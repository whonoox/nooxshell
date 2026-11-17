import QtQuick

// The shared selection plate (Theme.selectedFill edged in
// Theme.selectedBorder), drawn as a halo for a control whose own fill means
// something and must not change: a switch that is on, a Connect button. Put
// it inside the control; it sits behind it and reaches selectedHaloPad past
// its edges, with its corners kept concentric with the control's.
Rectangle {
    id: halo

    property bool active: false
    property real pad: Theme.selectedHaloPad

    z: -1
    anchors.fill: parent
    anchors.margins: -pad
    radius: (parent && parent.radius !== undefined ? parent.radius : 0) + pad
    color: Theme.selectedFill
    border.width: Theme.selectedBorderWidth
    border.color: Theme.selectedBorder
    opacity: active ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: 120 } }
}

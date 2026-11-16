import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// A switch sound on every key press and release, played only through the
// laptop's own speaker, whatever the default output is. Loaded by
// shell.qml only while ToggleState.keySounds is on, so nothing plays, no
// audio stream is open and Hyprland reports no keys while it is off.
//
// Hyprland sends each key as a global shortcut naming its sound, never the
// key itself: keySoundR0-R4 for the five rows, keySoundSpace, keySoundEnter,
// keySoundBackspace, and keySoundUp* for the releases. See QsKeys in
// hypr/quickshell-islands.lua.
Scope {
    id: root

    // The sound for each shortcut name, in sounds/keys.
    readonly property var sounds: ({
        "R0": "down-generic-r0",
        "R1": "down-generic-r1",
        "R2": "down-generic-r2",
        "R3": "down-generic-r3",
        "R4": "down-generic-r4",
        "Space": "down-space",
        "Enter": "down-enter-gunshot",
        "Backspace": "down-backspace",
        "Up": "up-generic",
        "UpSpace": "up-space",
        "UpEnter": "up-enter",
        "UpBackspace": "up-backspace"
    })
    readonly property var names: Object.keys(sounds)

    // Copies of each sound, taken in turn, so fast typing overlaps the
    // sounds instead of cutting the last one short.
    readonly property int voices: 3

    // The same cubic curve as the system volume slider, so 50 sounds half
    // as loud rather than barely quieter.
    readonly property real volume: Math.pow(Theme.keySoundVolume, 3)

    MediaDevices {
        id: devices
    }

    // The built-in speaker: the laptop's own sound card, not HDMI, USB or
    // Bluetooth. With nothing like it, the sounds stay silent rather than
    // going to the default output. Headphones in the laptop's jack share
    // the card, so they get the sounds too.
    //
    // Cards differ in how they name their outputs: an HDA card has one
    // analog-stereo output, a SOF card (most Intel laptops since 2020) one
    // per jack, such as HiFi__Speaker__sink, HiFi__Headphones__sink and
    // HiFi__HDMI1__sink. The display outputs never count; of the rest an
    // output named for the speaker comes first, then an analog one, then
    // whatever is left.
    readonly property var speaker: {
        var outs = devices.audioOutputs
        var best = null
        var bestRank = 0
        for (var i = 0; i < outs.length; i++) {
            var id = String(outs[i].id)
            if (id.indexOf("alsa_output.pci-") !== 0 || /hdmi|displayport|__dp\d/i.test(id))
                continue
            var rank = /speaker/i.test(id) ? 3 : (/analog/i.test(id) ? 2 : 1)
            if (rank > bestRank) {
                best = outs[i]
                bestRank = rank
            }
        }
        return best
    }

    onSpeakerChanged: {
        stats.speakerChanges++
        console.info("KeySounds: playing on", speaker ? speaker.id : "nothing, no built-in speaker found")
    }

    Component {
        id: effectComponent
        SoundEffect {
            audioDevice: root.speaker
            volume: root.volume
            muted: root.speaker === null
        }
    }

    property var pool: ({})
    property var turn: ({})

    function play(name) {
        stats.plays++
        var copies = pool[name]
        if (!copies)
            return
        var i = turn[name] || 0
        turn[name] = (i + 1) % copies.length
        copies[i].play()
    }

    // ------------------------------------------------------------------
    // Memory watchdog
    // ------------------------------------------------------------------
    // One report had the shell grow by gigabytes a minute with the key
    // sounds on, until the system ran out of memory, and the sounds being
    // remembered as on brought it back after a reboot. Whatever the cause,
    // the sounds turn themselves off, for good, once the shell has grown
    // by memoryLimit since they came on. The counters below go into the
    // log every minute while the shell grows, and when the watchdog trips,
    // so a report says what was happening.
    readonly property real memoryLimitKb: 1536 * 1024
    property real baseKb: 0
    property real lastLoggedKb: 0
    property bool tripped: false
    // Readings taken by the timer. FileView also reads the file as soon
    // as it is made, before the sounds are loaded, which is ignored: the
    // baseline is the first reading taken 10 s in.
    property int checks: 0
    property var stats: ({ plays: 0, speakerChanges: 0, rawEvents: 0, reloads: 0 })
    readonly property double startedAt: Date.now()

    function statsText(kb) {
        var minutes = ((Date.now() - startedAt) / 60000).toFixed(1)
        return "rss " + Math.round(kb / 1024) + " MB (+" + Math.round((kb - baseKb) / 1024)
            + " MB in " + minutes + " min), plays " + stats.plays
            + ", speaker changes " + stats.speakerChanges
            + ", Hyprland events " + stats.rawEvents + ", reloads " + stats.reloads
            + ", speaker " + (speaker ? speaker.id : "none")
    }

    FileView {
        id: status
        path: "/proc/self/status"
        printErrors: false
        onLoaded: {
            var m = /VmRSS:\s+(\d+)/.exec(text())
            if (!m || root.tripped || root.checks === 0)
                return
            var kb = Number(m[1])
            if (root.baseKb === 0) {
                root.baseKb = kb
                root.lastLoggedKb = kb
                return
            }
            if (kb - root.lastLoggedKb > 100 * 1024) {
                root.lastLoggedKb = kb
                console.warn("KeySounds: growing,", root.statsText(kb))
            }
            if (kb - root.baseKb > root.memoryLimitKb) {
                root.tripped = true
                console.error("KeySounds: turned off by the memory watchdog,", root.statsText(kb))
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "nooxshell",
                    "Key sounds turned off",
                    "The shell grew by " + Math.round((kb - root.baseKb) / 1024)
                    + " MB while they were on. Details are in nooxshell log."])
                ToggleState.setKeySounds(false)
            }
        }
    }

    Timer {
        interval: 10000
        running: !root.tripped
        repeat: true
        onTriggered: {
            root.checks++
            status.reload()
        }
    }

    // Hyprland reports keys only while the hook is on. A Hyprland reload
    // drops the hook, so it is asked for again.
    function sync(on) {
        Hyprland.dispatch("function() if QsKeys then QsKeys.set(" + on + ") end end")
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            root.stats.rawEvents++
            if (event.name === "configreloaded") {
                root.stats.reloads++
                root.sync(true)
            }
        }
    }

    Component.onCompleted: {
        var made = {}
        for (var n = 0; n < names.length; n++) {
            var copies = []
            for (var v = 0; v < voices; v++)
                copies.push(effectComponent.createObject(root, {
                    source: Qt.resolvedUrl("sounds/keys/" + sounds[names[n]] + ".wav")
                }))
            made[names[n]] = copies
        }
        pool = made
        sync(true)
    }

    Component.onDestruction: sync(false)

    Instantiator {
        model: root.names
        delegate: GlobalShortcut {
            required property string modelData
            name: "keySound" + modelData
            description: "Key sound (sent by Hyprland on each key)"
            appid: "quickshell"
            onPressed: root.play(modelData)
        }
    }
}

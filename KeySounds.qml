import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// A switch sound on every key press and release, and a lock sound as the
// screen locks, played only through the laptop's own speaker, whatever the
// default output is. Loaded by shell.qml only while ToggleState.keySounds
// is on, so nothing plays and Hyprland reports no keys while it is off.
//
// Hyprland sends each key as a global shortcut naming its sound, never the
// key itself: keySoundR0-R4 for the five rows, keySoundSpace, keySoundEnter,
// keySoundBackspace, and keySoundUp* for the releases. See QsKeys in
// hypr/quickshell-islands.lua.
//
// Each sound is its own short pw-play process, never Qt Multimedia inside
// the shell. Qt 6.12's audio backends, PipeWire and PulseAudio alike,
// handle an audio device going away (a WirePlumber restart on resume, a
// Bluetooth disconnect) on a background thread and can leave the shell's
// main thread polling a dead socket: the whole shell freezes at full CPU
// and logs "QSocketNotifier: Invalid socket" millions of times, until
// /run/user is full and nothing else can start. A pw-play that goes wrong
// takes only itself down.
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

    // The same cubic curve as the system volume slider, so 50 sounds half
    // as loud rather than barely quieter. pw-play takes it as a factor on
    // top of the speaker's own volume.
    readonly property string volume: Math.pow(Theme.keySoundVolume, 3).toFixed(3)

    // The node name of the built-in speaker, or "" for none.
    property string speaker: ""

    onSpeakerChanged: console.info("KeySounds: playing on", speaker || "nothing, no built-in speaker found")

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
    function pickSpeaker(sinkNames) {
        var best = ""
        var bestRank = 0
        for (var i = 0; i < sinkNames.length; i++) {
            var name = sinkNames[i]
            if (name.indexOf("alsa_output.pci-") !== 0 || /hdmi|displayport|__dp\d/i.test(name))
                continue
            var rank = /speaker/i.test(name) ? 3 : (/analog/i.test(name) ? 2 : 1)
            if (rank > bestRank) {
                best = name
                bestRank = rank
            }
        }
        return best
    }

    Process {
        id: listSinks
        command: ["pactl", "list", "short", "sinks"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var found = []
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var cols = lines[i].split("\t")
                    if (cols.length > 1)
                        found.push(cols[1])
                }
                root.speaker = root.pickSpeaker(found)
            }
        }
    }

    // Outputs come and go (a dock, a card profile change), so the list is
    // read again whenever a sink is added or removed.
    Process {
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (/'(new|remove)' on sink #/.test(line)) {
                    listSinks.running = false
                    listSinks.running = true
                }
            }
        }
    }

    function localPath(url) {
        return decodeURIComponent(String(Qt.resolvedUrl(url)).replace(/^file:\/\//, ""))
    }
    readonly property string soundDir: localPath("sounds/keys/")
    readonly property string lockSound: localPath("sounds/lock/lock_sound.wav")

    // At most this many sounds start in any one second. Typing never comes
    // near it; a runaway stream of key events cannot turn into a stream of
    // processes.
    readonly property int maxPerSecond: 40
    property var recent: []

    function play(name) {
        if (sounds[name])
            playFile(soundDir + sounds[name] + ".wav")
    }

    function playFile(path) {
        if (!speaker)
            return
        var now = Date.now()
        var kept = []
        for (var i = 0; i < recent.length; i++)
            if (now - recent[i] < 1000)
                kept.push(recent[i])
        if (kept.length >= maxPerSecond) {
            recent = kept
            return
        }
        kept.push(now)
        recent = kept
        // --latency 256 asks for a 256-sample (about 5 ms) buffer. pw-play's
        // default of 100 ms held each sound back by 60-75 ms, enough to
        // feel behind the key.
        Quickshell.execDetached(["pw-play", "--target", speaker, "--volume", volume,
            "--latency", "256", path])
    }

    // The screen lock. Omarchy's own shell locks the screen, whether from
    // Super+Ctrl+L, the menu, going idle or the lid, and tells nothing
    // else: Hyprland has no lock event and logind is never asked. It does
    // log each step in the plain-text log.log of its Quickshell instance,
    // so that file is followed. The click goes with "omarchy lock <time>
    // session-locked=true", logged once per lock as the lock screen covers
    // the display, about half a second after the lock was asked for.
    //
    // Each instance has its own directory, linked from by-shell/<md5 of
    // the shell.qml path>, and the links of finished ones stay behind. The
    // newest link is the running shell; it is looked for again every 5 s,
    // so a restarted Omarchy shell is picked up.
    readonly property string omarchyShellDir: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell/by-shell/"
        + Qt.md5((Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/shell.qml")

    Process {
        command: ["sh", "-c", `
            dir=$1 cur= pid=
            trap '[ -n "$pid" ] && kill "$pid"; exit' TERM INT HUP
            while :; do
                new=$(ls -t "$dir" 2>/dev/null | head -n 1)
                if [ "$new" != "$cur" ]; then
                    [ -n "$pid" ] && kill "$pid"
                    cur=$new pid=
                    if [ -n "$cur" ]; then
                        tail -n 0 -F --pid=$$ "$dir/$cur/log.log" 2>/dev/null &
                        pid=$!
                    fi
                fi
                sleep 5 & wait $!
            done`, "sh", root.omarchyShellDir]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (/ omarchy lock \S+ session-locked=true$/.test(line))
                    root.playFile(root.lockSound)
            }
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
            if (event.name === "configreloaded")
                root.sync(true)
        }
    }

    Component.onCompleted: sync(true)
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

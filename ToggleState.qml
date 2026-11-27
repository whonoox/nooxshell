pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string notifSettingsPath: home + "/.local/state/omarchy/notifications.json"

    // ------------------------------------------------------------------
    // Notification DND State
    // ------------------------------------------------------------------
    property bool dnd: false
    property bool _hydratingNotif: false
    property bool _notifSoundsSynced: false

    // DND silences the sounds apps play for their notifications as well as
    // the toasts; see bin/notification-sounds. Run again once the saved
    // state is first read, so a DND left on (or off) before a restart is
    // put back either way. The script does nothing when already in step.
    onDndChanged: syncNotifSounds()

    function syncNotifSounds() {
        root._notifSoundsSynced = true
        Quickshell.execDetached([Quickshell.shellPath("bin/notification-sounds"), root.dnd ? "mute" : "unmute"])
    }

    function toggleDnd() {
        setDnd(!root.dnd)
    }

    function setDnd(val) {
        root.dnd = !!val
        if (!root._hydratingNotif) {
            notifSaveTimer.restart()
        }
    }

    property Timer notifSaveTimer: Timer {
        interval: 150
        onTriggered: {
            if (root._hydratingNotif) return
            var payload = JSON.stringify({ version: 3, dnd: root.dnd }, null, 2) + "\n"
            if (notifSettingsWrite.setText) {
                notifSettingsWrite.setText(payload)
            } else {
                notifSettingsWrite.text = payload
            }
        }
    }

    property FileView notifSettingsWrite: FileView {
        path: root.notifSettingsPath
        printErrors: false
    }

    property FileView notifSettingsRead: FileView {
        path: root.notifSettingsPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            var raw = text()
            if (!raw) return
            root._hydratingNotif = true
            try {
                var parsed = JSON.parse(raw)
                root.dnd = !!(parsed && parsed.dnd)
            } catch (e) { }
            root._hydratingNotif = false
            if (!root._notifSoundsSynced) root.syncNotifSounds()
        }
        onFileChanged: reload()
    }

    // ------------------------------------------------------------------
    // Microphone Mute State
    // ------------------------------------------------------------------
    property bool micMuted: false
    property bool micAvailable: true

    function refreshMic() {
        if (!probeMicProcess.running) {
            probeMicProcess.running = true
        }
    }

    function toggleMic() {
        // Run omarchy-audio-input-mute or fallback to pactl
        Quickshell.execDetached([
            "bash", "-c",
            "if which omarchy-audio-input-mute >/dev/null 2>&1; then omarchy-audio-input-mute; else pactl set-source-mute @DEFAULT_SOURCE@ toggle; fi"
        ])
        // Optimistic toggle for instant visual response
        root.micMuted = !root.micMuted
        micSettleTimer.restart()
    }

    property Timer micSettleTimer: Timer {
        interval: 250
        onTriggered: root.refreshMic()
    }

    property Process probeMicProcess: Process {
        command: [
            "bash", "-c",
            "pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{ print ($NF == \"yes\") ? \"muted\" : \"live\" }'"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var l = String(line || "").trim()
                if (l === "muted") {
                    root.micMuted = true
                    root.micAvailable = true
                } else if (l === "live") {
                    root.micMuted = false
                    root.micAvailable = true
                }
            }
        }
    }

    property Process pactlSubscriber: Process {
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("'change' on source") !== -1 || line.indexOf("'change' on server") !== -1) {
                    root.refreshMic()
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Cursor X-Ray State
    // ------------------------------------------------------------------
    property bool cursorXRay: false

    function toggleCursorXRay() {
        setCursorXRay(!root.cursorXRay)
    }

    function setCursorXRay(val) {
        root.cursorXRay = !!val
    }

    // ------------------------------------------------------------------
    // Key Sounds State
    // ------------------------------------------------------------------
    // Kept across restarts in a file holding "on" or "off". KeySounds.qml
    // is loaded while this is on.
    readonly property string keySoundsPath: home + "/.local/state/nooxshell/key-sounds"
    property bool keySounds: false

    function toggleKeySounds() {
        setKeySounds(!root.keySounds)
    }

    function setKeySounds(val) {
        root.keySounds = !!val
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${1%/*}" && printf %s "$2" > "$1"',
            "sh", root.keySoundsPath, root.keySounds ? "on" : "off"])
    }

    property FileView keySoundsFile: FileView {
        path: root.keySoundsPath
        printErrors: false
        onLoaded: root.keySounds = text().trim() === "on"
    }

    // ------------------------------------------------------------------
    // Stay Awake (Idle Inhibition) State
    // ------------------------------------------------------------------
    readonly property string stayAwakeDir: home + "/.local/state/omarchy/indicators"
    readonly property string stayAwakePath: stayAwakeDir + "/stay-awake"
    property bool stayAwake: false

    function refreshStayAwake() {
        if (!probeStayAwakeProcess.running) {
            probeStayAwakeProcess.running = true
        }
    }

    function toggleStayAwake() {
        Quickshell.execDetached([
            "bash", "-c",
            "if which omarchy-toggle-idle >/dev/null 2>&1; then omarchy-toggle-idle toggle; else mkdir -p \"$HOME/.local/state/omarchy/indicators\"; if [[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]]; then rm -f \"$HOME/.local/state/omarchy/indicators/stay-awake\"; else touch \"$HOME/.local/state/omarchy/indicators/stay-awake\"; fi; fi"
        ])
        root.stayAwake = !root.stayAwake
        stayAwakeSettleTimer.restart()
    }

    function setStayAwake(val) {
        var cmd = val ? "stay-awake" : "allow-idle"
        Quickshell.execDetached([
            "bash", "-c",
            "if which omarchy-toggle-idle >/dev/null 2>&1; then omarchy-toggle-idle " + cmd + "; else mkdir -p \"$HOME/.local/state/omarchy/indicators\"; if [ \"" + (val ? "1" : "0") + "\" = \"1\" ]; then touch \"$HOME/.local/state/omarchy/indicators/stay-awake\"; else rm -f \"$HOME/.local/state/omarchy/indicators/stay-awake\"; fi; fi"
        ])
        root.stayAwake = !!val
        stayAwakeSettleTimer.restart()
    }

    property Timer stayAwakeSettleTimer: Timer {
        interval: 200
        onTriggered: root.refreshStayAwake()
    }

    property Process probeStayAwakeProcess: Process {
        command: [
            "bash", "-c",
            "if [[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]]; then echo yes; else echo no; fi"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                root.stayAwake = (String(line || "").trim() === "yes")
            }
        }
    }

    property FileView stayAwakeDirWatcher: FileView {
        path: root.stayAwakeDir
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshStayAwake()
    }

    // ------------------------------------------------------------------
    // Fn Lock State
    // ------------------------------------------------------------------
    // The lock is read from one of two places:
    //   "led"   Lenovo IdeaPads: ideapad_laptop's platform::fnlock LED, which
    //           the shell reads every second and can set.
    //   "dell"  Dell laptops: the BIOS's FnLockMode setting, read once at
    //           startup, then followed through the kernel log as Fn+Esc is
    //           pressed. Each read is a call into the BIOS, so it is not
    //           polled, and the shell cannot set it. Both need the system
    //           file install.sh adds on Dells (system/nooxshell-dell-fnlock.conf).
    // fnLockAvailable is true while the lock's state is known.
    readonly property string fnLockLedPath: "/sys/class/leds/platform::fnlock/brightness"
    property string fnLockSource: "led"
    readonly property bool fnLockSettable: fnLockSource === "led"
    property bool fnLock: false
    property bool fnLockAvailable: true

    function refreshFnLock() {
        if (root.fnLockSource === "led" && !probeFnLockProcess.running) {
            probeFnLockProcess.running = true
        }
    }

    function toggleFnLock() {
        if (!root.fnLockSettable) return
        Quickshell.execDetached([
            "bash", "-c",
            "val=$(cat /sys/class/leds/platform::fnlock/brightness 2>/dev/null || echo 0); if [ \"$val\" = \"1\" ]; then brightnessctl -q -d platform::fnlock set 0; else brightnessctl -q -d platform::fnlock set 1; fi"
        ])
        root.fnLock = !root.fnLock
        fnLockSettleTimer.restart()
    }

    function setFnLock(val) {
        if (!root.fnLockSettable) return
        var target = val ? "1" : "0"
        Quickshell.execDetached([
            "bash", "-c",
            "brightnessctl -q -d platform::fnlock set " + target
        ])
        root.fnLock = !!val
        fnLockSettleTimer.restart()
    }

    property Timer fnLockSettleTimer: Timer {
        interval: 200
        onTriggered: root.refreshFnLock()
    }

    property Process probeFnLockProcess: Process {
        command: ["cat", "/sys/class/leds/platform::fnlock/brightness"]
        stdout: SplitParser {
            onRead: function(line) {
                var l = String(line || "").trim()
                root.fnLockAvailable = true
                root.fnLock = (l === "1")
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                // No IdeaPad LED: try the Dell BIOS setting instead.
                root.fnLockAvailable = false
                root.fnLockSource = ""
                findDellFnLockProcess.running = true
            }
        }
    }

    property Timer fnLockPollTimer: Timer {
        interval: 1000
        running: root.fnLockSource === "led" && root.fnLockAvailable
        repeat: true
        onTriggered: root.refreshFnLock()
    }

    // Dell: FnLockMode is "DisableStandard" while Fn lock is on (F1-F12 by
    // default, as with the IdeaPad's lit LED) and "EnableSecondary" while
    // the media keys are. Prints "unknown" when the file is there but not
    // readable, as before the system file is installed: the lock is then
    // known from the first Fn+Esc on.
    function applyDellFnLockMode(mode) {
        if (mode === "DisableStandard" || mode === "EnableSecondary") {
            // The state comes before availability, so this first reading
            // does not pop the island up (ToggleBar reveals only changes
            // to a lock already known).
            root.fnLock = mode === "DisableStandard"
            root.fnLockAvailable = true
        }
    }

    property Process findDellFnLockProcess: Process {
        command: ["sh", "-c", "for f in /sys/class/firmware-attributes/*/attributes/FnLockMode/current_value; do [ -e \"$f\" ] || continue; cat \"$f\" 2>/dev/null || echo unknown; exit 0; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var mode = text.trim()
                if (!mode) return
                root.fnLockSource = "dell"
                root.applyDellFnLockMode(mode)
                dellFnLockFollower.running = true
            }
        }
    }

    // Each Fn+Esc logs "dell_wmi: Received WMI event (02 00 12 00 35 e0 XX
    // ...)": event type 0x0012, code 0xe035, with XX 00 for Fn lock on and
    // 01 for off. The kernel log is readable by the wheel group, which
    // Omarchy's user is in.
    readonly property var dellFnLockEvent: /dell_wmi: Received WMI event \([0-9a-f]{2} [0-9a-f]{2} 12 00 35 e0 ([0-9a-f]{2})/

    property Process dellFnLockFollower: Process {
        command: ["journalctl", "--dmesg", "--follow", "--lines=0", "--output=cat"]
        stdout: SplitParser {
            onRead: function(line) {
                var match = root.dellFnLockEvent.exec(String(line || ""))
                if (!match) return
                root.fnLockAvailable = true
                root.fnLock = match[1] === "00"
            }
        }
        // journalctl should run for the session; if it stops, start it again.
        onExited: dellFnLockRestartTimer.restart()
    }

    property Timer dellFnLockRestartTimer: Timer {
        interval: 5000
        onTriggered: if (root.fnLockSource === "dell") root.dellFnLockFollower.running = true
    }

    // ------------------------------------------------------------------
    // Caps Lock State
    // ------------------------------------------------------------------
    // Read from the keyboard's caps lock LED in sysfs, which the kernel
    // keeps in step with the lock even on keys whose light does not work.
    // It is only shown, not set: the lock belongs to the keyboard, and a key
    // pressed through a Wayland virtual keyboard (wtype) has a lock of its
    // own that the real one never sees. Hyprland sets every keyboard's LED
    // alike, so the first LED found does. When it goes away (a keyboard
    // unplugged), another is looked for.
    property string capsLockLedPath: ""
    property bool capsLock: false
    readonly property bool capsLockAvailable: capsLockLedPath !== ""

    function findCapsLock() {
        if (!findCapsLockProcess.running) findCapsLockProcess.running = true
    }

    property Process findCapsLockProcess: Process {
        command: ["sh", "-c", "for f in /sys/class/leds/*::capslock/brightness; do [ -e \"$f\" ] && { echo \"$f\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLockLedPath = text.trim()
        }
    }

    property FileView capsLockFile: FileView {
        path: root.capsLockLedPath
        printErrors: false
        onLoaded: root.capsLock = text().trim() === "1"
        onLoadFailed: {
            root.capsLockLedPath = ""
            root.capsLock = false
        }
    }

    // A sysfs file sends no change notice, so it is read again five times a
    // second: Caps Lock is pressed often and its state should show at once.
    property Timer capsLockPollTimer: Timer {
        interval: 200
        running: root.capsLockAvailable
        repeat: true
        onTriggered: root.capsLockFile.reload()
    }

    property Timer capsLockFindTimer: Timer {
        interval: 5000
        running: !root.capsLockAvailable
        repeat: true
        onTriggered: root.findCapsLock()
    }

    // ------------------------------------------------------------------
    // Input Language (Fcitx) State
    // ------------------------------------------------------------------
    // Read and switched through Omarchy's own Fcitx reader, the one its bar
    // runs for Super+I: it prints the current method as a line of JSON
    // whenever it changes and steps to the next one on "cycle". Fcitx keeps
    // one method per window, so the reading follows the focused window. A
    // switch made before any text field has focus is kept until one does.
    // Without Fcitx it cycles the keyboard layouts instead.
    readonly property string inputReaderPath: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy")
        + "/default/input-methods/indicator.py"
    property var inputMethods: []
    property string inputMethod: ""
    property string inputName: ""
    property string inputLabel: ""
    property string inputLanguage: ""
    readonly property bool inputAvailable: inputMethods.length > 1

    // Two or three letters for the island: Fcitx's label when it has one,
    // else the method's language ("en", "am").
    readonly property string inputShortLabel: {
        var text = root.inputLabel || root.inputLanguage || root.inputName.replace(/^Keyboard - /, "")
        return String(text).split(/[_\s(]/)[0].substring(0, 3)
    }

    function cycleInput(back) {
        if (!inputReader.running) return false
        inputReader.write(back ? "cycle back\n" : "cycle\n")
        return true
    }

    property Process inputReader: Process {
        command: ["/usr/bin/python3", root.inputReaderPath]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function(line) {
                var state
                try { state = JSON.parse(line) } catch (e) { return }
                root.inputMethods = state.methods || []
                root.inputName = state.name || ""
                root.inputLabel = state.label || ""
                root.inputLanguage = state.language || ""
                // Last, so a change is seen with the rest already in place.
                root.inputMethod = state.current || ""
            }
        }
        onExited: {
            root.inputMethods = []
            root.inputMethod = ""
            inputReaderRestartTimer.restart()
        }
    }

    property Timer inputReaderRestartTimer: Timer {
        interval: 5000
        onTriggered: root.inputReader.running = true
    }

    // ------------------------------------------------------------------
    // Airplane Mode State
    // ------------------------------------------------------------------
    property bool airplaneMode: false
    property double lastExternalRfkillChange: 0

    function refreshAirplane() {
        if (!probeAirplaneProcess.running) {
            probeAirplaneProcess.running = true
        }
    }

    function toggleAirplane() {
        // Guard: if hardware radio killswitch was pressed recently (<600ms), don't double-toggle
        if (Date.now() - root.lastExternalRfkillChange < 600) {
            return
        }
        var target = !root.airplaneMode
        Quickshell.execDetached([
            "bash", "-c",
            target ? "rfkill block all" : "rfkill unblock all"
        ])
        root.airplaneMode = target
        airplaneSettleTimer.restart()
    }

    function setAirplane(val) {
        Quickshell.execDetached([
            "bash", "-c",
            val ? "rfkill block all" : "rfkill unblock all"
        ])
        root.airplaneMode = !!val
        airplaneSettleTimer.restart()
    }

    property Timer airplaneSettleTimer: Timer {
        interval: 250
        onTriggered: root.refreshAirplane()
    }

    property Process probeAirplaneProcess: Process {
        command: [
            "bash", "-c",
            "if rfkill list | grep -q 'Soft blocked: yes'; then echo blocked; else echo unblocked; fi"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var l = String(line || "").trim()
                var blocked = (l === "blocked")
                if (root.airplaneMode !== blocked) {
                    root.lastExternalRfkillChange = Date.now()
                    root.airplaneMode = blocked
                }
            }
        }
    }

    property Process rfkillSubscriber: Process {
        command: ["rfkill", "event"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                root.refreshAirplane()
            }
        }
    }

    // ------------------------------------------------------------------
    // Night Light State
    // ------------------------------------------------------------------
    property bool nightLight: false

    function refreshNightLight() {
        if (!probeNightLightProcess.running) {
            probeNightLightProcess.running = true
        }
    }

    function toggleNightLight() {
        Quickshell.execDetached([
            "bash", "-c",
            "omarchy-toggle-nightlight"
        ])
        root.nightLight = !root.nightLight
        nightLightSettleTimer.restart()
    }

    function setNightLight(val) {
        var targetTemp = val ? 4000 : 6500
        Quickshell.execDetached([
            "bash", "-c",
            "pgrep -x hyprsunset >/dev/null || { setsid uwsm-app -- hyprsunset >/dev/null 2>&1 & sleep 1; }; hyprctl hyprsunset temperature " + targetTemp
        ])
        root.nightLight = !!val
        nightLightSettleTimer.restart()
    }

    property Timer nightLightSettleTimer: Timer {
        interval: 350
        onTriggered: root.refreshNightLight()
    }

    property Process probeNightLightProcess: Process {
        command: [
            "bash", "-c",
            "temp=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -n1); if [ -n \"$temp\" ] && [ \"$temp\" -lt 6000 ]; then echo on; else echo off; fi"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var l = String(line || "").trim()
                root.nightLight = (l === "on")
            }
        }
    }

    Component.onCompleted: {
        notifSettingsRead.reload()
        root.refreshMic()
        root.refreshStayAwake()
        root.refreshFnLock()
        root.findCapsLock()
        root.refreshAirplane()
        root.refreshNightLight()
    }
}

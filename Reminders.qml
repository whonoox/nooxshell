pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Omarchy's reminders (Super+Ctrl+R, `omarchy reminder <minutes> [message]`)
// shown on the time island rather than as toasts.
//
// omarchy-reminder keeps no state the shell could watch: each reminder is a
// systemd user timer that, when it runs out, sends a notification. Every
// notification it sends -- the reminder going off, and the set, show and
// clear confirmations -- comes from omarchy-action with the 󰢌 glyph, and
// nothing else in Omarchy uses that glyph. NotificationPanel hands those to
// take() instead of showing a toast. The one that is the reminder going off
// has the title omarchy-i18n gives for reminder.title, read here so it
// matches in any language.
//
// The pending list comes from `omarchy-reminder show --json`, read again on
// every reminder notification and whenever the time island expands.
QtObject {
    id: root

    readonly property string glyph: String.fromCodePoint(0xF088C)

    // The title of the notification sent when a reminder goes off.
    property string firedTitle: "Reminder"
    // The title of `omarchy reminder show`, told apart from the set and
    // clear confirmations so the island can open its list for it.
    property string upcomingTitle: "Upcoming reminders"

    // Reminders still to go off, soonest first:
    //   { label, message, at (seconds since the epoch), atTime ("14:32") }
    property var pending: []
    readonly property int count: pending.length

    // A reminder went off; message is what it says.
    signal fired(string message)
    // Any other reminder notification. Its text is not passed on: only a
    // reminder going off shows what it says. listing is true for `omarchy
    // reminder show`, false for a reminder being set or cleared.
    signal notice(bool listing)
    // Open the reminder input on the time island (Super+Ctrl+R, or Set
    // reminder in the menu), in place of Omarchy's own window.
    signal inputRequested()

    function requestInput() { root.inputRequested() }

    function claims(notification) {
        if (!notification || String(notification.appName || "") !== "omarchy-action") return false
        try {
            return String(notification.hints["omarchy-glyph"] || "") === root.glyph
        } catch (e) {
            return false
        }
    }

    function take(summary, body) {
        var title = String(summary || "")
        var text = String(body || "")
        if (title === root.firedTitle) {
            root.fired(text)
        } else {
            root.notice(title === root.upcomingTitle)
        }
        root.refresh()
    }

    property bool _refreshAgain: false

    function refresh() {
        if (listProc.running) {
            root._refreshAgain = true
        } else {
            listProc.running = true
        }
    }

    function parse(raw) {
        try {
            var data = JSON.parse(raw)
            var list = (data && data.reminders) || []
            list.sort(function (a, b) { return Number(a.at) - Number(b.at) })
            root.pending = list.map(function (r) {
                return {
                    label: String(r.label || ""),
                    message: String(r.message || ""),
                    at: Number(r.at) || 0,
                    atTime: String(r.atTime || "")
                }
            })
        } catch (e) {
            root.pending = []
        }
    }

    // "in 14m", "in 1h 5m", "in 40s", from seconds left.
    function remainingText(atSeconds, nowMs) {
        var left = Math.max(0, Math.round(atSeconds - nowMs / 1000))
        if (left < 60) return "in " + left + "s"
        var minutes = Math.ceil(left / 60)
        if (minutes < 60) return "in " + minutes + "m"
        var hours = Math.floor(minutes / 60)
        var rest = minutes % 60
        return "in " + hours + "h" + (rest > 0 ? " " + rest + "m" : "")
    }

    property Process listProc: Process {
        command: ["omarchy-reminder", "show", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) root.pending = []
            if (root._refreshAgain) {
                root._refreshAgain = false
                root.refresh()
            }
        }
    }

    property Process titleProc: Process {
        command: ["omarchy-i18n", "reminder.title"]
        stdout: StdioCollector {
            onStreamFinished: {
                var title = text.trim()
                if (title) root.firedTitle = title
            }
        }
    }

    property Process upcomingTitleProc: Process {
        command: ["omarchy-i18n", "reminder.upcoming"]
        stdout: StdioCollector {
            onStreamFinished: {
                var title = text.trim()
                if (title) root.upcomingTitle = title
            }
        }
    }

    Component.onCompleted: {
        titleProc.running = true
        upcomingTitleProc.running = true
        root.refresh()
    }
}

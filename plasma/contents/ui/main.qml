import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

import "zones.js" as Zones

WallpaperItem {
    id: root

    readonly property var cfg: root.configuration
    // The lock screen blurs the whole wallpaper item when the password prompt
    // appears, so there the card is moved onto the window, above the blur.
    readonly property bool inLockScreen: Qt.application.name === "kscreenlocker_greet"
    readonly property bool english: cfg.English
    readonly property var store: {
        try {
            return JSON.parse(cfg.PrayerData);
        } catch (e) {
            return null;
        }
    }
    // Indices of prayers checked off today, e.g. [1, 3].
    // Clicks update this immediately; the lock screen doesn't reload its config.
    property var localDone: null
    readonly property var done: {
        let d = localDone;
        if (!d) {
            try {
                d = JSON.parse(cfg.Done);
            } catch (e) {
                return [];
            }
        }
        return d.d === isoDate(now) ? d.p : [];
    }
    readonly property var prayerKeys: ["", "subuh", "", "zohor", "asar", "maghrib", "isyak"]

    function setDone(i, value) {
        const list = done.filter(p => p !== i);
        if (value) list.push(i);
        localDone = { d: isoDate(now), p: list };
        runner.connectSource('PATH="$HOME/.cargo/bin:$PATH" solat-lock ' + (value ? "done " : "undo ") + prayerKeys[i]);
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: (source, data) => disconnectSource(source)
    }
    readonly property bool stale: !store || store.zone !== cfg.Zone

    property date now: new Date()

    // Index into store.days for the current date, -1 if missing.
    readonly property int todayIndex: {
        if (stale) return -1;
        const key = isoDate(now);
        for (let i = 0; i < store.days.length; i++) {
            if (store.days[i].d === key) return i;
        }
        return -1;
    }
    readonly property var today: todayIndex >= 0 ? store.days[todayIndex] : null
    readonly property bool isFriday: now.getDay() === 5

    readonly property var namesMs: ["Imsak", "Subuh", "Syuruk", "Zohor", "Asar", "Maghrib", "Isyak"]
    readonly property var namesEn: ["Imsak", "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    readonly property var monthsMs: ["Januari", "Februari", "Mac", "April", "Mei", "Jun", "Julai", "Ogos", "September", "Oktober", "November", "Disember"]
    readonly property var daysMs: ["Ahad", "Isnin", "Selasa", "Rabu", "Khamis", "Jumaat", "Sabtu"]
    readonly property var hijriMs: ["Muharram", "Safar", "Rabiulawal", "Rabiulakhir", "Jamadilawal", "Jamadilakhir", "Rejab", "Syaaban", "Ramadan", "Syawal", "Zulkaedah", "Zulhijjah"]
    readonly property var hijriEn: ["Muharram", "Safar", "Rabi' al-Awwal", "Rabi' al-Thani", "Jumada al-Awwal", "Jumada al-Thani", "Rajab", "Sha'ban", "Ramadan", "Shawwal", "Dhu al-Qa'dah", "Dhu al-Hijjah"]

    // Next prayer (Imsak is not counted): { index, at, tomorrow }.
    readonly property var next: {
        if (!today) return null;
        for (let i = 1; i < 7; i++) {
            const at = toDate(today.d, today.t[i]);
            if (at > now) return { index: i, at: at, tomorrow: false };
        }
        if (todayIndex + 1 < store.days.length) {
            const tmr = store.days[todayIndex + 1];
            return { index: 1, at: toDate(tmr.d, tmr.t[1]), tomorrow: true };
        }
        return null;
    }

    // Prayer whose time is in effect now (index into t), -1 if none:
    // before Subuh, and between Syuruk and Zohor.
    readonly property int current: {
        if (!today) return -1;
        let idx = -1;
        for (let i = 1; i < 7; i++) {
            if (toDate(today.d, today.t[i]) <= now) idx = i;
        }
        return idx === 2 ? -1 : idx;
    }

    // Whole days of cached times left after today. solat-lock refetches when
    // fewer than 14 remain, so a low number means syncing has been failing.
    readonly property int daysLeft: store && !stale && store.days.length > 0
        ? Math.round((toDate(store.days[store.days.length - 1].d, "00:00") - toDate(isoDate(now), "00:00")) / 86400000)
        : -1
    readonly property bool lowData: today !== null && daysLeft < 7

    readonly property color accent: "#8ff0c8"

    function pad(n) { return n < 10 ? "0" + n : "" + n; }
    function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
    function toDate(day, hhmm) {
        const p = day.split("-"), t = hhmm.split(":");
        return new Date(+p[0], +p[1] - 1, +p[2], +t[0], +t[1]);
    }
    function prayerName(i, friday) {
        if (i === 3 && friday) return english ? "Jumu'ah" : "Jumaat";
        return (english ? namesEn : namesMs)[i];
    }
    function formatTime(hhmm) {
        if (!cfg.Use12h) return hhmm;
        const t = hhmm.split(":"), h = +t[0];
        return ((h + 11) % 12 + 1) + ":" + t[1] + (h < 12 ? " AM" : " PM");
    }
    function gregorianText(d) {
        if (english) return Qt.formatDate(d, "dddd, d MMMM yyyy");
        return daysMs[d.getDay()] + ", " + d.getDate() + " " + monthsMs[d.getMonth()] + " " + d.getFullYear();
    }
    function hijriText(h) {
        const p = h.split("-");
        return (+p[2]) + " " + (english ? hijriEn : hijriMs)[+p[1] - 1] + " " + p[0] + (english ? " AH" : "H");
    }
    function countdownText() {
        if (!next) return "";
        const mins = Math.ceil((next.at - now) / 60000);
        const name = prayerName(next.index, next.tomorrow ? (now.getDay() + 1) % 7 === 5 : isFriday);
        if (mins <= 1) return english ? name + " in under a minute" : name + " kurang seminit lagi";
        const h = Math.floor(mins / 60), m = mins % 60;
        let span;
        if (english) span = (h ? h + " h " : "") + (m ? m + " min" : "");
        else span = (h ? h + " jam " : "") + (m ? m + " minit" : "");
        return english ? name + " in " + span.trim() : name + " dalam " + span.trim();
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#0f2027" }
            GradientStop { position: 1; color: "#203a43" }
        }
    }

    Image {
        anchors.fill: parent
        source: root.cfg.Image
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.width
        sourceSize.height: root.height
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.cfg.Dim / 100
    }

    Rectangle {
        id: card

        parent: root.inLockScreen && root.Window.contentItem ? root.Window.contentItem : root
        z: 1000

        readonly property int pos: root.cfg.Position
        readonly property bool onRight: pos >= 3
        readonly property int row: pos % 3 // 0 top, 1 center, 2 bottom
        readonly property real margin: Math.max(Kirigami.Units.gridUnit * 2, root.width * 0.04)
        readonly property real u: Math.max(1, Math.min(root.width, root.height) / 1080)

        width: content.implicitWidth + 48 * u
        height: content.implicitHeight + 40 * u
        x: onRight ? root.width - width - margin : margin
        y: row === 0 ? margin : row === 1 ? (root.height - height) / 2 : root.height - height - margin
        radius: 18 * u
        color: Qt.rgba(0, 0, 0, 0.45)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        ColumnLayout {
            id: content
            anchors.centerIn: parent
            spacing: 6 * card.u

            Text {
                text: root.english ? "Prayer Times" : "Waktu Solat"
                color: "white"
                font.pixelSize: 26 * card.u
                font.weight: Font.DemiBold
            }
            Text {
                readonly property var zone: Zones.find(root.cfg.Zone)
                text: zone ? zone.code + " · " + zone.name : root.cfg.Zone
                color: Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: 14 * card.u
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 320 * card.u
            }
            Text {
                visible: root.today !== null
                text: root.today ? root.gregorianText(root.now) + "\n" + root.hijriText(root.today.h) : ""
                color: Qt.rgba(1, 1, 1, 0.85)
                font.pixelSize: 15 * card.u
                lineHeight: 1.15
                Layout.bottomMargin: 8 * card.u
            }

            Repeater {
                model: root.today ? 7 : 0

                delegate: Rectangle {
                    id: row
                    required property int index
                    readonly property bool isCurrent: root.current === index
                    readonly property bool started: root.toDate(root.today.d, root.today.t[index]) <= root.now
                    readonly property bool past: started && !isCurrent
                    readonly property bool isDone: root.done.indexOf(index) >= 0
                    // Only real prayers that have started can be checked off.
                    readonly property bool checkable: root.prayerKeys[index] !== "" && started

                    Layout.fillWidth: true
                    Layout.minimumWidth: 300 * card.u
                    implicitHeight: 40 * card.u
                    radius: 10 * card.u
                    color: isCurrent ? Qt.rgba(0.56, 0.94, 0.78, 0.14) : "transparent"
                    border.color: isCurrent ? Qt.rgba(0.56, 0.94, 0.78, 0.6) : "transparent"
                    border.width: 1.5 * card.u

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "white"
                        opacity: mouse.containsMouse && row.checkable ? 0.08 : 0
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        enabled: row.checkable
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setDone(row.index, !row.isDone)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14 * card.u
                        anchors.rightMargin: 14 * card.u
                        Text {
                            text: root.prayerName(index, root.isFriday)
                            color: isCurrent ? root.accent : "white"
                            opacity: past ? 0.45 : (index === 0 || index === 2 ? 0.75 : 1)
                            font.pixelSize: 19 * card.u
                            font.weight: isCurrent ? Font.Bold : Font.Normal
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.formatTime(root.today.t[index])
                            color: isCurrent ? root.accent : "white"
                            opacity: past ? 0.45 : 1
                            font.pixelSize: 19 * card.u
                            font.weight: isCurrent ? Font.Bold : Font.Normal
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            text: row.isDone ? "✓" : (row.checkable && (mouse.containsMouse || row.isCurrent) ? "○" : "")
                            color: root.accent
                            opacity: row.isDone ? 1 : 0.6
                            font.pixelSize: 19 * card.u
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 22 * card.u
                        }
                    }
                }
            }

            Text {
                visible: text !== ""
                text: root.countdownText()
                color: root.accent
                font.pixelSize: 17 * card.u
                font.weight: Font.DemiBold
                Layout.topMargin: 8 * card.u
            }

            Text {
                visible: root.today === null || root.stale
                text: root.english
                    ? "No prayer times cached for " + root.cfg.Zone + ".\nRun: solat-lock sync"
                    : "Tiada data waktu solat untuk " + root.cfg.Zone + ".\nJalankan: solat-lock sync"
                color: "#ffb4a2"
                font.pixelSize: 14 * card.u
            }

            Text {
                visible: root.lowData
                text: root.english
                    ? "⚠ Times only cached for " + root.daysLeft + " more day(s) — sync has been failing.\nCheck internet, then run: solat-lock sync"
                    : "⚠ Data hanya untuk " + root.daysLeft + " hari lagi — kemas kini gagal.\nSemak internet, kemudian jalankan: solat-lock sync"
                color: "#ffd479"
                font.pixelSize: 14 * card.u
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 320 * card.u
            }
        }
    }
}

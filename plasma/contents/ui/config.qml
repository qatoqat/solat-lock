import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "zones.js" as Zones

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout

    property alias formLayout: root

    property string cfg_Zone
    property string cfg_Image
    property alias cfg_Dim: dimSlider.value
    property alias cfg_Position: positionBox.currentIndex
    property alias cfg_English: englishBox.checked
    property alias cfg_Use12h: use12hBox.checked
    property alias cfg_Notify: notifyBox.checked
    property alias cfg_RemindEvery: remindBox.value
    property string cfg_Done
    property string cfg_PrayerData

    readonly property var store: {
        try {
            return JSON.parse(cfg_PrayerData);
        } catch (e) {
            return null;
        }
    }

    QQC2.ComboBox {
        id: zoneBox
        Kirigami.FormData.label: "Zone:"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        model: Zones.zones.map(z => ({ text: z.code + " — " + z.state + ": " + z.name, code: z.code }))
        textRole: "text"
        valueRole: "code"
        currentIndex: Zones.zones.findIndex(z => z.code === root.cfg_Zone)
        onActivated: root.cfg_Zone = currentValue
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: root.store && root.store.zone === root.cfg_Zone ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.neutralTextColor
        text: {
            const s = root.store;
            if (s && s.zone === root.cfg_Zone && s.days.length > 0)
                return "Data cached until " + s.days[s.days.length - 1].d + " (fetched " + s.fetched + ").";
            return "After applying, the solat-lock service downloads times for this zone. You can also run: solat-lock sync";
        }
    }

    RowLayout {
        Kirigami.FormData.label: "Background:"
        QQC2.TextField {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            text: root.cfg_Image
            placeholderText: "No image (gradient)"
            onEditingFinished: root.cfg_Image = text
        }
        QQC2.Button {
            icon.name: "document-open"
            text: "Browse…"
            onClicked: fileDialog.open()
        }
        QQC2.Button {
            icon.name: "edit-clear"
            QQC2.ToolTip.text: "Use plain gradient"
            QQC2.ToolTip.visible: hovered
            onClicked: root.cfg_Image = ""
        }
    }

    RowLayout {
        Kirigami.FormData.label: "Dim background:"
        QQC2.Slider {
            id: dimSlider
            from: 0
            to: 80
            stepSize: 5
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }
        QQC2.Label {
            text: dimSlider.value + "%"
        }
    }

    QQC2.ComboBox {
        id: positionBox
        Kirigami.FormData.label: "Position:"
        model: ["Top left", "Left", "Bottom left", "Top right", "Right", "Bottom right"]
    }

    QQC2.CheckBox {
        id: englishBox
        Kirigami.FormData.label: "Display:"
        text: "English prayer names"
    }

    QQC2.CheckBox {
        id: use12hBox
        text: "12-hour times"
    }

    QQC2.CheckBox {
        id: notifyBox
        Kirigami.FormData.label: "Notifications:"
        text: "Ask whether I have prayed"
    }

    RowLayout {
        Kirigami.FormData.label: "Remind every:"
        enabled: notifyBox.checked
        QQC2.SpinBox {
            id: remindBox
            from: 5
            to: 240
            stepSize: 5
        }
        QQC2.Label {
            text: "minutes, until marked done or the prayer time ends"
        }
    }

    FileDialog {
        id: fileDialog
        title: "Choose background image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif *.svg)"]
        onAccepted: root.cfg_Image = selectedFile.toString()
    }
}

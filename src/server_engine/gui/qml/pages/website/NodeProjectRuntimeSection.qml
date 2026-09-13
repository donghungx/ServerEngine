import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root

    required property var pageRoot
    required property var addNodeProjectWindow

    property string nodeRuntimeStateText: Strings.t("stopped")
    property string nodeRuntimePidText: "-"
    property string nodeRuntimeCpuText: "-"
    property string nodeRuntimeRamText: "-"
    property string feedbackText: String(root.pageRoot && root.pageRoot.addNodeProjectFeedback ? root.pageRoot.addNodeProjectFeedback : "")
    property bool feedbackVisible: feedbackText.length > 0

    readonly property bool nodeRuntimeRunning: String(nodeRuntimeStateText || "").toLowerCase() === "running"

    onFeedbackTextChanged: {
        if (feedbackText.length > 0) {
            feedbackVisible = true
            feedbackHideTimer.restart()
        } else {
            feedbackVisible = false
            feedbackHideTimer.stop()
        }
    }

    function setRuntimeState(currentState) {
        var state = currentState || ({})
        nodeRuntimeStateText = String(state.state || "Stopped")
        nodeRuntimePidText = String(state.pid || "-")
        nodeRuntimeCpuText = String(state.cpu || "-")
        nodeRuntimeRamText = String(state.ram || "-")
    }

    Timer {
        id: feedbackHideTimer
        interval: 5000
        repeat: false
        onTriggered: root.feedbackVisible = false
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Label { text: Strings.t("status"); color: Theme.muted }
                Label { text: root.nodeRuntimeStateText; color: Theme.text; font.weight: Font.DemiBold }
                Label { text: Strings.t("pid"); color: Theme.muted }
                Label { text: root.nodeRuntimePidText; color: Theme.text }
                Label { text: Strings.t("cpu"); color: Theme.muted }
                Label { text: root.nodeRuntimeCpuText; color: Theme.text }
                Label { text: Strings.t("ram"); color: Theme.muted }
                Label { text: root.nodeRuntimeRamText; color: Theme.text }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                textFormat: Text.RichText
                wrapMode: Text.WordWrap
                color: Theme.muted
                font.pixelSize: 13
                text: "<ul>"
                    + "<li><b>Status</b>: whether the Node runtime is running or stopped.</li>"
                    + "<li><b>PID</b>: the process ID assigned by the operating system.</li>"
                    + "<li><b>CPU</b>: how much processor time the runtime is using.</li>"
                    + "<li><b>RAM</b>: how much memory the runtime is using right now.</li>"
                    + "</ul>"
            }
        }

        footerLeft: Text {
            visible: root.feedbackVisible && root.feedbackText.length > 0
            text: root.feedbackText
            color: root.pageRoot && root.pageRoot.addNodeProjectFeedbackError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                visible: !root.addNodeProjectWindow.nodeRuntimeRunning
                text: Strings.t("start")
                enabled: !root.addNodeProjectWindow.nodeRuntimeActionBusy
                onClicked: root.addNodeProjectWindow.invokeNodeRuntimeAction("start")
            }
            Components.AppButton {
                visible: root.addNodeProjectWindow.nodeRuntimeRunning
                text: Strings.t("stop")
                enabled: !root.addNodeProjectWindow.nodeRuntimeActionBusy
                onClicked: root.addNodeProjectWindow.invokeNodeRuntimeAction("stop")
            }
            Components.AppButton {
                text: Strings.t("restart")
                enabled: !root.addNodeProjectWindow.nodeRuntimeActionBusy
                onClicked: root.addNodeProjectWindow.invokeNodeRuntimeAction("restart")
            }
            Components.AppButton {
                text: Strings.t("refresh")
                enabled: !root.addNodeProjectWindow.nodeRuntimeActionBusy
                onClicked: root.addNodeProjectWindow.refreshNodeRuntime()
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var phpRuntime: ({})
    property var dashboardBridge
    property string infoContent: ""
    property string feedbackText: ""
    property bool feedbackIsError: false
    property bool loading: false

    Layout.fillWidth: true
    Layout.fillHeight: true

    function loadPhpInfo() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            infoContent = ""
            feedbackText = "PHP runtime version is missing."
            feedbackIsError = true
            loading = false
            return
        }
        loading = true
        feedbackText = "Loading phpinfo..."
        feedbackIsError = false
        dashboardBridge.requestPhpRuntimePhpInfo(phpRuntime.version)
    }

    onPhpRuntimeChanged: loadPhpInfo()
    Component.onCompleted: loadPhpInfo()

    Connections {
        target: dashboardBridge
        ignoreUnknownSignals: true

        function onPhpInfoReady(version, ok, message, content) {
            if (!root.phpRuntime || String(root.phpRuntime.version) !== String(version)) {
                return
            }
            root.loading = false
            root.infoContent = String(content || "")
            root.feedbackText = String(message || "")
            root.feedbackIsError = !Boolean(ok)
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Components.AppScrollEditor {
                    id: phpInfoText
                    anchors.fill: parent
                    readOnly: true
                    text: root.infoContent
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    textColor: Theme.text
                    fontFamily: "Menlo"
                    fontPixelSize: 12
                    selectByMouse: true
                }

                Label {
                    anchors.centerIn: parent
                    visible: !root.loading && root.infoContent.length === 0
                    text: Strings.t("no.phpinfo.output.available")
                    color: Theme.muted
                    font.pixelSize: 13
                }
            }
        }

        footerLeft: Text {
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackIsError ? "#b33a3a" : "#2f7d32"
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            width: parent.width
        }

        footerRight: Components.AppButton {
            text: Strings.t("refresh")
            enabled: !root.loading
            onClicked: root.loadPhpInfo()
        }
    }
}




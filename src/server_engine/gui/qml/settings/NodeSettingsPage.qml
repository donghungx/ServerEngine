import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components" as Components
import "../theme"
import "../i18n"

Item {
    required property var bridge
    required property var window
    required property var appSettingsWindow
    property alias nodeDefaultVersionCombo: nodeDefaultVersionCombo
    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Components.SettingsLabeledControl {
                title: Strings.t("default.node.version")
                description: "This version will be used automatically for new Node projects and terminal sessions."
                visible: bridge.nodeRuntimeVersions.length > 0

                Components.AppComboBox {
                    id: nodeDefaultVersionCombo
                    width: 260
                    model: bridge.nodeRuntimeVersions
                }
            }

            Components.SettingsCheckableOption {
                id: nodeAutoInstallDependenciesCheck
                title: "Auto-install dependencies"
                description: "Run npm install automatically when node_modules is missing."
                checked: appSettingsWindow.nodeAutoInstallDependenciesDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.nodeAutoInstallDependenciesDraft = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                id: nodeAllowNetworkAccessCheck
                title: "Allow network access"
                description: "Allow other devices on the network to access the running Node app."
                checked: appSettingsWindow.nodeAllowNetworkAccessDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.nodeAllowNetworkAccessDraft = nextChecked
                }
            }

            Text {
                visible: bridge.nodeRuntimeVersions.length === 0
                Layout.fillWidth: true
                Layout.leftMargin: 216
                text: Strings.t("no.node.runtime.installed.a.href.install.node.install.one.in.runtime.manager.a")
                textFormat: Text.RichText
                linkColor: Theme.accentStrong
                color: Theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                onLinkActivated: function(_link) {
                    window.appSettingsSection = "Runtime"
                    appSettingsWindow.runtimeManagerService = "node"
                    appSettingsWindow.refreshRuntimeManager()
                    appSettingsWindow.applySectionWindowHeight(window.appSettingsSection)
                }
            }

            Components.SettingsLabeledControl {
                title: Strings.t("logs")
                description: "Open the folder where Node project logs are stored."

                Components.AppButton {
                    text: Strings.t("open.logs.folder")
                    onClicked: bridge.openRuntimePath("logs")
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: appSettingsWindow.scopedAppSettingsMessage
            color: bridge.appSettingsError ? Theme.danger : Theme.success
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: parent.width
            verticalAlignment: Text.AlignVCenter
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                accent: true
                text: Strings.t("settings.appearance.save")
                enabled: bridge.nodeRuntimeVersions.length > 0
                onClicked: bridge.saveNodeAppSettings(nodeDefaultVersionCombo.currentText)
            }
        }
    }
}

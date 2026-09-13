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
    property alias databaseEngineCombo: databaseEngineCombo
    property alias runtimeCombo: runtimeCombo
    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Components.SettingsLabeledControl {
                    title: Strings.t("database.engine")
                    description: "Choose which database engine this project will use for local development."

                    Components.AppComboBox {
                        id: databaseEngineCombo
                        width: 240
                        model: ["mariadb", "mysql"]
                        onCurrentTextChanged: {
                            appSettingsWindow.runtimeModel = bridge.databaseRuntimesByEngine(currentText)
                            runtimeCombo.currentIndex = appSettingsWindow.findRuntimeIndex(bridge.settingsDatabaseRuntime)
                        }
                    }
                }

                Components.SettingsLabeledControl {
                    title: Strings.t("database.runtime")
                    description: "Select the installed database version to run. Only available runtimes for the chosen engine are shown here."

                    Components.AppComboBox {
                        id: runtimeCombo
                        width: 240
                        model: appSettingsWindow.runtimeModel
                        textRole: "label"
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16

                Components.SettingsCheckableOption {
                    id: databaseRestartAfterChangesCheck
                    title: "Restart after changes"
                    description: "Restart the active database runtime automatically after saving changes."
                    checked: appSettingsWindow.databaseRestartAfterChangesDraft
                    onToggled: function(nextChecked) {
                        appSettingsWindow.databaseRestartAfterChangesDraft = nextChecked
                    }
                }

                Components.SettingsCheckableOption {
                    id: databaseAllowNetworkAccessCheck
                    title: "Allow network access"
                    description: "Allow other machines on your network to connect to this database runtime."
                    checked: appSettingsWindow.databaseAllowNetworkAccessDraft
                    onToggled: function(nextChecked) {
                        appSettingsWindow.databaseAllowNetworkAccessDraft = nextChecked
                    }
                }

                Components.SettingsCheckableOption {
                    id: databaseUseRandomFreePortIfBusyCheck
                    title: "Use random free port if busy"
                    description: "Automatically pick another unused port if the selected database port is already taken."
                    checked: appSettingsWindow.databaseUseRandomFreePortIfBusyDraft
                    onToggled: function(nextChecked) {
                        appSettingsWindow.databaseUseRandomFreePortIfBusyDraft = nextChecked
                    }
                }

                Components.SettingsCheckableOption {
                    id: databaseSnapshotBeforeImportCheck
                    title: "Snapshot before import"
                    description: "Create a snapshot before importing data so you can roll back if the import fails."
                    checked: appSettingsWindow.databaseSnapshotBeforeImportDraft
                    onToggled: function(nextChecked) {
                        appSettingsWindow.databaseSnapshotBeforeImportDraft = nextChecked
                    }
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
                onClicked: {
                    var runtimeId = runtimeCombo.currentIndex >= 0 && appSettingsWindow.runtimeModel.length > runtimeCombo.currentIndex
                        ? appSettingsWindow.runtimeModel[runtimeCombo.currentIndex].id
                        : ""
                    bridge.saveDatabaseAppSettings(databaseEngineCombo.currentText, runtimeId)
                }
            }
        }
    }
}

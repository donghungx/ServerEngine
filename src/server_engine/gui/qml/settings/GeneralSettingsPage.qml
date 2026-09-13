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
    required property var generateFolderDialog
    property bool immediateApplyGeneral: Qt.platform.os === "osx" || Qt.platform.os === "linux"
    property alias autoStartStackCheck: autoStartStackCheck
    property alias defaultProjectFolderField: defaultProjectFolderField
    property alias environmentRootField: environmentRootField
    Layout.fillWidth: true
    Layout.fillHeight: true

    function updateModes() {
        return [
            "Automatically download and install",
            "Just notify if there are updates",
            "Don't check for updates"
        ]
    }

    function notificationModes() {
        return [
            "Important only",
            "All events"
        ]
    }

    function logModes() {
        return [
            "Never delete logs",
            "Clear logs before startup",
            "Rotate when log size exceeds 10 MB",
            "Rotate when logs are older than 7 days"
        ]
    }

    function hasGeneralSettingsChanges() {
        return autoStartStackCheck.checked !== !!bridge.settingsAutoStartStack
            || String(environmentRootField.text || "") !== String(bridge.settingsEnvironmentRoot || "")
            || String(defaultProjectFolderField.text || "") !== String(bridge.settingsDefaultProjectFolder || "")
    }

    function saveGeneralSettings() {
        if (!hasGeneralSettingsChanges()) {
            return false
        }
        bridge.saveGeneralAppSettings(
            autoStartStackCheck.checked,
            bridge.settingsAutoUpdateHosts,
            bridge.settingsEnableSimulatedProcesses,
            environmentRootField.text,
            defaultProjectFolderField.text
        )
        return true
    }

    function queueGeneralSettingsSave() {
        if (immediateApplyGeneral) {
            generalSaveTimer.restart()
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            Components.SettingsLabeledControl {
                title: "Updates"
                description: "Choose how Server Engine checks for updates when the app starts."

                Components.AppComboBox {
                    id: updateModeCombo
                    model: updateModes()
                    currentIndex: appSettingsWindow.safeComboIndex(updateModeCombo, appSettingsWindow.optionsUpdateModeDraft)
                    onCurrentIndexChanged: {
                        appSettingsWindow.optionsUpdateModeDraft = currentText
                    }
                }
            }

            Components.SettingsLabeledInput {
                title: Strings.t("default.project.folder")
                description: "Choose where new local projects are created by default."

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Components.AppTextField {
                        id: defaultProjectFolderField
                        Layout.fillWidth: true
                        readOnly: true
                        placeholderText: Strings.t("serverengine")
                    }

                    Components.AppButton {
                        text: Strings.t("browse")
                        implicitWidth: 96
                        onClicked: generateFolderDialog.open()
                    }
                }
            }

            Components.SettingsLabeledInput {
                title: Strings.t("environment.root.path")
                description: "This is the base path used by Server Engine for its local environment."

                Text {
                    id: environmentRootField
                    Layout.fillWidth: true
                    text: "~/Library/Application Support/Server Engine"
                    color: Theme.text
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Components.SettingsCheckableOption {
                id: startWithSystemCheck
                title: "Start with System"
                description: "Launch Server Engine automatically when macOS starts."
                checked: appSettingsWindow.optionsStartWithSystemDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.optionsStartWithSystemDraft = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                id: autoStartStackCheck
                title: Strings.t("auto.start.stack.on.app.launch")
                description: "Start the local stack automatically when the app opens."
                checked: false
                onToggled: function(nextChecked) {
                    queueGeneralSettingsSave()
                }
            }


            Components.SettingsCheckableOption {
                id: showMenuBarCheck
                title: "Show Server Engine in Menu Bar"
                description: "Keep Server Engine available from the menu bar at all times."
                checked: appSettingsWindow.optionsShowInMenuBarDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.optionsShowInMenuBarDraft = nextChecked
                    if (bridge && bridge.setSystemTrayVisible) {
                        bridge.setSystemTrayVisible(nextChecked)
                    }
                }
            }

            Components.SettingsCheckableOption {
                id: promptBeforeQuitCheck
                title: "Prompt before Quitting"
                description: "Ask for confirmation before closing the app."
                checked: appSettingsWindow.optionsPromptBeforeQuitDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.optionsPromptBeforeQuitDraft = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                id: stopServersOnQuitCheck
                title: "Stop Servers on Quit"
                description: "Stop active servers when Server Engine closes."
                checked: appSettingsWindow.optionsStopServersOnQuitDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.optionsStopServersOnQuitDraft = nextChecked
                }
            }

            Components.SettingsLabeledControl {
                title: "Notifications"
                description: "Limit notifications to critical events like failures, port conflicts, and runtime errors."

                Components.AppComboBox {
                    id: notificationModeCombo
                    model: notificationModes()
                    currentIndex: appSettingsWindow.safeComboIndex(notificationModeCombo, appSettingsWindow.optionsNotificationModeDraft)
                    onCurrentIndexChanged: {
                        appSettingsWindow.optionsNotificationModeDraft = currentText
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Log"
                description: "Choose how Server Engine handles log files."

                Components.AppComboBox {
                    id: logModeCombo
                    model: logModes()
                    currentIndex: appSettingsWindow.safeComboIndex(logModeCombo, appSettingsWindow.optionsLogModeDraft)
                    onCurrentIndexChanged: {
                        appSettingsWindow.optionsLogModeDraft = currentText
                    }
                }
            }

            Components.SettingsCheckableOption {
                id: anonymousUsageCheck
                title: "Send Anonymous Usage Data"
                description: "Help improve Server Engine by sharing anonymous usage data."
                checked: appSettingsWindow.optionsSendAnonymousUsageDataDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.optionsSendAnonymousUsageDataDraft = nextChecked
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
            visible: !immediateApplyGeneral && text.length > 0
        }

        footerRight: Row {
            spacing: 8
            visible: !immediateApplyGeneral

            Components.AppButton {
                accent: true
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    saveGeneralSettings()
                }
            }
        }

        Timer {
            id: generalSaveTimer
            interval: 250
            repeat: false
            onTriggered: saveGeneralSettings()
        }
    }
}

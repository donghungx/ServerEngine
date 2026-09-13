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
    property bool immediateApplyAppearance: Qt.platform.os === "osx" || Qt.platform.os === "linux"

    property alias appearanceThemeCombo: appearanceThemeCombo
    property alias appearanceLanguageCombo: appearanceLanguageCombo
    property var appearanceLanguageModel: [
        { label: Strings.t("english"), value: "en" },
        { label: "Deutsch", value: "de" },
        { label: Strings.t("vietnamese"), value: "vi" },
        { label: Strings.t("chinese.simplified"), value: "zh-hans" },
        { label: Strings.t("chinese.traditional"), value: "zh-hant" }
    ]

    function applyAppearanceSettings() {
        if (!appSettingsWindow.appearanceSettingsReady) {
            return
        }
        if (!hasAppearanceSettingsChanges()) {
            return false
        }
        var themeItem = appearanceThemeCombo.model[appearanceThemeCombo.currentIndex]
        var languageItem = appearanceLanguageCombo.model[appearanceLanguageCombo.currentIndex]
        var themeValue = String((themeItem && themeItem.value) || "system")
        var languageValue = String((languageItem && languageItem.value) || "en")
        var saved = bridge.saveAppearanceAppSettings(
            themeValue,
            appSettingsWindow.appearanceAccentDraft,
            languageValue
        )
        return saved
    }

    function hasAppearanceSettingsChanges() {
        var themeItem = appearanceThemeCombo.model[appearanceThemeCombo.currentIndex]
        var languageItem = appearanceLanguageCombo.model[appearanceLanguageCombo.currentIndex]
        var themeValue = String((themeItem && themeItem.value) || "system").toLowerCase()
        var languageValue = String((languageItem && languageItem.value) || "en").toLowerCase()
        return themeValue !== String(bridge.settingsAppearanceTheme || "system").toLowerCase()
            || languageValue !== String(bridge.settingsAppearanceLanguage || "en").toLowerCase()
            || String(appSettingsWindow.normalizeAccentColor(appSettingsWindow.appearanceAccentDraft)) !== String(bridge.settingsAppearanceAccentColor || "#007bff").toLowerCase()
    }

    function queueAppearanceSettingsSave() {
        if (immediateApplyAppearance && appSettingsWindow.appearanceSettingsReady) {
            appearanceSaveTimer.restart()
        }
    }

    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            Components.SettingsLabeledControl {
                title: Strings.t("settings.appearance.accentColor")
                titleWidth: 208

                Row {
                    spacing: 8

                    Repeater {
                        model: window.appearanceAccentColors

                        delegate: Rectangle {
                            id: accentSwatch
                            required property int index
                            property var accentItem: window.appearanceAccentColors[index]
                            property string accentColor: appSettingsWindow.normalizeAccentColor(accentItem.color)
                            property bool selected: appSettingsWindow.normalizeAccentColor(appSettingsWindow.appearanceAccentDraft) === accentColor
                            width: 24
                            height: 24
                            radius: 12
                            color: accentColor
                            border.color: selected ? Theme.text : Theme.border
                            border.width: selected ? 1 : 1

                            Rectangle {
                                anchors.centerIn: parent
                                width: 6
                                height: 6
                                radius: 3
                                visible: accentSwatch.selected
                                color: Theme.surface
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    appSettingsWindow.appearanceAccentDraft = accentSwatch.accentColor
                                    Theme.accent = accentSwatch.accentColor
                                    Theme.accentStrong = accentSwatch.accentColor
                                    queueAppearanceSettingsSave()
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Components.SettingsLabeledControl {
                    title: Strings.t("settings.appearance.language")
                    description: Strings.t("Choose the language used across the app interface.")

                    Components.AppComboBox {
                        id: appearanceLanguageCombo
                        width: 240
                        model: appearanceLanguageModel
                        textRole: "label"
                        onCurrentIndexChanged: {
                            if (appSettingsWindow.appearanceSettingsReady && immediateApplyAppearance) {
                                var item = appearanceLanguageModel[appearanceLanguageCombo.currentIndex]
                                var nextLanguage = String((item && item.value) || "en").toLowerCase()
                                Strings.language = nextLanguage
                                window.currentLanguage = nextLanguage
                            }
                            queueAppearanceSettingsSave()
                        }
                    }
                }

                Components.SettingsLabeledControl {
                    title: Strings.t("settings.appearance.themeMode")
                    description: Strings.t("Choose whether the UI follows the system theme or uses a fixed light or dark mode.")

                    Components.AppComboBox {
                        id: appearanceThemeCombo
                        width: 240
                        model: [
                            { label: Strings.t("sync.with.os"), value: "system" },
                            { label: Strings.t("light"), value: "light" },
                            { label: Strings.t("dark"), value: "dark" }
                        ]
                        textRole: "label"
                        onCurrentIndexChanged: {
                            if (appSettingsWindow.appearanceSettingsReady && immediateApplyAppearance) {
                                var themeItem = appearanceThemeCombo.model[appearanceThemeCombo.currentIndex]
                                var nextTheme = String((themeItem && themeItem.value) || "system").toLowerCase()
                                window.currentThemeMode = nextTheme
                            }
                            queueAppearanceSettingsSave()
                        }
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
            visible: Qt.platform.os === "windows" && text.length > 0
        }

        footerRight: Row {
            spacing: 8
            visible: Qt.platform.os === "windows"

            Components.AppButton {
                accent: true
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    appSettingsWindow.appearanceSettingsReady = true
                    applyAppearanceSettings()
                }
            }
        }
    }

    Timer {
        id: appearanceSaveTimer
        interval: 250
        repeat: false
        onTriggered: applyAppearanceSettings()
    }
}

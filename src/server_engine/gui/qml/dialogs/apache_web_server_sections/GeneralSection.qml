import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    function apacheGeneralLogLevelIndex(level) {
        switch (String(level || "").toLowerCase()) {
        case "emerg":
            return 0
        case "alert":
            return 1
        case "crit":
            return 2
        case "error":
            return 3
        case "notice":
            return 5
        case "info":
            return 6
        case "debug":
            return 7
        default:
            return 4
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

                ColumnLayout {
                    width: parent.width
                    spacing: 16




                        Components.SettingsLabeledControl {
                            title: "Startup log level"
                            description: "Choose how much detail Apache prints while starting up."

                            Components.AppComboBox {
                                width: 320
                                model: [
                                    { label: "Emerg - emergency only", value: "emerg" },
                                    { label: "Alert - immediate attention", value: "alert" },
                                    { label: "Crit - critical issues", value: "crit" },
                                    { label: "Error - errors only", value: "error" },
                                    { label: "Warn - warnings and errors", value: "warn" },
                                    { label: "Notice - normal startup messages", value: "notice" },
                                    { label: "Info - informational detail", value: "info" },
                                    { label: "Debug - very verbose startup output", value: "debug" }
                                ]
                                textRole: "label"
                                currentIndex: apacheGeneralLogLevelIndex(runtimeWindow.apacheGeneralLogLevelDraft)
                                onCurrentIndexChanged: {
                                    var item = model[currentIndex]
                                    runtimeWindow.apacheGeneralLogLevelDraft = String((item && item.value) || "warn")
                                }
                            }
                        }

                        Components.SettingsLabeledControl {
                            title: "Custom define flags"
                            description: "Add one or more Apache -D define names, comma separated."

                            Components.AppTextField {
                                width: 360
                                text: runtimeWindow.apacheGeneralDefineFlagsDraft
                                placeholderText: "SSL,PROXY"
                                onTextChanged: runtimeWindow.apacheGeneralDefineFlagsDraft = text
                            }
                        }


                        Components.SettingsCheckableOption {
                            title: "Syntax check"
                            description: "Run Apache in test mode instead of starting the server."
                            checked: runtimeWindow.apacheGeneralSyntaxCheckDraft
                            onToggled: function(nextChecked) {
                                runtimeWindow.apacheGeneralSyntaxCheckDraft = nextChecked
                            }
                        }

                        Components.SettingsCheckableOption {
                            title: "Debug mode"
                            description: "Run Apache in single-process debug mode with -X."
                            checked: runtimeWindow.apacheGeneralDebugModeDraft
                            onToggled: function(nextChecked) {
                                runtimeWindow.apacheGeneralDebugModeDraft = nextChecked
                            }
                        }

                        Components.SettingsCheckableOption {
                            title: "Skip DocumentRoot check"
                            description: "Start Apache even if the DocumentRoot path is missing or unavailable."
                            checked: runtimeWindow.apacheGeneralSkipDocumentRootCheckDraft
                            onToggled: function(nextChecked) {
                                runtimeWindow.apacheGeneralSkipDocumentRootCheckDraft = nextChecked
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                }


}

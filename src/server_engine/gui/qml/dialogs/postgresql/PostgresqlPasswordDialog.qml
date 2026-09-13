import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Window {
    property var root: ({})
    property var dashboardBridge: ({})

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (root && root.dashboardBridge) {
            return root.dashboardBridge
        }
        return ({})
    }

    id: postgresqlPasswordWindow
        visible: root.postgresqlPasswordPopupOpen
        width: 540
        height: 250
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("root.password")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null

        flags: Qt.Dialog
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (visible) {
                postgresqlPasswordInput.text = String(bridge().postgresqlPassword || "")
                root.postgresqlPasswordFeedback = ""
                root.postgresqlPasswordFeedbackError = false
                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
            } else {
                root.postgresqlPasswordPopupOpen = false
                postgresqlPasswordInput.text = ""
                root.postgresqlPasswordFeedback = ""
                root.postgresqlPasswordFeedbackError = false
                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
            }
        }

        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 24
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) {
                postgresqlPasswordWindow.startSystemMove()
                mouse.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                color: "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 88
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("root.password")
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 16
                spacing: 16

                Label {
                    text: Strings.t("review.the.current.stored.root.password.and.optionally.change.it.for.the.active")
                        + String(bridge().activePostgresqlRuntimeLabel || "PostgreSQL")
                        + " runtime."
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Components.AppTextField {
                    id: postgresqlPasswordInput
                    Layout.fillWidth: true
                    placeholderText: Strings.t("root.password")
                    echoMode: TextInput.Normal
                }

                Label {
                    visible: text.length > 0

                    text: String(root.postgresqlPasswordFeedback || "").length > 0
                        ? root.postgresqlPasswordFeedback
                        : String(bridge().postgresqlRuntimeMessage || "")

                    color: String(root.postgresqlPasswordFeedback || "").length > 0
                        ? (root.postgresqlPasswordFeedbackError ? "#bb4d4d" : "#4aa94b")
                        : (bridge().postgresqlRuntimeError ? "#bb4d4d" : "#4aa94b")

                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    Components.AppButton {
                        text: Strings.t("cancel")

                        onClicked: root.postgresqlPasswordPopupOpen = false
                    }

                    Components.AppButton {
                        text: Strings.t("settings.appearance.save")
                        highlighted: true
                        textColor: "white"

                        onClicked: {
                            if (postgresqlPasswordInput.text.length === 0) {
                                root.postgresqlPasswordFeedback = "Password is required."
                                root.postgresqlPasswordFeedbackError = true
                            } else if (bridge().updatePostgresqlPassword && bridge().updatePostgresqlPassword(postgresqlPasswordInput.text)) {
                                root.postgresqlPasswordFeedback = ""
                                root.postgresqlPasswordFeedbackError = false
                                postgresqlPasswordInput.text = ""
                                root.postgresqlPasswordPopupOpen = false
                                bridge().refreshPostgresqlRuntime && bridge().refreshPostgresqlRuntime()
                            } else {
                                root.postgresqlPasswordFeedback = ""
                                root.postgresqlPasswordFeedbackError = false
                            }
                        }
                    }
                }
            }
        }
    }

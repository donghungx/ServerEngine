import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: aboutDialog

    required property var window

    visible: window.aboutDialogOpen
    width: 560
    height: 300
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("about.server.engine")
    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: window
    flags: Qt.Dialog | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (!visible) {
            window.aboutDialogOpen = false
        }
    }

    function aboutCopyText() {
        return "Server Engine\n"
            + "Version: " + window.aboutVersion + "\n"
            + "Build: " + window.aboutBuild + "\n"
            + "Runtime Mode: " + window.aboutRuntimeMode + "\n"
            + "License Mode: " + window.aboutLicenseMode + "\n"
            + "Python: " + window.aboutPythonVersion + "\n"
            + "App Support: " + window.aboutAppSupportPath + "\n"
            + "Website: https://ninacoder.top"
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: Strings.t("about.server.engine")
        moveWindow: aboutDialog
        contentMargins: 22
        contentSpacing: 18
        footerBottomMargin: 22

        TextEdit {
            id: clipboardBuffer
            visible: false
            text: ""
        }

        RowLayout {
            anchors.fill: parent
            spacing: 24

            Item {
                Layout.preferredWidth: 82
                Layout.fillHeight: true

                Image {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 8
                    width: 82
                    height: 82
                    source: "../icons/app-icon.png"
                    sourceSize.width: 512
                    sourceSize.height: 512
                    fillMode: Image.PreserveAspectFit
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: Strings.t("app.title")
                        color: Theme.text
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Strings.t("local.web.stack.manager.for.macos")
                        color: Theme.muted
                        font.pixelSize: 13
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { label: Strings.t("version"), value: window.aboutVersion },
                            { label: Strings.t("build"), value: window.aboutBuild },
                            { label: Strings.t("runtime.mode"), value: window.aboutRuntimeMode },
                            { label: Strings.t("license.mode"), value: window.aboutLicenseMode },
                        ]

                        delegate: RowLayout {
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 18

                            Text {
                                Layout.preferredWidth: 110
                                text: modelData.label
                                color: Theme.muted
                                font.pixelSize: 13
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.value
                                color: Theme.text
                                font.pixelSize: 13
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }

                ColumnLayout {
                    Text {
                        text: 'Copyright © 2026 <font color="' + Theme.accentStrong + '">ninacoder.top</font>.'
                        color: Theme.muted
                        font.pixelSize: 12
                        textFormat: Text.RichText

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally("https://ninacoder.top")
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        footerRight: Row {
            spacing: 10

            Components.AppButton {
                text: Strings.t("close")
                onClicked: window.aboutDialogOpen = false
            }

            Components.AppButton {
                text: Strings.t("copy.and.close")
                highlighted: true
                onClicked: {
                    clipboardBuffer.text = aboutCopyText()
                    clipboardBuffer.forceActiveFocus()
                    clipboardBuffer.selectAll()
                    clipboardBuffer.copy()
                    window.aboutDialogOpen = false
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import "../components" as Components
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    required property string pageName
    required property string description

    Column {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 22

        Text {
            text: pageName
            color: Theme.text
            font.pixelSize: 36
            font.weight: Font.Bold
        }

        Text {
            text: description
            color: Theme.muted
            font.pixelSize: 16
            wrapMode: Text.WordWrap
            width: 620
        }

        Row {
            spacing: 18

            Repeater {
                model: 3

                delegate: Item {
                    id: placeholderItem
                    required property int index
                    width: 250
                    height: 180

                    Components.ShellCard {
                        anchors.fill: parent

                        Column {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 12

                            Rectangle {
                                width: 48
                                height: 48
                                radius: Theme.radius
                                color: Theme.accentSoft

                                Text {
                                    anchors.centerIn: parent
                                    text: String(placeholderItem.index + 1)
                                    color: Theme.accentStrong
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }

                            Text {
                                text: Strings.t("module.placeholder")
                                color: Theme.text
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: Strings.t("this.page.shell.is.prepared.for.real.controls.and.data.binding")
                                width: parent.width - 10
                                color: Theme.muted
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}

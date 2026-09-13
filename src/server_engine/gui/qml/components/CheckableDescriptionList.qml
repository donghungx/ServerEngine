import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "." as Components

Item {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: true
    property string headerLeftText: "Name"
    property string headerRightText: "Description"
    property var model: []
    property string titleRole: "name"
    property string descriptionRole: "description"
    property string checkedRole: "enabled"
    property int checkboxColumnWidth: 32
    property int titleColumnWidth: 220
    property int descriptionColumnWidth: 0

    signal toggled(int index, bool checked)

    implicitWidth: 300
    implicitHeight: 300

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 0

                        Item {
                            Layout.preferredWidth: root.checkboxColumnWidth
                            Layout.fillHeight: true
                        }

                        Text {
                            Layout.preferredWidth: root.titleColumnWidth
                            Layout.minimumWidth: root.titleColumnWidth
                            Layout.maximumWidth: root.titleColumnWidth
                            text: root.headerLeftText
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            width: 1
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: Theme.border
                        }

                        Text {
                            Layout.preferredWidth: root.descriptionColumnWidth > 0 ? root.descriptionColumnWidth : 0
                            Layout.minimumWidth: root.descriptionColumnWidth > 0 ? root.descriptionColumnWidth : 0
                            Layout.maximumWidth: root.descriptionColumnWidth > 0 ? root.descriptionColumnWidth : Number.POSITIVE_INFINITY
                            Layout.fillWidth: root.descriptionColumnWidth <= 0
                            Layout.leftMargin: 12
                            text: root.headerRightText
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                }

                Components.AppScrollArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clipContent: true

                    Column {
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: root.model

                            delegate: Components.CheckableDescriptionRow {
                                required property int index
                                property var rowData: root.model[index]
                                alternating: index % 2 === 0
                                checked: !!rowData[root.checkedRole]
                                checkboxColumnWidth: root.checkboxColumnWidth
                                titleColumnWidth: root.titleColumnWidth
                                descriptionColumnWidth: root.descriptionColumnWidth
                                title: String(rowData[root.titleRole] || "")
                                description: String(rowData[root.descriptionRole] || "")
                                onToggled: function(nextChecked) {
                                    rowData[root.checkedRole] = nextChecked
                                    root.model[index] = rowData
                                    root.toggled(index, nextChecked)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

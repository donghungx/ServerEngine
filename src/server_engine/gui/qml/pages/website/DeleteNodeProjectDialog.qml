import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Window {
    id: deleteNodeProjectDialog

    required property var root
    required property var dashboardBridge
    readonly property var bridge: dashboardBridge ? dashboardBridge : (root && root.dashboardBridge ? root.dashboardBridge : null)

    visible: false

    width: 460
    height: 220

    minimumWidth: width
    maximumWidth: width

    minimumHeight: height
    maximumHeight: height

    title: Strings.t("remove.node.project")

    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: root.Window.window

    flags: Qt.Dialog
        | Qt.CustomizeWindowHint
        | Qt.WindowTitleHint
        | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (!visible) {
            root.nodeProjectToDelete = ({})
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
            deleteNodeProjectDialog.startSystemMove()
            mouse.accepted = true
        }
    }

    ColumnLayout {
        spacing: 16
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 88
                anchors.verticalCenter: parent.verticalCenter
                text: Strings.t("remove.node.project")
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 40
        anchors.margins: 16
        spacing: 16

        Label {
            text: Strings.t("remove.this.node.project.from.the.app")
            color: Theme.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Label {
            text: root.nodeProjectToDelete && root.nodeProjectToDelete.domain
                ? String(root.nodeProjectToDelete.domain)
                : ""
            color: Theme.text
            wrapMode: Text.WordWrap
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
                onClicked: {
                    deleteNodeProjectDialog.visible = false
                    root.nodeProjectToDelete = ({})
                }
            }

            Components.AppButton {
                text: Strings.t("remove")
                highlighted: true
                textColor: "white"
                enabled: !!root.nodeProjectToDelete
                    && String(root.nodeProjectToDelete.id || "").length > 0

                onClicked: {
                    if (!root.nodeProjectToDelete || !root.nodeProjectToDelete.id) {
                        deleteNodeProjectDialog.visible = false
                        return
                    }

                    var nodeId = String(root.nodeProjectToDelete.id)
                    var state = deleteNodeProjectDialog.bridge && deleteNodeProjectDialog.bridge.nodeProjectServiceState
                        ? deleteNodeProjectDialog.bridge.nodeProjectServiceState(nodeId)
                        : ({ state: "Stopped", running: false })
                    var isRunning = String(state.state || "").toLowerCase() === "running"
                    if (isRunning) {
                        root.addNodeProjectFeedback = "Stop the Node runtime before removing this project."
                        root.addNodeProjectFeedbackError = true
                        deleteNodeProjectDialog.visible = false
                        root.nodeProjectToDelete = ({})
                        return
                    }

                    var ok = deleteNodeProjectDialog.bridge && deleteNodeProjectDialog.bridge.deleteNodeProject
                        ? deleteNodeProjectDialog.bridge.deleteNodeProject(nodeId)
                        : false
                    if (!ok) {
                        root.addNodeProjectFeedback = deleteNodeProjectDialog.bridge ? deleteNodeProjectDialog.bridge.lastOperationMessage : "Unable to remove Node project."
                        root.addNodeProjectFeedbackError = true
                    } else {
                        root.addNodeProjectFeedback = ""
                        root.addNodeProjectFeedbackError = false
                    }

                    deleteNodeProjectDialog.visible = false
                    root.nodeProjectToDelete = ({})
                }
            }
        }
    }
}

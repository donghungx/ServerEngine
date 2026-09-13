import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "../theme"
import "../i18n"

Item {
    id: root

    property string label: ""
    property string status: ""
    property int phaseIndex: -1
    property int currentPhaseIndex: -1

    implicitWidth: parent ? parent.width : 200
    implicitHeight: 20
    width: implicitWidth
    height: implicitHeight

    readonly property bool usePhaseOrdering: phaseIndex >= 0 && currentPhaseIndex >= 0
    readonly property bool isInstalling: usePhaseOrdering
        ? phaseIndex === currentPhaseIndex
        : String(status || "") === "installing"
    readonly property bool isDone: usePhaseOrdering
        ? phaseIndex < currentPhaseIndex
        : String(status || "") === "done"
    readonly property bool isPending: usePhaseOrdering
        ? phaseIndex > currentPhaseIndex
        : !isInstalling && !isDone

    Row {
        anchors.fill: parent
        spacing: 8

        Loader {
            width: 16
            height: 16
            active: root.isInstalling
            visible: active
            sourceComponent: BusyIndicator {
                running: true
                width: 16
                height: 16
            }
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            visible: root.isDone
            color: Theme.success

            Image {
                id: checkIconSourceImage
                visible: false
                source: "../icons/lucide/check.svg"
                width: 12
                height: 12
                sourceSize.width: 24
                sourceSize.height: 24
                fillMode: Image.PreserveAspectFit
            }

            MultiEffect {
                visible: root.visible
                anchors.centerIn: parent
                width: 12
                height: 12
                source: checkIconSourceImage
                colorization: 1.0
                colorizationColor: "white"
                brightness: 1.0
            }
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            visible: root.isPending
            color: Theme.border
        }

        Text {
            text: root.label
            color: root.isDone ? Theme.text : Theme.muted
            font.pixelSize: 12
            width: parent.width - 40
            wrapMode: Text.WordWrap
        }
    }
}

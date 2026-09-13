import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../theme"
import "../components" as Components
import "../i18n"

Window {
    id: dialog
    color: Theme.surface
    flags: Qt.Dialog | Qt.WindowCloseButtonHint
    property bool lockSize: true
    minimumWidth: lockSize ? width : 0
    maximumWidth: lockSize ? width : 400
    minimumHeight: lockSize ? height : 0
    maximumHeight: lockSize ? height : 112
    property string heading: ""
    property string subtitle: ""
    property string confirmText: Strings.t("confirm")
    property string cancelText: Strings.t("cancel")
    property string feedbackText: ""
    property bool feedbackIsError: false
    property bool confirmEnabled: true
    property bool footerVisible: true
    property bool footerDividerVisible: true
    property bool bodyScrollable: true
    property bool bodyFillHeight: false
    property bool confirmVisible: true
    property bool cancelVisible: true
    property bool confirmButtonEnabled: true
    property bool cancelButtonEnabled: true
    property bool headerVisible: true
    property int contentMargins: 16
    property bool closeConfirmationEnabled: false

    signal confirmRequested()
    signal cancelRequested()
    signal closeRequested()

    default property alias body: bodyColumn.data

    modality: Qt.ApplicationModal

    onClosing: function(closeEvent) {
        if (dialog.closeConfirmationEnabled) {
            closeEvent.accepted = false
            dialog.closeRequested()
            return
        }
        cancelRequested()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        z: -1
    }

    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 32
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.ArrowCursor
        onPressed: function(mouse) {
            dialog.startSystemMove()
            mouse.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            visible: dialog.headerVisible
            Layout.fillWidth: true
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                color: "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 88
                    anchors.verticalCenter: parent.verticalCenter
                    text: dialog.heading
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            Label {
                visible: text.length > 0
                Layout.fillWidth: true
                leftPadding: dialog.contentMargins
                rightPadding: dialog.contentMargins
                text: dialog.subtitle
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: dialog.contentMargins
            spacing: 18

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: dialog.bodyFillHeight ? height : bodyColumn.implicitHeight
                clip: true
                interactive: dialog.bodyScrollable
                flickableDirection: Flickable.AutoFlickIfNeeded

                ColumnLayout {
                    id: bodyColumn
                    width: parent.width
                    height: dialog.bodyFillHeight ? parent.height : implicitHeight
                    spacing: 20
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
                visible: dialog.footerDividerVisible
            }

            Label {
                Layout.fillWidth: true
                visible: dialog.feedbackText.length > 0
                text: dialog.feedbackText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                color: dialog.feedbackIsError ? Theme.dialogFeedbackErrorText : Theme.dialogFeedbackSuccessText
                font.pixelSize: 13
                maximumLineCount: 1
            }

            RowLayout {
                Layout.fillWidth: true
                visible: dialog.footerVisible

                Item {
                    Layout.fillWidth: true
                }

                Components.AppButton {
                    height: 24
                    visible: dialog.cancelVisible
                    text: dialog.cancelText
                    enabled: dialog.cancelButtonEnabled
                    onClicked: dialog.cancelRequested()
                }

                Components.AppButton {
                    height: 24
                    visible: dialog.confirmVisible
                    text: dialog.confirmText
                    enabled: dialog.confirmEnabled && dialog.confirmButtonEnabled
                    onClicked: dialog.confirmRequested()
                }
            }
        }
    }

}

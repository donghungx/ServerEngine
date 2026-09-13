import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../theme"
import "../components" as Components
import "../i18n"

Window {
    id: alert

    width: 400
    height: 108

    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height

    color: Theme.surface
    flags: Qt.Dialog | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    property string heading: Strings.t("alert")
    property string message: ""
    property string buttonText: Strings.t("ok")
    property color messageColor: Theme.muted

    signal accepted()

    function showAlert(title, text) {
        heading = title
        message = text
        show()
        raise()
        requestActivate()
    }

    function showInfo(title, text) {
        heading = title
        message = text
        messageColor = Theme.muted
        show()
        raise()
        requestActivate()
    }

    function showSuccess(title, text) {
        heading = title
        message = text
        messageColor = Theme.muted
        show()
        raise()
        requestActivate()
    }

    function showError(title, text) {
        heading = title
        message = text
        messageColor = Theme.danger
        show()
        raise()
        requestActivate()
    }

    function openAlert(title, text) {
        showAlert(title, text)
    }

    function openInfo(title, text) {
        showInfo(title, text)
    }

    function openSuccess(title, text) {
        showSuccess(title, text)
    }

    function openError(title, text) {
        showError(title, text)
    }

    onClosing: function(closeEvent) {
        accepted()
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: alert.heading
        moveWindow: alert

        Text {
            anchors.fill: parent
            text: alert.message
            color: Theme.text
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }

        footerRight: Row {
            Components.AppButton {
                text: alert.buttonText

                onClicked: {
                    alert.accepted()
                    alert.close()
                }
            }
        }
    }
}

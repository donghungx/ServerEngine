import QtQuick
import QtQuick.Controls
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    Text {
        anchors.centerIn: parent
        text: Strings.t("section.not.available")
        color: Theme.muted
        font.pixelSize: 14
    }
}

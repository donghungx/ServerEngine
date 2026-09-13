import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    anchors.fill: parent

    Components.FileLogSection {
        anchors.fill: parent
        title: Strings.t("logs")
        description: Strings.t("read.the.latest.mailpit.runtime.log.output")
        emptyText: "No Mailpit log yet."
        logPathProvider: function() {
            return ""
        }
        logContentProvider: function(lines, tailMode) {
            return dashboardBridge && dashboardBridge.mailpitRuntimeLog
                ? String(dashboardBridge.mailpitRuntimeLog)
                : ""
        }
    }
}

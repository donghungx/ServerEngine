import QtQuick
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    Components.FileLogSection {
        anchors.fill: parent
        title: Strings.t("logs")
        description: "Read the latest Apache runtime log output."
        emptyText: "No Apache runtime log yet."
        logPathProvider: function() {
            return dashboardBridge ? dashboardBridge.apacheRuntimeLogPath : ""
        }
        logContentProvider: function(lines, tailMode) {
            return dashboardBridge
                ? dashboardBridge.readFileLogContent(dashboardBridge.apacheRuntimeLogPath, lines, tailMode)
                : ""
        }
    }
}

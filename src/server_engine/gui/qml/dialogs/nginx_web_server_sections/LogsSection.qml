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
        description: "Read the latest Nginx runtime log output."
        emptyText: "No Nginx runtime log yet."
        logPathProvider: function() {
            return ""
        }
        logContentProvider: function(lines, tailMode) {
            return dashboardBridge && dashboardBridge.nginxRuntimeLog
                ? String(dashboardBridge.nginxRuntimeLog)
                : ""
        }
    }
}

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
        description: Strings.t("read.the.latest.redis.runtime.log.output")
        emptyText: "No Redis runtime log yet."
        logPathProvider: function() {
            return ""
        }
        logContentProvider: function(lines, tailMode) {
            return dashboardBridge && dashboardBridge.redisRuntimeLog
                ? String(dashboardBridge.redisRuntimeLog)
                : ""
        }
    }
}

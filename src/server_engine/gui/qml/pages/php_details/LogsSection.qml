import QtQuick
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var phpRuntime: ({})
    property var dashboardBridge

    function loadLogs() {
        phpLogs.loadLogs()
    }

    Components.FileLogSection {
        id: phpLogs
        anchors.fill: parent
        title: root.phpRuntime && root.phpRuntime.version
            ? ("Logs - PHP " + root.phpRuntime.version)
            : "Logs"
        description: Strings.t("shows.the.runtime.log.for.the.selected.php.version")
        emptyText: "No log entries yet."
        logPathProvider: function() {
            if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
                return ""
            }
            return String(dashboardBridge.phpRuntimeLogPath(phpRuntime.version) || "")
        }
        logContentProvider: function(lines, tailMode) {
            if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
                return ""
            }
            var result = dashboardBridge.phpRuntimeRelatedLog(phpRuntime.version, lines)
            return String(result.content || "")
        }
        openLogPathHandler: function(path) {
            if (dashboardBridge) {
                dashboardBridge.revealInFinder(path)
            }
        }
    }
}

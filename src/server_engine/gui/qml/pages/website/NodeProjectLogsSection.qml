import QtQuick
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    property string projectId: ""

    function loadLogs() {
        nodeProjectLogs.loadLogs()
    }

    Components.FileLogSection {
        id: nodeProjectLogs
        anchors.fill: parent
        title: Strings.t("logs")
        description: "Read the latest Node project runtime log output."
        emptyText: "No Node project runtime log yet."
        logPathProvider: function() {
            var currentProjectId = projectId ? String(projectId) : ""
            if (!dashboardBridge || currentProjectId.length === 0) {
                return ""
            }
            return dashboardBridge.nodeProjectServiceLogPath(currentProjectId)
        }
        logContentProvider: function(lines, tailMode) {
            var currentProjectId = projectId ? String(projectId) : ""
            if (!dashboardBridge || currentProjectId.length === 0) {
                return ""
            }
            return dashboardBridge.readFileLogContent(dashboardBridge.nodeProjectServiceLogPath(currentProjectId), lines, tailMode)
        }
    }
}

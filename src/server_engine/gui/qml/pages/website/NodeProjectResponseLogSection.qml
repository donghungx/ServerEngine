import QtQuick
import QtQuick.Controls
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property string projectId: ""

    function loadLogs() {
        nodeProjectResponseLogs.loadLogs()
    }

    Components.FileLogSection {
        id: nodeProjectResponseLogs
        anchors.fill: parent
        title: Strings.t("response.log")
        description: "Read the web server access log for this Node project."
        emptyText: "No Node project response log yet."
        logPathProvider: function() {
            var currentProjectId = projectId ? String(projectId) : ""
            if (!dashboardBridge || currentProjectId.length === 0) {
                return ""
            }
            return dashboardBridge.nodeProjectResponseLogPath(currentProjectId)
        }
        logContentProvider: function(lines, tailMode) {
            var currentProjectId = projectId ? String(projectId) : ""
            if (!dashboardBridge || currentProjectId.length === 0) {
                return ""
            }
            return dashboardBridge.nodeProjectResponseLogContent(currentProjectId, lines)
        }
    }
}

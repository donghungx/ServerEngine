import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.platform as Native
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: tableRoot
    required property var pageRoot
    required property var dashboardBridge
    required property var editNodeProjectWindow
    required property var deleteNodeProjectDialog

    readonly property int nodeTableContentWidth: 1004
    readonly property int bodyHeight: Math.max(0, tableRoot.height - headerCard.height - 14)
    readonly property var bridge: tableRoot.pageRoot ? tableRoot.pageRoot.dashboardBridge : null
    readonly property bool nativeMenuIconsSupported: tableRoot.bridge && tableRoot.bridge.macOS26OrLater

    function projectIconFor(templateId) {
        var iconBase = tableRoot.pageRoot && tableRoot.pageRoot.qmlIconsBaseUrl ? String(tableRoot.pageRoot.qmlIconsBaseUrl) : ""
        switch (String(templateId || "existing").toLowerCase()) {
        case "react":
            return iconBase + "projects/react.svg"
        case "next":
            return iconBase + "projects/nextjs.svg"
        case "remix":
            return iconBase + "projects/remix.svg"
        case "vue":
            return iconBase + "projects/vue.svg"
        case "nuxt":
            return iconBase + "projects/nuxt.svg"
        case "svelte":
            return iconBase + "projects/svelte.svg"
        case "sveltekit":
            return iconBase + "projects/sveltekit.svg"
        case "express":
            return iconBase + "projects/express.svg"
        case "fastify":
            return iconBase + "projects/fastify.svg"
        case "nest":
            return iconBase + "projects/nestjs.svg"
        case "existing":
        default:
            return iconBase + "projects/existing-project.svg"
        }
    }

    anchors.fill: parent

    Rectangle {
        id: headerCard
        width: parent.width
        height: 40
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: Theme.border
        border.width: 1
        clip: true

        Flickable {
            id: tableHeaderFlick
            anchors.fill: parent
            contentWidth: tableRoot.nodeTableContentWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                width: tableRoot.nodeTableContentWidth
                height: parent.height
                spacing: 0

                Components.HeaderCell { label: ""; cellWidth: 54 }
                Components.HeaderCell { label: Strings.t("site.name"); cellWidth: 236 }
                Components.HeaderCell { label: Strings.t("status"); cellWidth: 126 }
                Components.HeaderCell { label: Strings.t("node"); cellWidth: 104 }
                Components.HeaderCell { label: Strings.t("ssl"); cellWidth: 70 }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerCard.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 14
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
        clip: true

        Components.AppScrollArea {
            anchors.fill: parent
            clipContent: true

            Item {
                width: parent.width
                height: Math.max(tableRoot.bodyHeight, nodeProjectList.visible ? nodeProjectList.contentHeight : emptyState.implicitHeight)
            
                ListView {
                    id: nodeProjectList
                    width: parent.width
                    height: contentHeight
                    implicitHeight: contentHeight
                    model: tableRoot.bridge ? (tableRoot.bridge.nodeProjectItems || []) : []
                    visible: count > 0
                    interactive: false
                    clip: true

                    delegate: Column {
                        required property int index
                        width: nodeProjectList.width
                        property var nodeItem: tableRoot.bridge ? (tableRoot.bridge.nodeProjectItems || [])[index] : ({})

                        Rectangle {
                            width: parent.width
                            height: 62
                            color: "transparent"

                            Flickable {
                                anchors.fill: parent
                                contentWidth: parent.width
                                contentHeight: parent.height
                                contentX: tableHeaderFlick.contentX
                                flickableDirection: Flickable.HorizontalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                onContentXChanged: tableHeaderFlick.contentX = contentX

                                RowLayout {
                                    width: parent.width
                                    height: parent.height
                                    spacing: 0

                                    Item {
                                        Layout.preferredWidth: 54
                                        Layout.fillHeight: true

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 36
                                            height: 36
                                            radius: width / 2
                                            color: Theme.accent

                                            Image {
                                                id: nodeTemplateIcon
                                                anchors.centerIn: parent
                                                width: 18
                                                height: 18
                                                visible: false
                                                source: tableRoot.projectIconFor(nodeItem.template_id)
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                            }

                                            MultiEffect {
                                                anchors.centerIn: parent
                                                width: 18
                                                height: 18
                                                source: nodeTemplateIcon
                                                colorization: 1.0
                                                colorizationColor: "white"
                                                brightness: 1.0
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.preferredWidth: 220
                                        Layout.fillHeight: true

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 3

                                            Text {
                                                text: nodeItem.domain
                                                color: Theme.accentStrong
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                                width: parent.width
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: nodeItem.project_path
                                                color: Theme.muted
                                                font.pixelSize: 12
                                                width: parent.width
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.preferredWidth: 120
                                        Layout.fillHeight: true

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: String(nodeItem.status || "").toLowerCase() === "running" ? "#4aa94b" : "#c86b6b"
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: nodeItem.status
                                                color: Theme.text
                                                font.pixelSize: 12
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.preferredWidth: 110
                                        Layout.fillHeight: true
                                        verticalAlignment: Text.AlignVCenter
                                        text: nodeItem.node_version
                                        color: Theme.text
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Text {
                                        Layout.preferredWidth: 70
                                        Layout.fillHeight: true
                                        verticalAlignment: Text.AlignVCenter
                                        text: nodeItem.ssl
                                        color: nodeItem.ssl === "On" ? "#4aa94b" : "#e29a33"
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    // Auto-fills the remaining empty space.
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }

                                    // Last column auto-fits its button content.
                                    Item {
                                        Layout.preferredWidth: actionsLayout.implicitWidth + 16
                                        Layout.minimumWidth: actionsLayout.implicitWidth + 16
                                        Layout.fillHeight: true

                                        RowLayout {
                                            id: actionsLayout
                                            anchors.centerIn: parent
                                            spacing: 8

                                            Components.QuickActionButton {
                                                text: Strings.t("open.site")
                                                iconSource: "../icons/lucide/external-link.svg"
                                                tooltip: Strings.t("open.site")
                                                onClicked: Qt.openUrlExternally(String(nodeItem.browse_url || ""))
                                            }

                                            Components.QuickActionButton {
                                                text: "Run with CLI"
                                                iconSource: "../icons/lucide/terminal.svg"
                                                tooltip: "Run with CLI"
                                                onClicked: tableRoot.pageRoot.requestNodeProjectCli(nodeItem)
                                            }

                                            Components.QuickActionButton {
                                                text: Strings.t("modify")
                                                iconSource: "../icons/lucide/settings.svg"
                                                onClicked: {
                                                    tableRoot.pageRoot.addNodeProjectFeedback = ""
                                                    tableRoot.pageRoot.addNodeProjectFeedbackError = false
                                                    tableRoot.pageRoot.addNodeProjectOpen = false
                                                    tableRoot.editNodeProjectWindow.openNodeProject(nodeItem)
                                                }
                                            }

                                            Components.QuickActionButton {
                                                id: nodeMoreButton
                                                text: ""
                                                iconSource: "../icons/lucide/ellipsis-vertical.svg"
                                                tooltip: "Options"
                                                onClicked: {
                                                    nodeMoreMenu.refreshOpenWithEditors()
                                                    nodeMoreMenu.open(nodeMoreButton)
                                                }
                                            }
                                        }

                                        Native.Menu {
                                            id: nodeMoreMenu
                                            property string projectPath: String(nodeItem.project_path || "")
                                            property string siteUrl: String(nodeItem.browse_url || "")
                                            property var openWithEditors: []

                                            function refreshOpenWithEditors() {
                                                openWithEditors = tableRoot.bridge && tableRoot.bridge.websiteOpenWithEditors
                                                    ? tableRoot.bridge.websiteOpenWithEditors(projectPath)
                                                    : []
                                            }

                                            Native.MenuSeparator {}

                                            Native.MenuItem {
                                                text: "Copy Path"
                                                enabled: nodeMoreMenu.projectPath.length > 0
                                                icon.name: tableRoot.nativeMenuIconsSupported ? "edit-copy" : ""
                                                icon.source: tableRoot.nativeMenuIconsSupported ? "../icons/lucide/file-text.svg" : ""
                                                onTriggered: {
                                                    if (tableRoot.bridge && tableRoot.bridge.copyTextToClipboard) {
                                                        tableRoot.bridge.copyTextToClipboard(nodeMoreMenu.projectPath)
                                                    }
                                                }
                                            }

                                            Native.MenuItem {
                                                text: "Open with Terminal"
                                                enabled: nodeMoreMenu.projectPath.length > 0
                                                icon.name: tableRoot.nativeMenuIconsSupported ? "terminal" : ""
                                                icon.source: tableRoot.nativeMenuIconsSupported ? "../icons/lucide/terminal.svg" : ""
                                                onTriggered: {
                                                    if (tableRoot.bridge && tableRoot.bridge.openPathInTerminal) {
                                                        tableRoot.bridge.openPathInTerminal(nodeMoreMenu.projectPath)
                                                    }
                                                }
                                            }

                                            Native.MenuSeparator {}

                                            Native.MenuItem {
                                                text: Strings.t("reveal.in.finder")
                                                enabled: nodeMoreMenu.projectPath.length > 0
                                                icon.name: tableRoot.nativeMenuIconsSupported ? "folder" : ""
                                                icon.source: tableRoot.nativeMenuIconsSupported ? "../icons/lucide/folder-open.svg" : ""
                                                onTriggered: {
                                                    if (tableRoot.bridge && tableRoot.bridge.revealInFinder) {
                                                        tableRoot.bridge.revealInFinder(nodeMoreMenu.projectPath)
                                                    }
                                                }
                                            }

                                            Native.MenuItem {
                                                text: Strings.t("open.site")
                                                enabled: nodeMoreMenu.siteUrl.length > 0
                                                icon.name: tableRoot.nativeMenuIconsSupported ? "link" : ""
                                                icon.source: tableRoot.nativeMenuIconsSupported ? "../icons/lucide/external-link.svg" : ""
                                                onTriggered: Qt.openUrlExternally(nodeMoreMenu.siteUrl)
                                            }

                                            Native.MenuItem {
                                                text: "Run with CLI"
                                                icon.name: tableRoot.nativeMenuIconsSupported ? "terminal" : ""
                                                icon.source: tableRoot.nativeMenuIconsSupported ? "../icons/lucide/terminal.svg" : ""
                                                onTriggered: tableRoot.pageRoot.requestNodeProjectCli(nodeItem)
                                            }

                                            Native.MenuSeparator {}

                                            Native.MenuItem {
                                                text: Strings.t("modify")
                                                icon.name: tableRoot.nativeMenuIconsSupported ? "preferences-system" : ""
                                                icon.source: tableRoot.nativeMenuIconsSupported ? "../icons/lucide/settings.svg" : ""
                                                onTriggered: {
                                                    tableRoot.pageRoot.addNodeProjectFeedback = ""
                                                    tableRoot.pageRoot.addNodeProjectFeedbackError = false
                                                    tableRoot.pageRoot.addNodeProjectOpen = false
                                                    tableRoot.editNodeProjectWindow.openNodeProject(nodeItem)
                                                }
                                            }

                                            Native.MenuItem {
                                                text: Strings.t("remove")
                                                icon.name: tableRoot.nativeMenuIconsSupported ? "user-trash" : ""
                                                icon.source: tableRoot.nativeMenuIconsSupported ? "../icons/lucide/trash-2.svg" : ""
                                                onTriggered: {
                                                    tableRoot.pageRoot.nodeProjectToDelete = nodeItem
                                                    tableRoot.deleteNodeProjectDialog.visible = true
                                                }
                                            }
                                        }

                                        Native.Menu {
                                            id: nodeOpenWithMenu
                                            title: Strings.t("open.with")

                                            Component.onCompleted: {
                                                nodeMoreMenu.insertMenu(0, nodeOpenWithMenu)
                                            }

                                            Instantiator {
                                                id: nodeOpenWithMenuItems
                                                model: nodeMoreMenu.openWithEditors

                                                delegate: Native.MenuItem {
                                                    required property int index
                                                    required property var modelData
                                                    text: String(modelData.label || "")
                                                    icon.source: tableRoot.nativeMenuIconsSupported ? String(modelData.iconSource || "") : ""
                                                    onTriggered: {
                                                        if (tableRoot.bridge && tableRoot.bridge.openPathWithEditor) {
                                                            tableRoot.bridge.openPathWithEditor(
                                                                nodeMoreMenu.projectPath,
                                                                String(modelData.id || "")
                                                            )
                                                        }
                                                    }
                                                }

                                                onObjectAdded: function(index, object) {
                                                    nodeOpenWithMenu.insertItem(index, object)
                                                }

                                                onObjectRemoved: function(index, object) {
                                                    nodeOpenWithMenu.removeItem(object)
                                                }
                                            }

                                            Instantiator {
                                                id: nodeOpenWithMenuFallback
                                                model: nodeMoreMenu.openWithEditors.length === 0 ? 1 : 0

                                                delegate: Native.MenuItem {
                                                    text: "No editors found"
                                                    enabled: false
                                                }

                                                onObjectAdded: function(index, object) {
                                                    nodeOpenWithMenu.insertItem(nodeOpenWithMenu.count, object)
                                                }

                                                onObjectRemoved: function(index, object) {
                                                    nodeOpenWithMenu.removeItem(object)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.border
                        }
                    }
                }

                Column {
                    id: emptyState
                    anchors.centerIn: parent
                    visible: !(tableRoot.bridge && (tableRoot.bridge.nodeProjectItems || []).length > 0)
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Strings.t("no.node.projects.yet")
                        color: Theme.text
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Strings.t("add.your.first.node.project")
                        color: Theme.muted
                        font.pixelSize: 14
                    }
                }
            }
        }
    }
}

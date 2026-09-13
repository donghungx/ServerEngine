import QtQuick
import QtQuick.Controls
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: tableRoot
    required property var pageRoot
    required property var deleteSiteDialog

    readonly property int bodyHeight: Math.max(0, tableRoot.height - headerCard.height - 14)

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

        Row {
            width: parent.width
            height: parent.height
            spacing: 0

            Components.HeaderCell { label: Strings.t("site.name"); cellWidth: 248 }
            Components.HeaderCell { label: Strings.t("php"); cellWidth: 92+16 }
            Components.HeaderCell { label: Strings.t("ssl"); cellWidth: 100 }
            Item { width: Math.max(0, parent.width - 220 - 92 - 100); height: parent.height }
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
                height: Math.max(tableRoot.bodyHeight, phpList.visible ? phpList.contentHeight : emptyState.implicitHeight)

                ListView {
                    id: phpList
                    width: parent.width
                    height: contentHeight
                    implicitHeight: contentHeight
                    model: tableRoot.pageRoot.filteredWebsiteItems
                    visible: count > 0
                    interactive: false
                    clip: true

                    delegate: Column {
                        required property int index
                        width: ListView.view.width
                        property var websiteItem: tableRoot.pageRoot.filteredWebsiteItems[index]

                        Components.WebsiteRow {
                            width: parent.width
                            height: 70
                            rowData: parent.websiteItem
                            dashboardBridge: tableRoot.pageRoot.dashboardBridge
                            onSiteSelected: {
                                tableRoot.pageRoot.selectedSite = parent.websiteItem
                                tableRoot.pageRoot.selectedSiteSection = "domain"
                                tableRoot.pageRoot.siteDetailsOpen = true
                            }
                            onCliRequested: tableRoot.pageRoot.websiteCliRequested(parent.websiteItem)
                            onModifyRequested: {
                                tableRoot.pageRoot.selectedSite = parent.websiteItem
                                tableRoot.pageRoot.selectedSiteSection = "domain"
                                tableRoot.pageRoot.siteDetailsOpen = true
                            }
                            onDeleteRequested: {
                                tableRoot.pageRoot.siteToDelete = parent.websiteItem
                                tableRoot.deleteSiteDialog.visible = true
                                tableRoot.deleteSiteDialog.raise()
                                tableRoot.deleteSiteDialog.requestActivate()
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
                    visible: tableRoot.pageRoot.filteredWebsiteItems.length === 0
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tableRoot.pageRoot.siteFilterQuery.length > 0 ? Strings.t("no.matching.sites") : Strings.t("no.sites.yet")
                        color: Theme.text
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tableRoot.pageRoot.siteFilterQuery.length > 0
                            ? Strings.t("try.a.different.domain.or.remarks.keyword")
                            : Strings.t("create.your.first.local.site.with.the.add.site.button")
                        color: Theme.muted
                        font.pixelSize: 14
                    }
                }
            }
        }
    }
}


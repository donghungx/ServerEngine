import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../pages" as Pages
import "../pages/database" as DatabasePages

RowLayout {
    id: mainContentLayout

    signal installNodeRuntimeRequested()
    signal installPhpRuntimeRequested()
    signal openPhpSettingsRequested()
    signal openDatabaseCliRequested()
    signal openRedisCliRequested()
    signal openBottomMailRequested()
    signal openPostgresqlBackupRequested(var rowData)
    signal openMongodbCliRequested()
    signal openPostgresqlCliRequested()
    signal openWebsiteCliRequested(var siteData)
    signal openNodeProjectCliRequested(var nodeProjectData)

    required property var dashboardBridge
    required property var bottomPanelItem

    property alias websitePage: websitePage
    property alias databasePage: databasePage
    property alias databaseBackupPage: databaseBackupPage

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: bottomPanelItem.top
    spacing: 16

    Sidebar {
        dashboardBridge: mainContentLayout.dashboardBridge
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 18

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: dashboardBridge.currentPageIndex

            Pages.HomePage {
                dashboardBridge: mainContentLayout.dashboardBridge
            }

            Pages.WebsitePage {
                id: websitePage
                dashboardBridge: mainContentLayout.dashboardBridge
                onInstallNodeRuntimeRequested: mainContentLayout.installNodeRuntimeRequested()
                onWebsiteCliRequested: function(siteData) {
                    mainContentLayout.openWebsiteCliRequested(siteData)
                }
                onNodeProjectCliRequested: function(nodeProjectData) {
                    mainContentLayout.openNodeProjectCliRequested(nodeProjectData)
                }
            }

            Pages.PhpPage {
                dashboardBridge: mainContentLayout.dashboardBridge
                onInstallMoreSelected: mainContentLayout.installPhpRuntimeRequested()
                onOpenPhpSettingsRequested: mainContentLayout.openPhpSettingsRequested()
            }

            Pages.DatabasePage {
                id: databasePage
                dashboardBridge: mainContentLayout.dashboardBridge
                onDatabaseCliRequested: mainContentLayout.openDatabaseCliRequested()
            }

            Pages.RedisPage {
                dashboardBridge: mainContentLayout.dashboardBridge
                onDatabaseCliRequested: mainContentLayout.openRedisCliRequested()
            }

            Pages.CachePage {
                dashboardBridge: mainContentLayout.dashboardBridge
            }

            Pages.MailPage {
                dashboardBridge: mainContentLayout.dashboardBridge
                onOpenBottomMailRequested: mainContentLayout.openBottomMailRequested()
            }

            Pages.PostgreSQLPage {
                dashboardBridge: mainContentLayout.dashboardBridge
                onDatabaseCliRequested: mainContentLayout.openPostgresqlCliRequested()
                onBackupRequested: mainContentLayout.openPostgresqlBackupRequested(rowData)
            }

            Pages.MongoDBPage {
                dashboardBridge: mainContentLayout.dashboardBridge
                onDatabaseCliRequested: mainContentLayout.openMongodbCliRequested()
            }

            DatabasePages.DatabaseBackupPage {
                id: databaseBackupPage
                dashboardBridge: mainContentLayout.dashboardBridge
                databaseName: ""
            }

        }
    }
}

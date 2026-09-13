import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: siteDetailsWindow

    required property var root
    readonly property var dashboardBridge: root.dashboardBridge
    readonly property var siteSectionItem: siteSectionLoader.item

    function reloadSiteData() {
        if (!dashboardBridge || !root.selectedSite || !root.selectedSite.id) {
            return
        }
        console.log("[WebsiteSiteDetailsDialog] reloadSiteData site_id=", String(root.selectedSite.id))
        var freshSite = dashboardBridge.siteDetails(String(root.selectedSite.id))
        if (freshSite && freshSite.id) {
            console.log(
                "[WebsiteSiteDetailsDialog] reloadSiteData result site_id=",
                String(freshSite.id),
                "ssl_enabled=",
                freshSite.ssl_enabled !== undefined ? String(freshSite.ssl_enabled) : "undefined",
                "ssl_enforce_tls=",
                freshSite.ssl_enforce_tls !== undefined ? String(freshSite.ssl_enforce_tls) : "undefined",
                "ssl_allow_http=",
                freshSite.ssl_allow_http !== undefined ? String(freshSite.ssl_allow_http) : "undefined"
            )
            root.selectedSite = freshSite
            if (siteSectionLoader.item) {
                siteSectionLoader.item.siteData = freshSite
            }
        }
    }

    width: 736
    height: 520
    minimumWidth: width
    maximumWidth: width

    minimumHeight: height
    maximumHeight: height
    visible: root.siteDetailsOpen
    title: root.selectedSite.primary_domain
        ? String(root.selectedSite.primary_domain)
        : (root.selectedSite.local_domain
            ? String(root.selectedSite.local_domain)
            : (root.selectedSite.name ? String(root.selectedSite.name) : Strings.t("site.details")))
    modality: Qt.ApplicationModal
    transientParent: root.Window.window
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
    color: Theme.surface

    onClosing: function(closeEvent) {
        root.siteDetailsOpen = false
    }

    onVisibleChanged: {
        if (!visible) {
            return
        }
        console.log("[WebsiteSiteDetailsDialog] visible -> reload")
        //reloadSiteData()
    }

    Components.PageWindowFrame {
        moveWindow: siteDetailsWindow
        bodyMargins: 16

        headerContent: Item {
            anchors.fill: parent

            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                text: root.siteSectionLabel(root.selectedSiteSection)
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Item {
                anchors.fill: parent
                anchors.topMargin: 28
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.bottomMargin: 6
                clip: true

                Row {
                    height: 58
                    spacing: 6

                    Repeater {
                        model: root.visibleSiteSections

                        delegate: Components.TopIconTab {
                            id: siteTopTabItem
                            required property int index
                            property var navItem: root.visibleSiteSections[index]
                            selected: root.selectedSiteSection === navItem.id
                            label: siteTopTabItem.navItem.label
                            iconSource: "../icons/lucide/" + root.siteSectionIcon(siteTopTabItem.navItem.id) + ".svg"
                            onClicked: root.selectedSiteSection = siteTopTabItem.navItem.id
                        }
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent

            Loader {
                id: siteSectionLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                source: root.siteSectionSource(root.selectedSiteSection)
                onLoaded: {
                    if (item) {
                        item.siteData = root.selectedSite
                        try {
                            item.dashboardBridge = dashboardBridge
                        } catch (error) {
                        }
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: deleteSiteDialog

    required property var root
    readonly property var dashboardBridge: root.dashboardBridge

    property bool moveFilesToTrash: false

    visible: false

    width: 400
    height: 136

    minimumWidth: width
    maximumWidth: width

    minimumHeight: height
    maximumHeight: height

    title: Strings.t("remove.website")

    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: root.Window.window

    flags: Qt.Dialog
        | Qt.CustomizeWindowHint
        | Qt.WindowTitleHint
        | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (!visible) {
            root.siteToDelete = ({})
        }
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: Strings.t("remove.website")
        moveWindow: deleteSiteDialog
        color: Theme.surface

        ColumnLayout {
            id: deleteSiteContent
            anchors.fill: parent
            spacing: 4

            Label {
                text: Strings.t("this.will.remove.the.website.from.server.engine")
                color: Theme.text
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: Strings.t("remove.this.site.from.the.app")
                color: Theme.text
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: root.siteToDelete && root.siteToDelete.primary_domain
                    ? String(root.siteToDelete.primary_domain)
                    : ""
                color: Theme.text
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Item {
                Layout.fillHeight: true
            }
        }

        footerLeft : CheckBox {
            id: moveToTrashCheckBox
            text: Strings.t("move.files.to.trash")
            checked: false
            Layout.fillWidth: true
            onCheckedChanged: deleteSiteDialog.moveFilesToTrash = checked
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("cancel")

                onClicked: {
                    deleteSiteDialog.visible = false
                    deleteSiteDialog.moveFilesToTrash = false
                    root.siteToDelete = ({})
                }
            }

            Components.AppButton {
                text: Strings.t("remove")

                highlighted: true
                textColor: "white"

                enabled: !!root.siteToDelete
                    && String(root.siteToDelete.id || "").length > 0

                onClicked: {
                    if (!root.siteToDelete || !root.siteToDelete.id) {
                        deleteSiteDialog.visible = false
                        return
                    }

                    var ok = dashboardBridge.deleteSite(
                        String(root.siteToDelete.id),
                        deleteSiteDialog.moveFilesToTrash
                    )

                    if (
                        ok
                        && root.selectedSite
                        && root.selectedSite.id === root.siteToDelete.id
                    ) {
                        root.siteDetailsOpen = false
                        root.selectedSite = ({})
                    }

                    deleteSiteDialog.visible = false
                    deleteSiteDialog.moveFilesToTrash = false
                    root.siteToDelete = ({})
                }
            }
        }
    }
}

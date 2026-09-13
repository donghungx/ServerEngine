import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    property
    var siteData: ({})
    property
    var dashboardBridge
    property string feedbackText: ""
    property bool feedbackError: false
    property string loadedSiteId: ""
    property bool editorDirty: false
    property bool syncingEditor: false
    property string defaultDocuments:
        "index.php\n" +
        "index.html\n" +
        "index.htm\n" +
        "default.php\n" +
        "default.htm\n" +
        "default.html"

    function loadDefaultDocuments() {
        if (!dashboardBridge || !siteData || !siteData.id) {
            return
        }
        var siteId = String(siteData.id)
        var switchingSite = loadedSiteId !== siteId
        if (!switchingSite && (editorDirty || defaultDocEditor.activeFocus)) {
            return
        }
        var loaded = dashboardBridge.siteDefaultDocuments(String(siteData.id))
        syncingEditor = true
        if (String(loaded).length > 0) {
            defaultDocuments = loaded
        } else if (switchingSite) {
            defaultDocuments =
                "index.php\n" +
                "index.html\n" +
                "index.htm\n" +
                "default.php\n" +
                "default.htm\n" +
                "default.html"
        }
        loadedSiteId = siteId
        editorDirty = false
        syncingEditor = false
    }

    Component.onCompleted: loadDefaultDocuments()
    onSiteDataChanged: loadDefaultDocuments()

    Components.SettingsTabFrame {
        anchors.fill: parent

        ColumnLayout {
            spacing: 16



            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Components.AppScrollEditor {
                    id: defaultDocEditor
                    anchors.fill: parent
                    text: defaultDocuments
                    readOnly: false
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    textFormat: TextEdit.PlainText
                    fontPixelSize: 12
                    textColor: Theme.text
                    contentPadding: 8
                    onTextChanged: {
                        if (!syncingEditor) {
                            editorDirty = true
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("default.indexes.are.checked.from.top.to.bottom.one.per.line")
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }

        footerLeft: Text {
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackError ? Theme.danger : Theme.success
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        footerRight: RowLayout {
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    if (!dashboardBridge || !siteData || !siteData.id) {
                        return
                    }
                    var ok = dashboardBridge.saveSiteDefaultDocuments(String(siteData.id), defaultDocEditor.text)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackError = !ok
                    if (ok) {
                        syncingEditor = true
                        defaultDocuments = dashboardBridge.siteDefaultDocuments(String(siteData.id))
                        editorDirty = false
                        syncingEditor = false
                    }
                }
            }
        }
    }
}

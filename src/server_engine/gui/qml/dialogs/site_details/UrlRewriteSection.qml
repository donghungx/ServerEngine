import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root
    property var siteData: ({})
    property var dashboardBridge
    property string feedbackText: ""
    property bool feedbackError: false
    property bool restartConfirmOpen: false
    property string loadedRewriteSiteId: ""
    property var rewriteTemplates: [
        { label: Strings.t("select.template"), value: "" },
        {
            label: Strings.t("laravel"),
            value:
                "location / {\n" +
                "    try_files $uri $uri/ /index.php$is_args$query_string;\n" +
                "}"
        },
        {
            label: Strings.t("wordpress"),
            value:
                "location / {\n" +
                "    try_files $uri $uri/ /index.php?$args;\n" +
                "}"
        },
        {
            label: Strings.t("basic.php"),
            value:
                "location / {\n" +
                "    try_files $uri $uri/ /index.php?$query_string;\n" +
                "}"
        },
        {
            label: Strings.t("react.spa"),
            value:
                "location / {\n" +
                "    try_files $uri /index.html;\n" +
                "}"
        }
    ]

    function loadRewriteRules() {
        if (!dashboardBridge || !siteData || !siteData.id) {
            return
        }
        if (loadedRewriteSiteId === String(siteData.id)) {
            return
        }
        var loaded = dashboardBridge.siteNginxRewriteRules(String(siteData.id))
        rewriteEditor.text = String(loaded || "")
        loadedRewriteSiteId = String(siteData.id)
    }

    Component.onCompleted: loadRewriteRules()
    onSiteDataChanged: loadRewriteRules()
    onDashboardBridgeChanged: loadRewriteRules()

    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        Label {
            text: Strings.t("url.rewrite")
            color: Theme.text
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }

        Label {
            Layout.fillWidth: true
            text: Strings.t("nginx.location.rules.for.this.site")
            color: Theme.muted
            font.pixelSize: 13
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: Strings.t("template")
                color: Theme.text
                font.pixelSize: 13
            }

            Components.AppComboBox {
                id: templateCombo
                Layout.preferredWidth: 220
                model: root.rewriteTemplates
                textRole: "label"
                onActivated: function(index) {
                    var tpl = root.rewriteTemplates[index]
                    if (tpl && String(tpl.value || "").length > 0) {
                        rewriteEditor.text = String(tpl.value)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: "#fbfbfc"
            border.color: Theme.border
            border.width: 1

            ScrollView {
                anchors.fill: parent
                anchors.margins: 1
                clip: true

                Components.NativeTextArea {
                    id: rewriteEditor
                    text: ""
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    selectByMouse: true
                    persistentSelection: true
                    font.family: "Menlo"
                    font.pixelSize: 15
                    color: Theme.text
                    padding: 16
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Components.AppButton {
                text: Strings.t("test")
                onClicked: {
                    if (!dashboardBridge || !siteData || !siteData.id) {
                        return
                    }
                    var ok = dashboardBridge.testSiteNginxRewriteRulesDraft(String(siteData.id), rewriteEditor.text)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackError = !ok
                }
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    if (!dashboardBridge || !siteData || !siteData.id) {
                        return
                    }
                    var ok = dashboardBridge.saveSiteNginxRewriteRules(String(siteData.id), rewriteEditor.text)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackError = !ok
                    if (ok && dashboardBridge.homeServiceRunning("web")) {
                        restartConfirmOpen = true
                    }
                }
            }

            Components.AppButton {
                text: Strings.t("reload")
                onClicked: {
                    loadedRewriteSiteId = ""
                    loadRewriteRules()
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        footerLeft: Text {
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackError ? Theme.danger : Theme.success
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
    }

    Window {
        id: restartConfirmWindow
        visible: restartConfirmOpen
        width: 480
        height: 180
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: Strings.t("restart.nginx")
        modality: Qt.ApplicationModal
        transientParent: root.Window.window
        flags: Qt.Window
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (!visible) {
                restartConfirmOpen = false
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Label {
                    Layout.fillWidth: true
                    text: Strings.t("nginx.is.running.restart.now.to.apply.rewrite.changes")
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    Components.AppButton {
                        text: Strings.t("later")
                        onClicked: restartConfirmOpen = false
                    }

                    Components.AppButton {
                        text: Strings.t("restart")
                        highlighted: true
                        textColor: "white"
                        onClicked: {
                            restartConfirmOpen = false
                            dashboardBridge.restartWebServerRuntime()
                        }
                    }
                }
            }
        }
    }
}

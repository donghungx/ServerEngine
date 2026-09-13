import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var phpRuntime: ({})
    property var dashboardBridge
    property var extensionItems: []
    property var initialExtensionEnabledMap: ({})
    property string feedbackText: ""
    property bool feedbackError: false
    property bool hasPendingChanges: false
    property bool applyingBatchSave: false
    Layout.fillWidth: true
    Layout.fillHeight: true

    function isCacheExtension(name) {
        var n = String(name || "").toLowerCase()
        return n === "redis" || n === "memcached" || n === "apcu" || n === "opcache"
    }

    function activeOtherCacheExtensions(targetName) {
        var actives = []
        for (var i = 0; i < extensionItems.length; i++) {
            var item = extensionItems[i]
            if (isCacheExtension(item.name) && item.name !== targetName && item.enabled) {
                actives.push(item.name)
            }
        }
        return actives
    }

    function loadSettings() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            extensionItems = []
            initialExtensionEnabledMap = ({})
            hasPendingChanges = false
            return
        }
        extensionItems = dashboardBridge.phpExtensionItems(phpRuntime.version)
        var initialMap = {}
        for (var i = 0; i < extensionItems.length; i++) {
            initialMap[String(extensionItems[i].name)] = !!extensionItems[i].enabled
        }
        initialExtensionEnabledMap = initialMap
        hasPendingChanges = false
    }

    function recomputePendingChanges() {
        var dirty = false
        for (var i = 0; i < extensionItems.length; i++) {
            var item = extensionItems[i]
            var name = String(item.name || "")
            if (!!item.enabled !== !!initialExtensionEnabledMap[name]) {
                dirty = true
                break
            }
        }
        hasPendingChanges = dirty
    }

    function setExtensionDraft(extensionName, enable) {
        var changed = false
        var targetName = String(extensionName || "")
        var targetLower = targetName.toLowerCase()
        var targetIsCache = isCacheExtension(targetName)
        var nextItems = []

        for (var i = 0; i < extensionItems.length; i++) {
            var item = extensionItems[i]
            var name = String(item.name || "")
            var nameLower = name.toLowerCase()
            var nextEnabled = !!item.enabled

            if (nameLower === targetLower) {
                nextEnabled = !!enable
            } else if (!!enable && targetIsCache && isCacheExtension(name) && !!item.enabled) {
                nextEnabled = false
            }

            if (nextEnabled !== !!item.enabled) {
                changed = true
            }

            nextItems.push({
                "name": name,
                "description": item.description,
                "status": item.status,
                "installed": item.installed,
                "enabled": nextEnabled
            })
        }
        if (changed) {
            extensionItems = nextItems
            recomputePendingChanges()
        }
    }

    function saveChanges() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version || !hasPendingChanges) {
            return
        }
        var allOk = true
        applyingBatchSave = true
        for (var i = 0; i < extensionItems.length; i++) {
            var item = extensionItems[i]
            var name = String(item.name || "")
            var before = !!initialExtensionEnabledMap[name]
            var now = !!item.enabled
            if (before === now) {
                continue
            }
            var ok = dashboardBridge.setPhpExtensionEnabled(phpRuntime.version, name, now)
            if (!ok) {
                allOk = false
                break
            }
        }
        applyingBatchSave = false
        feedbackText = dashboardBridge.lastOperationMessage
        feedbackError = !allOk
        loadSettings()
    }

    onPhpRuntimeChanged: loadSettings()
    onDashboardBridgeChanged: loadSettings()

    Connections {
        target: dashboardBridge
        ignoreUnknownSignals: true
        function onPhpExtensionsChanged() {
            if (!root.applyingBatchSave) {
                root.loadSettings()
            }
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("manage.php.extension.activation.for.this.runtime.changes.are.applied.only.when.you.click.save")
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                font.weight: Font.Medium
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surface
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        color: Theme.surface

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 0

                            Text {
                                width: parent.width - 122
                                anchors.verticalCenter: parent.verticalCenter
                                text: Strings.t("extension")
                                color: Theme.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                width: 108
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: Strings.t("enabled")
                                color: Theme.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.border
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.surface
                        clip: true

                        Components.AppScrollArea {
                            anchors.fill: parent
                            viewportMargins: 1
                            clipContent: true

                            Column {
                                width: parent.width
                                spacing: 0

                                Repeater {
                                    model: root.extensionItems

                                    delegate: Rectangle {
                                        required property int index
                                        property var itemData: root.extensionItems[index]

                                        width: parent.width
                                        height: 46
                                        color: index % 2 === 0 ? Theme.surface : Theme.surfaceAlt

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 0

                                            Column {
                                                width: parent.width - 122
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 2

                                                Text {
                                                    width: parent.width
                                                    text: itemData.name
                                                    color: Theme.text
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: itemData.description + " • " + itemData.status
                                                    color: Theme.muted
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Item {
                                                width: 108
                                                height: parent.height

                                                Components.AppSwitch {
                                                    anchors.centerIn: parent
                                                    checked: itemData.enabled
                                                    enabled: !(dashboardBridge && dashboardBridge.phpExtensionActionBusy) && (itemData.installed || itemData.enabled)
                                                    onToggled: function(nextChecked) { setExtensionDraft(itemData.name, nextChecked) }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: Theme.border
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        footerLeft: Text {
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("reload")
                enabled: !(dashboardBridge && dashboardBridge.phpExtensionActionBusy)
                onClicked: {
                    feedbackText = ""
                    feedbackError = false
                    loadSettings()
                }
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                enabled: hasPendingChanges && !(dashboardBridge && dashboardBridge.phpExtensionActionBusy)
                onClicked: saveChanges()
            }
        }
    }
}




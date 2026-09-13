import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt.labs.platform as Native
import "../../components" as Components
import "../../theme"
import "../../i18n"

Components.ShellCard {
    id: root

    required property var dashboardBridge
    required property bool panelOpen
    signal hideRequested()

    border.width: 0
    color: "transparent"

    property string selectedView: "tree"
    property string filterText: ""
    property var expandedNamespaces: ({})
    property var contextMenuPayload: null
    property string contextMenuKind: ""
    property bool openRefreshQueued: false
    readonly property bool hasSelectedValue: dashboardBridge
        && String(dashboardBridge.redisInspectorSelectedKey || "").length > 0
        && String(dashboardBridge.redisInspectorSelectedValue || "").trim().length > 0
        && String(dashboardBridge.redisInspectorSelectedValue || "").trim() !== "(nil)"
        && String(dashboardBridge.redisInspectorSelectedValue || "").trim().toLowerCase() !== "nil"

    component InspectorTabButton: Rectangle {
        id: tab
        signal clicked()
        property string label: ""
        property bool active: false

        height: 26
        width: tabLabel.implicitWidth + 16
        radius: 6
        color: active ? Theme.buttonNeutralBackground : (tabMouse.containsMouse ? Theme.buttonNeutralBackground : "transparent")

        Text {
            id: tabLabel
            anchors.centerIn: parent
            text: tab.label
            color: Theme.text
            font.pixelSize: 12
        }

        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: tab.clicked()
        }
    }

    component IconOnlyButton: Rectangle {
        id: iconButton
        signal clicked()
        property string iconSource: ""
        property string tooltip: ""
        width: 24
        height: 24
        radius: 12
        color: mouseArea.containsMouse ? Theme.buttonNeutralBackground : "transparent"

        Image {
            id: iconSourceImage
            anchors.centerIn: parent
            width: 16
            height: 16
            sourceSize.width: 16
            sourceSize.height: 16
            source: iconButton.iconSource
            visible: false
        }

        MultiEffect {
            anchors.fill: iconSourceImage
            source: iconSourceImage
            colorization: 1.0
            colorizationColor: Theme.text
            brightness: 1.0
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.clicked()
        }

        Components.AppToolTip {
            visible: iconButton.tooltip.length > 0 && mouseArea.containsMouse
            delay: 400
            text: iconButton.tooltip
        }
    }

    component InspectorKeyMenu: Native.Menu {
        id: menu
        property var inspectorItem: null

        Native.MenuItem {
            text: "Copy as JSON"
            onTriggered: {
                if (dashboardBridge && dashboardBridge.copyTextToClipboard && menu.inspectorItem) {
                    dashboardBridge.copyTextToClipboard(JSON.stringify(menu.inspectorItem || {}, null, 2))
                }
            }
        }

        Native.MenuItem {
            text: "Delete"
            enabled: !!(menu.inspectorItem && String(menu.inspectorItem.key || "").length > 0)
            onTriggered: {
                if (dashboardBridge && dashboardBridge.deleteRedisInspectorKey && menu.inspectorItem && menu.inspectorItem.key) {
                    dashboardBridge.deleteRedisInspectorKey(String(menu.inspectorItem.key))
                }
            }
        }
    }

    component InspectorNamespaceMenu: Native.Menu {
        id: menu
        property var namespaceItem: null

        Native.MenuItem {
            text: "Copy as JSON"
            onTriggered: {
                if (dashboardBridge && dashboardBridge.copyTextToClipboard && menu.namespaceItem) {
                    dashboardBridge.copyTextToClipboard(JSON.stringify(menu.namespaceItem || {}, null, 2))
                }
            }
        }

        Native.MenuItem {
            text: "Delete"
            enabled: !!(menu.namespaceItem && String(menu.namespaceItem.path || menu.namespaceItem.label || "").length > 0)
            onTriggered: {
                if (dashboardBridge && dashboardBridge.deleteRedisInspectorNamespace && menu.namespaceItem) {
                    dashboardBridge.deleteRedisInspectorNamespace(String(menu.namespaceItem.path || menu.namespaceItem.label || "default"))
                }
            }
        }
    }

    function openInspectorContextMenu(kind, payload) {
        root.contextMenuKind = String(kind || "")
        root.contextMenuPayload = payload || null
        inspectorContextMenu.open()
    }

    function requestRefreshInspector() {
        if (!panelOpen) {
            openRefreshQueued = true
            return
        }
        if (dashboardBridge && dashboardBridge.refreshRedisInspector) {
            dashboardBridge.refreshRedisInspector(filterText)
        }
    }

    function scheduleOpenRefresh() {
        if (!panelOpen) {
            openRefreshQueued = true
            return
        }
        openRefreshQueued = false
        openRefreshTimer.restart()
    }

    function pauseInspectorActivity() {
        openRefreshQueued = false
        openRefreshTimer.stop()
        filterRefreshTimer.stop()
    }

    Timer {
        id: openRefreshTimer
        interval: 220
        repeat: false
        onTriggered: root.requestRefreshInspector()
    }

    Timer {
        id: filterRefreshTimer
        interval: 250
        repeat: false
        onTriggered: root.requestRefreshInspector()
    }

    Native.Menu {
        id: inspectorContextMenu

        Native.MenuItem {
            text: "Copy as JSON"
            enabled: !!root.contextMenuPayload
            onTriggered: {
                if (dashboardBridge && dashboardBridge.copyTextToClipboard && root.contextMenuPayload) {
                    dashboardBridge.copyTextToClipboard(JSON.stringify(root.contextMenuPayload, null, 2))
                }
            }
        }

        Native.MenuItem {
            text: "Delete"
            enabled: root.contextMenuKind === "namespace"
                ? !!(root.contextMenuPayload && String(root.contextMenuPayload.path || root.contextMenuPayload.label || "").length > 0)
                : !!(root.contextMenuPayload && String(root.contextMenuPayload.key || "").length > 0)
            onTriggered: {
                if (root.contextMenuKind === "namespace") {
                    if (dashboardBridge && dashboardBridge.deleteRedisInspectorNamespace && root.contextMenuPayload) {
                        dashboardBridge.deleteRedisInspectorNamespace(String(root.contextMenuPayload.path || root.contextMenuPayload.label || "default"))
                    }
                    return
                }
                if (dashboardBridge && dashboardBridge.deleteRedisInspectorKey && root.contextMenuPayload) {
                    dashboardBridge.deleteRedisInspectorKey(String(root.contextMenuPayload.key || ""))
                }
            }
        }
    }

    function namespaceExpanded(namespaceName) {
        var name = String(namespaceName || "default")
        return !!root.expandedNamespaces[name]
    }

    function toggleNamespace(namespaceName) {
        var name = String(namespaceName || "default")
        var nextState = {}
        for (var key in root.expandedNamespaces) {
            if (Object.prototype.hasOwnProperty.call(root.expandedNamespaces, key)) {
                nextState[key] = root.expandedNamespaces[key]
            }
        }
        nextState[name] = !nextState[name]
        root.expandedNamespaces = nextState
    }

    function treeKeysForNamespace(namespaceName) {
        var name = String(namespaceName || "default")
        var keys = dashboardBridge ? (dashboardBridge.redisInspectorKeys || []) : []
        var items = []
        for (var i = 0; i < keys.length; i++) {
            var item = keys[i]
            if (String(item.namespace || "default") === name) {
                items.push(item)
            }
        }
        items.sort(function(a, b) {
            var ka = String(a && a.key ? a.key : "").toLowerCase()
            var kb = String(b && b.key ? b.key : "").toLowerCase()
            if (ka === kb) {
                return 0
            }
            return ka < kb ? -1 : 1
        })
        return items
    }

    function inspectorItemChangeState(item) {
        return String(item && item.change_state ? item.change_state : "")
    }

    function inspectorItemChangeRatio(item, tick) {
        var state = inspectorItemChangeState(item)
        if (state.length === 0) {
            return 0
        }
        var startedAt = Number(item && item.change_started_at ? item.change_started_at : 0)
        var defaultDuration = state === "removed" ? 1000 : 3000
        var duration = Math.max(1, Number(item && item.change_duration_ms ? item.change_duration_ms : defaultDuration))
        var elapsed = Date.now() - startedAt
        if (elapsed <= 0) {
            return 1
        }
        var ratio = 1 - (elapsed / duration)
        return ratio > 0 ? ratio : 0
    }

    function inspectorItemChangeBackground(item, tick) {
        var state = inspectorItemChangeState(item)
        var ratio = inspectorItemChangeRatio(item, tick)
        if (ratio <= 0 || state.length === 0) {
            return "transparent"
        }
        if (state === "added") {
            return Qt.rgba(0.35, 0.75, 0.35, 0.22 * ratio)
        }
        if (state === "removed") {
            return Qt.rgba(0.9, 0.35, 0.35, 0.22 * ratio)
        }
        return "transparent"
    }

    function inspectorItemVisible(item, tick) {
        var state = inspectorItemChangeState(item)
        if (state !== "removed") {
            return true
        }
        return inspectorItemChangeRatio(item, tick) > 0
    }

    function namespaceChangeState(namespaceName) {
        var items = root.treeKeysForNamespace(namespaceName)
        var removed = false
        var added = false
        for (var i = 0; i < items.length; i++) {
            var state = inspectorItemChangeState(items[i])
            if (state === "added") {
                added = true
            } else if (state === "removed") {
                removed = true
            }
        }
        if (added) {
            return "added"
        }
        if (removed) {
            return "removed"
        }
        return ""
    }

    function namespaceChangeRatio(namespaceName, tick) {
        var items = root.treeKeysForNamespace(namespaceName)
        var ratio = 0
        for (var i = 0; i < items.length; i++) {
            ratio = Math.max(ratio, inspectorItemChangeRatio(items[i], tick))
        }
        return ratio
    }

    function namespaceChangeBackground(namespaceName, tick) {
        var state = namespaceChangeState(namespaceName)
        var ratio = namespaceChangeRatio(namespaceName, tick)
        if (ratio <= 0 || state.length === 0) {
            return "transparent"
        }
        if (state === "added") {
            return Qt.rgba(0.35, 0.75, 0.35, 0.18 * ratio)
        }
        if (state === "removed") {
            return Qt.rgba(0.9, 0.35, 0.35, 0.18 * ratio)
        }
        return "transparent"
    }

    function expandFirstNamespaceIfNeeded() {
        if (selectedView !== "tree") {
            return
        }
        var namespaces = dashboardBridge ? (dashboardBridge.redisInspectorNamespaces || []) : []
        if (namespaces.length === 0) {
            return
        }
        if (Object.keys(root.expandedNamespaces).length > 0) {
            return
        }
        var first = namespaces[0]
        if (first) {
            root.toggleNamespace(String(first.path || first.label || "default"))
        }
    }

    function syncNamespacesWithFilter() {
        if (selectedView !== "tree") {
            return
        }
        var namespaces = dashboardBridge ? (dashboardBridge.redisInspectorNamespaces || []) : []
        if (namespaces.length === 0) {
            return
        }
        var filter = String(root.filterText || "").trim()
        if (filter.length === 0) {
            root.expandFirstNamespaceIfNeeded()
            return
        }
        var nextState = {}
        for (var key in root.expandedNamespaces) {
            if (Object.prototype.hasOwnProperty.call(root.expandedNamespaces, key)) {
                nextState[key] = root.expandedNamespaces[key]
            }
        }
        for (var i = 0; i < namespaces.length; i++) {
            var namespaceItem = namespaces[i]
            var namespaceName = String(namespaceItem.path || namespaceItem.label || "default")
            nextState[namespaceName] = true
        }
        root.expandedNamespaces = nextState
    }

    Component.onCompleted: {
        if (panelOpen) {
            scheduleOpenRefresh()
        }
    }

    onPanelOpenChanged: {
        if (panelOpen) {
            scheduleOpenRefresh()
        } else {
            pauseInspectorActivity()
        }
    }

    onVisibleChanged: {
        if (!visible) {
            pauseInspectorActivity()
        }
    }

    Connections {
        target: dashboardBridge ? dashboardBridge : null
        function onDataChanged() {
            if (!root.panelOpen) {
                return
            }
            root.syncNamespacesWithFilter()
        }
        function onRedisRuntimeFeedbackChanged() {
            if (!root.panelOpen) {
                return
            }
            root.syncNamespacesWithFilter()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            Layout.minimumHeight: 26
            Layout.maximumHeight: 26
            color: Theme.surfaceAlt


                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 2

                    InspectorTabButton {
                        label: "Tree View"
                        active: root.selectedView === "tree"
                        onClicked: root.selectedView = "tree"
                    }

                    InspectorTabButton {
                        label: "List View"
                        active: root.selectedView === "table"
                        onClicked: root.selectedView = "table"
                    }


                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 330
                        Layout.preferredHeight: 26
                        radius: 10
                        color: Theme.buttonNeutralBackground

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "Filters"
                                color: Theme.text
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            Components.AppTextField {
                                id: inspectorFilter
                                Layout.fillWidth: true
                                placeholderText: {
                                    var count = String(
                                        (dashboardBridge && dashboardBridge.redisInspectorKeys)
                                            ? dashboardBridge.redisInspectorKeys.filter(function(item) { return !item || item.present !== false }).length
                                            : 0
                                    )
                                    return "Filter keys or namespaces • " + count + " keys"
                                }
                                text: root.filterText
                                onTextChanged: {
                                    root.filterText = text
                                    filterRefreshTimer.restart()
                                }
                                onAccepted: root.requestRefreshInspector()
                            }
                        }
                    }

                    IconOnlyButton {
                        iconSource: "../../icons/lucide/rotate-cw.svg"
                        tooltip: "Refresh"
                        onClicked: root.requestRefreshInspector()
                    }

                    IconOnlyButton {
                        iconSource: "../../icons/lucide/minus.svg"
                        tooltip: "Hide"
                        onClicked: root.hideRequested()
                    }
                }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 2
            color: Theme.surfaceAlt
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.leftMargin: -12
            Layout.rightMargin: -12
            color: Theme.border
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.preferredWidth: 330
                Layout.minimumWidth: 330
                Layout.fillHeight: true
                clip: true
                color: Theme.surfaceAlt

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 0

                    Components.AppScrollArea {
                        id: treeScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.selectedView === "tree"
                        viewportMargins: 0
                        clipContent: true
                        showBorder: false
                        color: Theme.surfaceAlt

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 0
                            spacing: 2

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                            }

                            Repeater {
                                model: dashboardBridge ? dashboardBridge.redisInspectorNamespaces : []

                                delegate: Column {
                                    required property int index
                                    required property var modelData
                                    property var namespaceItem: modelData
                                    property int highlightTick: 0
                                    width: parent.width
                                    spacing: 0

                                    Rectangle {
                                        id: namespaceRow
                                        width: parent.width
                                        height: 24
                                        radius: 0
                                        color: "transparent"

                                        Rectangle {
                                            anchors.fill: parent
                                            color: root.namespaceChangeBackground(String(namespaceItem.path || namespaceItem.label || "default"), highlightTick)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            spacing: 4

                                            Rectangle {
                                                width: 18
                                                height: 18
                                                radius: 4
                                                Layout.leftMargin: 4
                                                color: Theme.buttonNeutralBackground

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.namespaceExpanded(String(namespaceItem.path || namespaceItem.label || "default")) ? "−" : "+"
                                                    color: Theme.text
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                }

                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: String(namespaceItem.label || namespaceItem.path || "default")
                                                    + " ("
                                                    + String(root.treeKeysForNamespace(String(namespaceItem.path || namespaceItem.label || "default")).length)
                                                    + ")"
                                                color: Theme.text
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.right: parent.right
                                            z: 0
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            preventStealing: true
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    root.openInspectorContextMenu("namespace", namespaceItem)
                                                    mouse.accepted = true
                                                }
                                            }
                                            onClicked: function(mouse) {
                                                if (mouse.button !== Qt.LeftButton) {
                                                    return
                                                }
                                                root.toggleNamespace(String(namespaceItem.path || namespaceItem.label || "default"))
                                            }
                                        }

                                                Timer {
                                                    interval: 80
                                                    repeat: true
                                                    running: root.panelOpen && root.namespaceChangeState(String(namespaceItem.path || namespaceItem.label || "default")).length > 0
                                                    onTriggered: highlightTick++
                                                }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: 2
                                        visible: root.namespaceExpanded(String(namespaceItem.path || namespaceItem.label || "default"))

                                        Repeater {
                                            model: root.treeKeysForNamespace(String(namespaceItem.path || namespaceItem.label || "default"))

                                            delegate: Rectangle {
                                                required property int index
                                                required property var modelData
                                                property var inspectorItem: modelData
                                                property int highlightTick: 0
                                                property bool rowHovered: false
                                                width: parent.width
                                                height: root.inspectorItemVisible(inspectorItem, highlightTick) ? 36 : 0
                                                radius: 6
                                                visible: root.inspectorItemVisible(inspectorItem, highlightTick)
                                                color: "transparent"

                                                Item {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    z: 0
                                                    visible: dashboardBridge && String(dashboardBridge.redisInspectorSelectedKey || "") === String(inspectorItem.key || "")

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 6
                                                        color: Theme.buttonNeutralBackground
                                                    }
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    z: 1
                                                    color: root.inspectorItemChangeBackground(inspectorItem, highlightTick)
                                                }

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 16
                                                    anchors.rightMargin: 16
                                                    anchors.topMargin: 4
                                                    anchors.bottomMargin: 4
                                                    z: 2
                                                    spacing: 1

                                                    RowLayout {
                                                        width: parent.width
                                                        spacing: 6

                                                        Column {
                                                            Layout.fillWidth: true
                                                            spacing: 1

                                                            Text {
                                                                width: parent.width
                                                                text: String(inspectorItem.key || "")
                                                                color: Theme.text
                                                                font.pixelSize: 12
                                                                elide: Text.ElideRight
                                                            }

                                                            Text {
                                                                width: parent.width
                                                                text: String(inspectorItem.type || "string") + " • TTL " + String(inspectorItem.ttl === -1 ? "persist" : inspectorItem.ttl)
                                                                color: Theme.muted
                                                                font.pixelSize: 10
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    z: 3
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                    cursorShape: Qt.PointingHandCursor
                                                    preventStealing: true
                                                    enabled: inspectorItem.present !== false
                                                    onEntered: rowHovered = true
                                                    onExited: rowHovered = false
                                                    onPressed: function(mouse) {
                                                        if (mouse.button === Qt.RightButton) {
                                                            root.openInspectorContextMenu("key", inspectorItem)
                                                            mouse.accepted = true
                                                        }
                                                    }
                                                    onClicked: function(mouse) {
                                                        if (mouse.button !== Qt.LeftButton) {
                                                            return
                                                        }
                                                        if (dashboardBridge && dashboardBridge.selectRedisInspectorKey) {
                                                            dashboardBridge.selectRedisInspectorKey(String(inspectorItem.key || ""))
                                                        }
                                                    }
                                                }

                                                Timer {
                                                    interval: 80
                                                    repeat: true
                                                    running: root.panelOpen && root.inspectorItemChangeState(inspectorItem).length > 0
                                                    onTriggered: highlightTick++
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.selectedView !== "tree"
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.surfaceAlt
                        }

                        ListView {
                            anchors.fill: parent
                            model: dashboardBridge ? dashboardBridge.redisInspectorKeys : []
                            clip: true

                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                property var inspectorItem: modelData
                                property int highlightTick: 0
                                property bool rowHovered: false
                                width: ListView.view.width
                                height: root.inspectorItemVisible(inspectorItem, highlightTick) ? 34 : 0
                                radius: 6
                                visible: root.inspectorItemVisible(inspectorItem, highlightTick)
                                color: "transparent"

                                Item {
                                    anchors.fill: parent
                                    z: 0
                                    visible: dashboardBridge && String(dashboardBridge.redisInspectorSelectedKey || "") === String(inspectorItem.key || "")

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 0
                                        color: Theme.buttonNeutralBackground
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    z: 1
                                    color: root.inspectorItemChangeBackground(inspectorItem, highlightTick)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    z: 2
                                    text: String(inspectorItem.key || "")
                                    color: Theme.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    width: parent.width - 16
                                }

                                MouseArea {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    z: 3
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    preventStealing: true
                                    enabled: inspectorItem.present !== false
                                    onEntered: rowHovered = true
                                    onExited: rowHovered = false
                                    onPressed: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            root.openInspectorContextMenu("key", inspectorItem)
                                            mouse.accepted = true
                                        }
                                    }
                                    onClicked: function(mouse) {
                                        if (mouse.button !== Qt.LeftButton) {
                                            return
                                        }
                                        if (dashboardBridge && dashboardBridge.selectRedisInspectorKey) {
                                            dashboardBridge.selectRedisInspectorKey(String(inspectorItem.key || ""))
                                        }
                                    }
                                }

                            Timer {
                                interval: 80
                                repeat: true
                                running: root.panelOpen && root.inspectorItemChangeState(inspectorItem).length > 0
                                onTriggered: highlightTick++
                            }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: Theme.border
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 360
                Layout.fillHeight: true
                radius: 0
                color: Theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Text {
                        text: dashboardBridge && dashboardBridge.redisInspectorSelectedKey.length > 0
                            ? dashboardBridge.redisInspectorSelectedKey
                            : "Key details"
                        color: Theme.text
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: root.hasSelectedValue
                    }

                    Text {
                        text: dashboardBridge ? String(dashboardBridge.redisInspectorSelectedSummary || "") : ""
                        color: Theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        visible: root.hasSelectedValue && text.length > 0
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Item {
                            anchors.fill: parent
                            visible: !root.hasSelectedValue
                            z: 2

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 40
                                spacing: 6

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: (dashboardBridge && dashboardBridge.redisInspectorKeys && dashboardBridge.redisInspectorKeys.length === 0)
                                        ? "No Redis keys yet"
                                        : "Select a key from the left panel"
                                    color: Theme.text
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: (dashboardBridge && dashboardBridge.redisInspectorKeys && dashboardBridge.redisInspectorKeys.length === 0)
                                        ? "Add some keys or open the CLI and refresh this panel."
                                        : "Click a key name to preview the value here."
                                    color: Theme.muted
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Components.NativeTextArea {
                            anchors.fill: parent
                            text: dashboardBridge ? String(dashboardBridge.redisInspectorSelectedValue || "") : ""
                            readOnly: true
                            selectByMouse: true
                            persistentSelection: true
                            wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                            textFormat: TextEdit.PlainText
                            color: Theme.text
                            font.family: "Menlo"
                            font.pixelSize: 11
                            nativeContextMenuEnabled: true
                            visible: root.hasSelectedValue
                        }
                    }
                }
            }
        }
    }
}

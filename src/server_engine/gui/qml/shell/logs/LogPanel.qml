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
    color: "transparent"
    required property var dashboardBridge
    required property bool panelOpen
    signal hideRequested()
    border.width: 0
    property string selectedLogId: ""
    property string logContent: ""
    property int tailLines: 100
    property bool tailMode: false
    property string selectedCategory: "all"
    property var filteredLogItems: []
    property bool refreshBusy: false
    property bool refreshQueued: false
    property bool refreshCooldown: false
    property bool openRefreshQueued: false
    property bool showImportantOnly: false
    property bool newestFirst: true
    property int maxFullReadBytes: 1048576
    property var categoryFilters: [
        { "catId": "all", "label": "All" },
        { "catId": "apache", "label": "Apache" },
        { "catId": "nginx", "label": "Nginx" },
        { "catId": "php", "label": "PHP" },
        { "catId": "database", "label": "Database" },
        { "catId": "mongodb", "label": "MongoDB" },
        { "catId": "postgresql", "label": "PostgreSQL" },
        { "catId": "redis", "label": "Redis" },
        { "catId": "memcached", "label": "Memcached" },
        { "catId": "node-projects", "label": "Node" },
        { "catId": "mailpit", "label": "Mailpit" },
        { "catId": "general", "label": "General" }
    ]

    component FilterTabButton: Rectangle {
        id: tab
        signal clicked()
        property string label: ""
        property bool active: false
        property bool pressed: false

        width: labelText.implicitWidth + 20
        height: 26
        radius: 6
        color: active
            ? (Theme.buttonNeutralBackground)
            : (mouseArea.containsMouse ? Theme.buttonNeutralBackground : "transparent")

        Text {
            id: labelText
            anchors.centerIn: parent
            text: tab.label
            color: Theme.text
            font.pixelSize: 12
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: tab.pressed = true
            onReleased: tab.pressed = false
            onCanceled: tab.pressed = false
            onClicked: tab.clicked()
        }
    }

    component IconOnlyButton: Rectangle {
        id: iconButton
        signal clicked()
        property string iconSource: ""
        property string tooltip: ""
        property bool active: false
        property bool accentIconWhenActive: false
        width: 24
        height: 24
        radius: 12
        color: mouseArea.containsMouse ? Theme.quickActionHoverBackground : "transparent"

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
            colorizationColor: (iconButton.active && iconButton.accentIconWhenActive)
                ? Theme.accentStrong
                : Theme.text
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

    function categoryVisible(itemCategory) {
        var cat = String(itemCategory || "").toLowerCase()
        var selected = effectiveSelectedCategory()
        return selected === "all" || cat === selected
    }

    function categoryFilterVisible(filterId) {
        var normalized = String(filterId || "").toLowerCase()
        if (normalized === "all") {
            return true
        }
        if (normalized === "mongodb" || normalized === "postgresql") {
            var allItems = dashboardBridge ? (dashboardBridge.logSourceItems || []) : []
            for (var i = 0; i < allItems.length; i++) {
                if (String(allItems[i].category || "").toLowerCase() === normalized) {
                    return true
                }
            }
            return false
        }
        return true
    }

    function effectiveSelectedCategory() {
        var selected = String(root.selectedCategory || "all").toLowerCase()
        if (selected === "mongodb" || selected === "postgresql") {
            return categoryFilterVisible(selected) ? selected : "all"
        }
        return selected
    }

    function recomputeFilteredLogs() {
        var allItems = dashboardBridge ? (dashboardBridge.logSourceItems || []) : []
        var nextItems = []
        for (var i = 0; i < allItems.length; i++) {
            var item = allItems[i]
            if (categoryVisible(item.category) && logVisibleInList(item)) {
                nextItems.push(item)
            }
        }
        nextItems.sort(function(a, b) {
            var ma = Number(a && a.modified ? a.modified : 0)
            var mb = Number(b && b.modified ? b.modified : 0)
            if (ma !== mb) {
                return mb - ma
            }
            var pa = priorityRank(a)
            var pb = priorityRank(b)
            if (pa !== pb) {
                return pa - pb
            }
            var ca = String(a && a.category ? a.category : "").toLowerCase()
            var cb = String(b && b.category ? b.category : "").toLowerCase()
            if (ca !== cb) {
                return ca < cb ? -1 : 1
            }
            var na = String(a && a.name ? a.name : "").toLowerCase()
            var nb = String(b && b.name ? b.name : "").toLowerCase()
            if (na === nb) {
                return 0
            }
            return na < nb ? -1 : 1
        })
        filteredLogItems = nextItems
    }

    function priorityRank(item) {
        var name = String(item && item.name ? item.name : "").toLowerCase()
        if (name.indexOf("httpd-error.log") !== -1) {
            return 0
        }
        if (name.indexOf("nginx-error.log") !== -1) {
            return 1
        }
        if (name.indexOf("nginx-startup.log") !== -1) {
            return 2
        }
        return 100
    }

    function logVisibleInList(item) {
        if (!showImportantOnly) {
            return true
        }
        var category = String(item && item.category ? item.category : "").toLowerCase()
        var name = String(item && item.name ? item.name : "").toLowerCase()
        var sizeValue = Number(item && item.size ? item.size : 0)
        var criticalName = name.indexOf("error") !== -1
            || name.indexOf("startup") !== -1
            || name.indexOf("crash") !== -1
            || name.indexOf("panic") !== -1
            || name.indexOf("fatal") !== -1
            || (name.indexOf("app-") !== -1 && name.indexOf(".log") !== -1)

        if (criticalName) {
            return true
        }

        if (category === "php" || category === "node-projects") {
            return true
        }

        if (category === "general") {
            return false
        }

        if (sizeValue <= 0) {
            return false
        }

        return name.indexOf("access") === -1
            && name.indexOf("-ssl-access") === -1
    }

    function fileUrlForPath(pathValue) {
        var path = String(pathValue || "")
        if (path.length === 0) {
            return ""
        }
        return "file://" + encodeURI(path)
    }

    function folderUrlForPath(pathValue) {
        var path = String(pathValue || "")
        if (path.length === 0) {
            return ""
        }
        var slash = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
        var folder = slash > 0 ? path.slice(0, slash) : path
        return "file://" + encodeURI(folder)
    }

    function selectedLogSizeBytes() {
        for (var i = 0; i < filteredLogItems.length; i++) {
            var item = filteredLogItems[i]
            if (String(item.id || "") === selectedLogId) {
                return Number(item.size || 0)
            }
        }
        return 0
    }

    function selectedLogPath() {
        for (var i = 0; i < filteredLogItems.length; i++) {
            var item = filteredLogItems[i]
            if (String(item.id || "") === selectedLogId) {
                return String(item.path || "")
            }
        }
        return ""
    }

    function selectedLogName() {
        for (var i = 0; i < filteredLogItems.length; i++) {
            var item = filteredLogItems[i]
            if (String(item.id || "") === selectedLogId) {
                return String(item.name || item.path || "Log")
            }
        }
        return "Log"
    }

    function performRefreshLogs() {
        if (!dashboardBridge) {
            return
        }
        recomputeFilteredLogs()
        if (selectedLogId.length === 0 && filteredLogItems.length > 0) {
            selectedLogId = String(filteredLogItems[0].id || "")
        }
        if (selectedLogId.length === 0) {
            logContent = ""
            return
        }
        if (tailMode) {
            logContent = orderedLogText(dashboardBridge.readLogTail(selectedLogId, tailLines))
            return
        }

        var sizeBytes = selectedLogSizeBytes()
        if (sizeBytes > maxFullReadBytes) {
            logContent = "File is too large for full read (" + sizeBytes
                + " bytes). Showing tail " + tailLines + " lines instead.\n\n"
                + orderedLogText(dashboardBridge.readLogTail(selectedLogId, tailLines))
            return
        }

        logContent = orderedLogText(dashboardBridge.readLogFile(selectedLogId))
    }

    function orderedLogText(rawText) {
        var source = String(rawText || "")
        if (!newestFirst || source.length === 0) {
            return source
        }
        var keepTrailingNewline = source.charAt(source.length - 1) === "\n"
        var lines = source.split("\n")
        if (keepTrailingNewline && lines.length > 0 && lines[lines.length - 1] === "") {
            lines.pop()
        }
        lines.reverse()
        var output = lines.join("\n")
        if (keepTrailingNewline) {
            output += "\n"
        }
        return output
    }

    function requestRefreshLogs() {
        if (!panelOpen) {
            openRefreshQueued = true
            return
        }
        if (refreshBusy || refreshCooldown) {
            refreshQueued = true
            return
        }
        refreshBusy = true
        refreshCooldown = true
        refreshThrottleTimer.restart()
        Qt.callLater(function() {
            performRefreshLogs()
            refreshBusy = false
            if (refreshQueued && !refreshCooldown) {
                refreshQueued = false
                requestRefreshLogs()
            }
        })
    }

    function scheduleOpenRefresh() {
        if (!panelOpen) {
            openRefreshQueued = true
            return
        }
        openRefreshQueued = false
        openRefreshTimer.restart()
    }

    Timer {
        id: openRefreshTimer
        interval: 220
        repeat: false
        onTriggered: root.requestRefreshLogs()
    }

    Timer {
        id: refreshThrottleTimer
        interval: 180
        repeat: false
        onTriggered: {
            root.refreshCooldown = false
            if (root.refreshQueued && !root.refreshBusy) {
                root.refreshQueued = false
                root.requestRefreshLogs()
            }
        }
    }

    Timer {
        id: tailRefreshTimer
        interval: 1000
        repeat: true
        running: root.tailMode
        onTriggered: {
            if (root.tailMode && root.selectedLogId.length > 0) {
                root.requestRefreshLogs()
            }
        }
    }

    onSelectedLogIdChanged: requestRefreshLogs()
    onSelectedCategoryChanged: requestRefreshLogs()
    onTailModeChanged: requestRefreshLogs()
    onDashboardBridgeChanged: requestRefreshLogs()
    onPanelOpenChanged: {
        if (panelOpen) {
            scheduleOpenRefresh()
        } else {
            openRefreshQueued = false
            refreshBusy = false
            refreshQueued = false
            refreshCooldown = false
            refreshThrottleTimer.stop()
            tailRefreshTimer.stop()
        }
    }

    Component.onCompleted: {
        if (panelOpen) {
            scheduleOpenRefresh()
        }
    }

    Connections {
        target: root.dashboardBridge ? root.dashboardBridge : null
        function onDataChanged() {
            root.recomputeFilteredLogs()
            if (!root.panelOpen) {
                return
            }
            if (!root.selectedLogId || root.selectedLogId.length === 0) {
                root.requestRefreshLogs()
                return
            }
            var exists = false
            for (var i = 0; i < root.filteredLogItems.length; i++) {
                if (String(root.filteredLogItems[i].id || "") === root.selectedLogId) {
                    exists = true
                    break
                }
            }
            if (!exists) {
                root.selectedLogId = ""
                return
            }
            root.requestRefreshLogs()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.topMargin: 0
        anchors.bottomMargin: 0
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            ButtonGroup {
                id: categoryFilterGroup
                exclusive: true
            }

            Repeater {
                model: root.categoryFilters

                delegate: FilterTabButton {
                    required property int index
                    property var chip: root.categoryFilters[index]
                    visible: root.categoryFilterVisible(chip.catId)

                    label: String(chip.label || "")
                    active: root.effectiveSelectedCategory() === String(chip.catId || "")

                    onClicked: {
                        root.selectedCategory = String(chip.catId || "all")
                        if (root.selectedLogId.length > 0) {
                            var stillVisible = false
                            for (var i = 0; i < root.filteredLogItems.length; i++) {
                                var it = root.filteredLogItems[i]
                                if (String(it.id || "") === root.selectedLogId && root.categoryVisible(it.category)) {
                                    stillVisible = true
                                    break
                                }
                            }
                            if (!stillVisible) {
                                root.selectedLogId = ""
                            }
                        }
                        root.requestRefreshLogs()
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 6

                Rectangle {
                    height: 26
                    width: tailModeLabel.implicitWidth + tailModeSwitch.implicitWidth + 24
                    radius: 10
                    color: "transparent"

                    Text {
                        id: tailModeLabel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        text: Strings.t("tail.mode")
                        color: Theme.text
                        font.pixelSize: 12
                    }

                    Components.AppSwitch {
                        id: tailModeSwitch
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        implicitHeight: 16
                        height: 16
                        checked: root.tailMode

                        onToggled: function(checked) {
                            root.tailMode = checked
                            root.requestRefreshLogs()
                        }
                    }
                }

                Components.AppComboBox {
                    id: tailLinesCombo
                    Layout.preferredWidth: 84
                    enabled: root.tailMode
                    model: ["100", "200", "500", "1000"]
                    currentIndex: 1
                    onCurrentTextChanged: {
                        root.tailLines = parseInt(currentText)
                        if (root.tailMode) {
                            root.requestRefreshLogs()
                        }
                    }
                }

                IconOnlyButton {
                    iconSource: "../../icons/lucide/rotate-cw.svg"
                    onClicked: root.requestRefreshLogs()
                }

                IconOnlyButton {
                    iconSource: "../../icons/lucide/file-text.svg"
                    tooltip: "Open in Console"
                    onClicked: {
                        if (root.dashboardBridge && root.dashboardBridge.openLogInViewer) {
                            root.dashboardBridge.openLogInViewer(
                                root.selectedLogName(),
                                root.logContent
                            )
                        }
                    }
                }

                IconOnlyButton {
                    iconSource: "../../icons/lucide/filter.svg"
                    tooltip: root.showImportantOnly ? "Important logs only" : "Show all logs"
                    active: root.showImportantOnly
                    accentIconWhenActive: true
                    onClicked: {
                        root.showImportantOnly = !root.showImportantOnly
                        root.requestRefreshLogs()
                    }
                }

                IconOnlyButton {
                    iconSource: "../../icons/lucide/arrow-up-down.svg"
                    tooltip: root.newestFirst ? "Newest first" : "Oldest first"
                    active: root.newestFirst
                    accentIconWhenActive: true
                    onClicked: {
                        root.newestFirst = !root.newestFirst
                        root.requestRefreshLogs()
                    }
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
            color: "transparent"
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

            ListView {
                Layout.preferredWidth: 330
                Layout.leftMargin: -12
                Layout.fillHeight: true
                spacing: 2
                clip: true
                model: root.filteredLogItems
                section.property: "groupLabel"
                section.criteria: ViewSection.FullString
                section.delegate: Text {
                    width: ListView.view.width
                    leftPadding: 8
                    rightPadding: 8
                    topPadding: 5
                    bottomPadding: 3
                    horizontalAlignment: Text.AlignLeft
                    text: String(section)
                    color: Theme.muted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                delegate: Rectangle {
                    required property int index
                    property var itemData: root.filteredLogItems[index]
                    property var pageRoot: root
                    readonly property string itemPath: String((itemData && itemData.path) ? itemData.path : "")
                    width: ListView.view.width
                    height: 22
                    color: String(itemData.id || "") === root.selectedLogId
                        ? (Theme.buttonNeutralBackground)
                        : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        text: String(itemData.name || "")
                        color: Theme.text
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: root.selectedLogId = String(parent.itemData.id || "")
                    }

                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: function(eventPoint) {
                            root.selectedLogId = String(parent.itemData.id || "")
                            logItemMenu.open()
                        }
                    }

                    Native.Menu {
                        id: logItemMenu
                        property var pageRoot: root
                        property string menuItemPath: itemPath
                        Native.MenuItem {
                            text: Strings.t("open.log.file")
                            enabled: logItemMenu.menuItemPath.length > 0
                            onTriggered: Qt.openUrlExternally(logItemMenu.pageRoot.fileUrlForPath(logItemMenu.menuItemPath))
                        }
                        Native.MenuItem {
                            text: Strings.t("reveal.in.finder")
                            enabled: logItemMenu.menuItemPath.length > 0
                            onTriggered: logItemMenu.pageRoot.dashboardBridge.revealInFinder(logItemMenu.menuItemPath)
                        }
                        Native.MenuSeparator {}
                        Native.MenuItem {
                            text: Strings.t("copy.path")
                            enabled: logItemMenu.menuItemPath.length > 0
                            onTriggered: logItemMenu.pageRoot.dashboardBridge.copyTextToClipboard(logItemMenu.menuItemPath)
                        }
                        Native.MenuSeparator {}
                        Native.MenuItem {
                            text: Strings.t("empty")
                            enabled: logItemMenu.menuItemPath.length > 0
                            onTriggered: {
                                if (logItemMenu.pageRoot.dashboardBridge.emptyFile(logItemMenu.menuItemPath)) {
                                    logItemMenu.pageRoot.requestRefreshLogs()
                                }
                            }
                        }
                        Native.MenuItem {
                            text: Strings.t("move.to.trash")
                            enabled: logItemMenu.menuItemPath.length > 0
                            onTriggered: {
                                if (logItemMenu.pageRoot.dashboardBridge.movePathToTrash(logItemMenu.menuItemPath)) {
                                    logItemMenu.pageRoot.requestRefreshLogs()
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
                Layout.fillHeight: true
                color: Theme.surface

                Components.AppScrollEditor {
                    id: logArea
                    anchors.fill: parent
                    text: root.logContent.length > 0 ? root.logContent : "No log selected."
                    readOnly: true
                    showEditActions: false
                    showEmptyAction: true
                    emptyAction: function() {
                        var path = root.selectedLogPath()
                        if (path.length === 0) {
                            return
                        }
                        if (root.dashboardBridge.emptyFile(path)) {
                            root.requestRefreshLogs()
                        }
                    }
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    textFormat: TextEdit.PlainText
                    textColor: Theme.text
                    fontFamily: "Menlo"
                    fontPixelSize: 11
                    selectByMouse: true
                    persistentSelection: true
                    contentPadding: 8
                    borderWidth: 0
                    onEditorFlickChanged: {
                        if (editorFlick) {
                            editorFlick.flickableDirection = Flickable.VerticalFlick
                            editorFlick.boundsBehavior = Flickable.StopAtBounds
                            editorFlick.boundsMovement = Flickable.StopAtBounds
                            editorFlick.contentX = 0
                        }
                    }
                }
            }
        }
    }
}

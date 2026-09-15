import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Native
import QtQuick.Effects
import "../components" as Components
import "../theme"
import "../i18n"

Rectangle {
    id: bottomTerminalPanel

    signal hideRequested()

    required property var terminalBackend
    required property bool bottomTerminalOpen
    required property var statusBarItem
    required property var dashboardBridge
    required property var appWindow
    property bool dockMode: false

    property string activeSessionId: ""
    property var terminalRows: []
    property int cursorX: 0
    property int cursorY: 0
    property string statusText: "Idle"
    property bool cursorVisible: false
    property int fontSize: 12
    property string fontName: "Menlo"
    property real rowHeight: Math.ceil(terminalFontMetrics.lineSpacing)
    property real cellWidth: Math.max(1, cellMetrics.advanceWidth)
    property int terminalPadding: 4
    property int terminalColumns: Math.max(20, Math.floor(((terminalContent.width || 1) - terminalPadding * 2) / cellWidth))
    property int terminalRowCount: Math.max(8, Math.floor((terminalContent.height || 1) / rowHeight))
    property bool terminalScrollBarHoldVisible: false
    property bool terminalAutoScrollRequested: false
    property bool terminalWasNearBottom: true
    property string previousTerminalText: ""
    property bool explicitSessionOpenPending: false
    property bool openRefreshQueued: false
    property bool terminalResizing: false
    property bool terminalWasMinimized: false
    property var terminalSessionCache: ({})
    readonly property int minimumExpandedHeight: 80
    readonly property int maxTerminalTabs: 4

    anchors {
        left: parent.left
        right: parent.right
        bottom: dockMode ? parent.bottom : statusBarItem.top
    }

    height: dockMode
        ? (parent ? parent.height : 0)
        : (bottomTerminalOpen ? Math.min(sharedTerminalHeight(), terminalMaxExpandedHeight()) : 0)
    color: Theme.surfaceAlt
    clip: true
    visible: dockMode ? true : height > 0

    Behavior on height {
        enabled: !bottomTerminalPanel.terminalResizing
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    TextMetrics {
        id: cellMetrics
        font.family: bottomTerminalPanel.fontName
        font.pixelSize: bottomTerminalPanel.fontSize
        text: Strings.t("m")
    }

    FontMetrics {
        id: terminalFontMetrics
        font.family: bottomTerminalPanel.fontName
        font.pixelSize: bottomTerminalPanel.fontSize
    }

    Components.AlertDialog {
        id: terminalLimitAlert
    }

    Item {
        id: terminalResizeTopHandle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 6
        z: 100
        visible: !bottomTerminalPanel.dockMode

        MouseArea {
            id: terminalResizeTopMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            property real dragStartSceneY: 0
            property int dragStartHeight: 0

            onPressed: function(mouse) {
                bottomTerminalPanel.terminalResizing = true
                dragStartSceneY = terminalResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                dragStartHeight = sharedTerminalHeight()
                mouse.accepted = true
            }

            onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) {
                    return
                }
                var currentSceneY = terminalResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                setSharedTerminalHeight(dragStartHeight + (dragStartSceneY - currentSceneY))
            }

            onReleased: function(mouse) {
                bottomTerminalPanel.terminalResizing = false
                if (bottomTerminalPanel.dashboardBridge && bottomTerminalPanel.dashboardBridge.saveBottomTerminalPanelHeight) {
                    bottomTerminalPanel.dashboardBridge.saveBottomTerminalPanelHeight(sharedTerminalHeight())
                }
                bottomTerminalPanel.resizeActiveTerminal()
                Qt.callLater(function() {
                    bottomTerminalPanel.forceTerminalPaintRefresh()
                })
                mouse.accepted = true
            }

            onCanceled: {
                bottomTerminalPanel.terminalResizing = false
                bottomTerminalPanel.resizeActiveTerminal()
            }
        }

    }

    function sharedTerminalHeight() {
        if (bottomTerminalPanel.appWindow && bottomTerminalPanel.appWindow.bottomPanelHeight !== undefined) {
            return Math.max(minimumExpandedHeight, Number(bottomTerminalPanel.appWindow.bottomPanelHeight || minimumExpandedHeight))
        }
        return minimumExpandedHeight
    }

    function terminalMaxExpandedHeight() {
        return Math.max(
            minimumExpandedHeight,
            Math.floor(((parent && parent.height) ? parent.height : 0) * 2 / 3)
        )
    }

    function clampTerminalOpenHeight(nextHeight) {
        return Math.max(
            minimumExpandedHeight,
            Math.min(terminalMaxExpandedHeight(), Math.floor(nextHeight))
        )
    }

    function setSharedTerminalHeight(nextHeight) {
        var clamped = clampTerminalOpenHeight(nextHeight)
        if (bottomTerminalPanel.appWindow && bottomTerminalPanel.appWindow.bottomPanelHeight !== undefined) {
            bottomTerminalPanel.appWindow.bottomPanelHeight = clamped
        }
    }

    component TerminalIconButton: Rectangle {
        id: iconButton

        signal clicked()

        property string iconSource: ""
        property string tooltip: ""

        width: 24
        height: 24
        radius: 12
        color: iconMouse.containsMouse ? Theme.buttonNeutralBackground : "transparent"

        Image {
            id: iconImage
            anchors.centerIn: parent
            width: 16
            height: 16
            sourceSize.width: 16
            sourceSize.height: 16
            source: iconButton.iconSource
            fillMode: Image.PreserveAspectFit
        }

        MultiEffect {
            anchors.fill: iconImage
            source: iconImage
            colorization: 1.0
            colorizationColor: Theme.muted
            brightness: 1.0
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: iconButton.clicked()
        }

        Components.AppToolTip {
            visible: iconButton.tooltip.length > 0 && iconMouse.containsMouse
            delay: 400
            text: iconButton.tooltip
        }
    }

    function ensureDefaultSession() {
        if (!terminalBackend) {
            return
        }

        var sessions = terminalBackend.sessionItems || []

        if (sessions.length === 0) {
            var defaultSessionId = terminalBackend.ensureDefaultSession()
            if (defaultSessionId.length > 0) {
                activateTerminalSession(defaultSessionId)
            }
        } else if (activeSessionId.length === 0) {
            activateTerminalSession(String(sessions[0].id || ""))
        }

        scheduleOpenRefresh()
    }

    function beginExplicitSessionOpen() {
        explicitSessionOpenPending = true
        defaultSessionRetryTimer.stop()
    }

    function finishExplicitSessionOpen() {
        explicitSessionOpenPending = false
    }

    function maybeEnsureDefaultSession() {
        if (explicitSessionOpenPending) {
            return
        }
        ensureDefaultSession()
        defaultSessionRetryTimer.restart()
    }

    function scheduleOpenRefresh() {
        if (!bottomTerminalOpen) {
            openRefreshQueued = true
            return
        }
        openRefreshQueued = false
        terminalPaintRefreshTimer.restart()
    }

    function resizeActiveTerminal() {
        if (terminalResizing) {
            return
        }
        // Do not resize the PTY while the bottom panel is sliding closed.
        // A temporary 0-height panel reports a tiny row count, which makes
        // shells redraw their prompt and leaves duplicate-looking lines when
        // the panel is opened again.
        if (!dockMode && (!bottomTerminalOpen || terminalContent.height < minimumExpandedHeight / 2)) {
            return
        }
        if (terminalBackend && activeSessionId.length > 0) {
            terminalBackend.resizeTerminal(activeSessionId, terminalRowCount, terminalColumns)
        }
    }

    function scheduleTerminalResize() {
        if (terminalResizing || (!dockMode && !bottomTerminalOpen)) {
            return
        }
        terminalResizeTimer.restart()
    }

    function requestActiveScreen() {
        if (terminalBackend && activeSessionId.length > 0) {
            terminalBackend.requestSessionScreen(activeSessionId)
        }
    }

    function cacheCurrentTerminalSession() {
        var sessionId = String(activeSessionId || "")
        if (sessionId.length === 0) {
            return
        }
        terminalSessionCache[sessionId] = {
            rows: terminalRows.slice(0),
            cursorX: cursorX,
            cursorY: cursorY,
            status: statusText,
            previousText: previousTerminalText
        }
    }

    function restoreTerminalSession(sessionId) {
        var snapshot = terminalSessionCache[String(sessionId || "")]
        if (!snapshot) {
            return false
        }
        terminalRows = (snapshot.rows || []).slice(0)
        cursorX = Number(snapshot.cursorX || 0)
        cursorY = Number(snapshot.cursorY || 0)
        statusText = String(snapshot.status || statusText)
        previousTerminalText = String(snapshot.previousText || terminalRows.join("\n"))
        return true
    }

    function activateTerminalSession(sessionId) {
        var nextSessionId = String(sessionId || "")
        if (nextSessionId.length === 0) {
            cacheCurrentTerminalSession()
            activeSessionId = ""
            resetTerminalView(true)
            return
        }

        requestTerminalAutoScroll()
        cacheCurrentTerminalSession()

        if (activeSessionId === nextSessionId) {
            restoreTerminalSession(nextSessionId)
            scrollTerminalToBottom(true)
        } else {
            activeSessionId = nextSessionId
            if (!restoreTerminalSession(nextSessionId)) {
                resetTerminalView(false)
            }
            scrollTerminalToBottom(true)
        }
    }

    function resetTerminalView(resetStatus) {
        terminalRows = []
        cursorX = 0
        cursorY = 0
        previousTerminalText = ""

        if (resetStatus) {
            statusText = "Idle"
        }
    }

    function trimTrailingBlankRows(rows) {
        var trimmed = rows.slice(0)

        while (trimmed.length > 1) {
            var lastRow = String(trimmed[trimmed.length - 1] || "")
            if (!/^\s*$/.test(lastRow)) {
                break
            }
            trimmed.pop()
        }

        return trimmed
    }

    function refreshActiveScreen() {
        if (!terminalBackend || activeSessionId.length === 0) {
            return
        }

        if (terminalBackend.sessionScreen !== undefined) {
            applySessionScreen(terminalBackend.sessionScreen(activeSessionId))
        } else {
            requestActiveScreen()
        }
    }

    function forceTerminalPaintRefresh() {
        if (activeSessionId.length === 0) {
            return
        }
        refreshActiveScreen()
        scrollTerminalToBottom(true)
    }

    function scheduleWindowRestoreRefresh() {
        if (!bottomTerminalOpen || activeSessionId.length === 0) {
            return
        }
        // macOS can restore the window before the ScrollView/TextEdit has its
        // final geometry. Redraw after the restore layout has settled.
        terminalRestoreRefreshTimer.restart()
    }

    function applySessionScreen(snapshot) {
        if (!snapshot || String(snapshot.id || "") !== activeSessionId) {
            return
        }

        var rows = snapshot.rows || []
        var presentationRows = trimTrailingBlankRows(rows)
        var nextText = presentationRows.join("\n")

        terminalRows = presentationRows
        cursorX = Number(snapshot.cursorX || 0)
        cursorY = Number(snapshot.cursorY || 0)
        statusText = String(snapshot.status || statusText)
        previousTerminalText = nextText
        cacheCurrentTerminalSession()

        Qt.callLater(function() {
            scrollTerminalToBottom(true)
        })
    }

    function focusTerminal() {
        terminalFocus.forceActiveFocus()
    }

    function openProfileSession(profileId) {
        if (!terminalBackend) {
            return
        }

        if (!canOpenTerminalProfile(profileId)) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openProfile(String(profileId || ""))

        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function openDefaultSession() {
        if (!terminalBackend) {
            return
        }

        if (!canOpenDefaultTerminalSession()) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openDefaultPhpCli()
        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function openActiveDatabaseSession() {
        if (!terminalBackend) {
            return
        }

        var profileId = terminalBackend.activeDatabaseProfileId()
        if (!profileId || !canOpenTerminalProfile(profileId)) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openActiveDatabaseCli()

        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function openActiveMongodbSession() {
        if (!terminalBackend) {
            return
        }

        var profileId = terminalBackend.activeMongodbProfileId()
        if (!profileId || !canOpenTerminalProfile(profileId)) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openActiveMongodbCli()

        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function openActivePostgresqlSession() {
        if (!terminalBackend) {
            return
        }

        var profileId = terminalBackend.activePostgresqlProfileId()
        if (!profileId || !canOpenTerminalProfile(profileId)) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openActivePostgresqlCli()

        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function openActiveRedisSession() {
        if (!terminalBackend) {
            return
        }

        var profileId = terminalBackend.activeRedisProfileId()
        if (!profileId || !canOpenTerminalProfile(profileId)) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openActiveRedisCli()

        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function openWebsiteSession(siteId) {
        if (!terminalBackend) {
            return
        }

        var profileId = "site:" + String(siteId || "")
        if (!canOpenTerminalProfile(profileId)) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openWebsiteCli(String(siteId || ""))

        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function openNodeProjectSession(projectId) {
        if (!terminalBackend) {
            return
        }

        var profileId = "node-project:" + String(projectId || "")
        if (!canOpenTerminalProfile(profileId)) {
            showTerminalLimitAlert()
            return
        }

        var sessionId = terminalBackend.openNodeProjectCli(String(projectId || ""))

        if (sessionId.length > 0) {
            activateTerminalSession(sessionId)
            resizeActiveTerminal()
            scheduleOpenRefresh()
        }

        Qt.callLater(focusTerminal)
    }

    function canOpenTerminalProfile(profileId) {
        var sessions = terminalBackend ? (terminalBackend.sessionItems || []) : []
        var normalizedProfileId = String(profileId || "")
        for (var i = 0; i < sessions.length; i++) {
            if (String(sessions[i].profileId || "") === normalizedProfileId) {
                return true
            }
        }
        return sessions.length < maxTerminalTabs
    }

    function canOpenDefaultTerminalSession() {
        var sessions = terminalBackend ? (terminalBackend.sessionItems || []) : []
        return sessions.length < maxTerminalTabs
    }

    function showTerminalLimitAlert() {
        terminalLimitAlert.showInfo(
            "Terminal Limit",
            "You can open up to 4 terminal tabs. Close one before opening another."
        )
    }

    function refreshTerminalScrollBarVisibility() {
        if (terminalVBar.hovered || terminalVBar.pressed) {
            terminalScrollBarHoldVisible = true
            terminalScrollBarHideTimer.restart()
        } else {
            terminalScrollBarHideTimer.restart()
        }
    }

    function requestTerminalAutoScroll() {
        terminalAutoScrollRequested = true
    }

    function lockTerminalHorizontalMovement() {
        if (!terminalScroll.contentItem) {
            return
        }

        var flick = terminalScroll.contentItem

        if (flick.flickableDirection !== undefined) {
            flick.flickableDirection = Flickable.VerticalFlick
        }

        if (flick.boundsBehavior !== undefined) {
            flick.boundsBehavior = Flickable.StopAtBounds
        }

        if (flick.contentWidth !== undefined) {
            flick.contentWidth = Math.max(0, flick.width || terminalScroll.width || terminalScroll.availableWidth || 0)
        }

        if (flick.contentX !== undefined) {
            flick.contentX = 0
        }
    }

    function terminalNearBottom() {
        if (!terminalScroll.contentItem) {
            return true
        }

        var flick = terminalScroll.contentItem
        var maxY = Math.max(0, flick.contentHeight - flick.height)

        return flick.contentY >= maxY - Math.max(8, rowHeight)
    }

    function scrollTerminalToBottom(force) {
        if (!terminalScroll.contentItem) {
            return
        }

        var flick = terminalScroll.contentItem

        if (!force && !terminalWasNearBottom && !terminalAutoScrollRequested) {
            return
        }

        flick.contentY = Math.max(0, flick.contentHeight - flick.height)

        if (flick.contentX !== undefined) {
            flick.contentX = 0
        }

        terminalAutoScrollRequested = false
        terminalWasNearBottom = true
    }

    function copySelection() {
        if (terminalText.selectedText.length > 0) {
            terminalText.copy()
            return
        }

        if (terminalBackend && terminalRows.length > 0) {
            terminalBackend.copyText(terminalRows.join("\n"))
        }
    }

    function pasteClipboard() {
        if (terminalBackend && activeSessionId.length > 0) {
            requestTerminalAutoScroll()
            terminalBackend.pasteClipboard(activeSessionId)
        }
    }

    function clearTerminal() {
        if (terminalBackend && activeSessionId.length > 0) {
            requestTerminalAutoScroll()
            if (terminalBackend.clearTerminal) {
                terminalBackend.clearTerminal(activeSessionId)
            } else {
                sendRaw("\x0c")
            }
            clearTerminalRefreshTimer.restart()
        }
    }

    function sendRaw(text) {
        if (terminalBackend && activeSessionId.length > 0) {
            terminalBackend.sendRaw(activeSessionId, text)
        }
    }

    function hasOnlyModifier(event, modifier) {
        var allowed = modifier | Qt.KeypadModifier
        return (event.modifiers & modifier) && ((event.modifiers & ~allowed) === 0)
    }

    function commandModifier() {
        return Qt.platform.os === "osx" ? Qt.ControlModifier : Qt.ControlModifier
    }

    function physicalControlModifier() {
        return Qt.platform.os === "osx" ? Qt.MetaModifier : Qt.ControlModifier
    }

    function acceptShortcutOverride(event) {
        var commandDown = (event.modifiers & commandModifier()) !== 0
        var controlDown = (event.modifiers & physicalControlModifier()) !== 0

        if (commandDown && !controlDown && (event.key === Qt.Key_V || event.key === Qt.Key_C)) {
            event.accepted = true
            return true
        }

        if (controlDown && !commandDown && (event.key === Qt.Key_V || event.key === Qt.Key_C)) {
            event.accepted = true
            return true
        }

        return false
    }

    function sendKey(event) {
        if (activeSessionId.length === 0) {
            event.accepted = true
            return
        }

        var commandDown = (event.modifiers & commandModifier()) !== 0
        var controlDown = (event.modifiers & physicalControlModifier()) !== 0

        if (commandDown && !controlDown) {
            if (event.key === Qt.Key_V) {
                pasteClipboard()
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_C) {
                copySelection()
                event.accepted = true
                return
            }

            event.accepted = true
            return
        }

        if (controlDown && !commandDown) {
            if (event.key === Qt.Key_C) {
                requestTerminalAutoScroll()
                terminalBackend.sendInterrupt(activeSessionId)
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_V) {
                sendRaw("\x16")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_D) {
                requestTerminalAutoScroll()
                sendRaw("\x04")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_L) {
                requestTerminalAutoScroll()
                sendRaw("\x0c")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_A) {
                sendRaw("\x01")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_E) {
                sendRaw("\x05")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_U) {
                sendRaw("\x15")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_K) {
                sendRaw("\x0b")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_W) {
                sendRaw("\x17")
                event.accepted = true
                return
            }

            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            requestTerminalAutoScroll()
            sendRaw("\r")
        } else if (event.key === Qt.Key_Backspace) {
            sendRaw("\x7f")
        } else if (event.key === Qt.Key_Delete) {
            sendRaw("\x1b[3~")
        } else if (event.key === Qt.Key_Tab) {
            sendRaw("\t")
        } else if (event.key === Qt.Key_Left) {
            sendRaw("\x1b[D")
        } else if (event.key === Qt.Key_Right) {
            sendRaw("\x1b[C")
        } else if (event.key === Qt.Key_Up) {
            sendRaw("\x1b[A")
        } else if (event.key === Qt.Key_Down) {
            sendRaw("\x1b[B")
        } else if (event.key === Qt.Key_Home) {
            sendRaw("\x01")
        } else if (event.key === Qt.Key_End) {
            sendRaw("\x05")
        } else if (event.key === Qt.Key_Escape) {
            sendRaw("\x1b")
        } else if (event.text.length > 0) {
            sendRaw(event.text)
        } else {
            event.accepted = true
            return
        }

        event.accepted = true
    }

    Timer {
        id: defaultSessionRetryTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (bottomTerminalPanel.bottomTerminalOpen
                    && !bottomTerminalPanel.explicitSessionOpenPending
                    && bottomTerminalPanel.activeSessionId.length === 0) {
                bottomTerminalPanel.ensureDefaultSession()
            }
        }
    }

    Timer {
        id: terminalPaintRefreshTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (!bottomTerminalPanel.bottomTerminalOpen || bottomTerminalPanel.activeSessionId.length === 0) {
                return
            }

            bottomTerminalPanel.openRefreshQueued = false
            bottomTerminalPanel.focusTerminal()
            bottomTerminalPanel.forceTerminalPaintRefresh()
        }
    }

    Timer {
        id: clearTerminalRefreshTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (bottomTerminalPanel.activeSessionId.length === 0) {
                return
            }

            if (terminalScroll.contentItem) {
                terminalScroll.contentItem.contentX = 0
                terminalScroll.contentItem.contentY = 0
            }
            terminalAutoScrollRequested = true
            terminalWasNearBottom = true
            bottomTerminalPanel.forceTerminalPaintRefresh()
            bottomTerminalPanel.scrollTerminalToBottom(true)
            bottomTerminalPanel.focusTerminal()
        }
    }

    Timer {
        id: terminalRestoreRefreshTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (!bottomTerminalPanel.bottomTerminalOpen || bottomTerminalPanel.activeSessionId.length === 0) {
                return
            }
            bottomTerminalPanel.resetTerminalView(false)
            bottomTerminalPanel.resizeActiveTerminal()
            bottomTerminalPanel.requestActiveScreen()
            Qt.callLater(function() {
                bottomTerminalPanel.forceTerminalPaintRefresh()
            })
        }
    }

    Timer {
        id: terminalResizeTimer
        interval: 180
        repeat: false
        onTriggered: bottomTerminalPanel.resizeActiveTerminal()
    }

    Timer {
        id: terminalScrollBarHideTimer
        interval: 1200
        repeat: false
        onTriggered: bottomTerminalPanel.terminalScrollBarHoldVisible = false
    }

    onBottomTerminalOpenChanged: {
        if (!bottomTerminalOpen) {
            openRefreshQueued = false
            terminalPaintRefreshTimer.stop()
            return
        }

        scheduleOpenRefresh()
        if (activeSessionId.length === 0) {
            requestTerminalAutoScroll()
            Qt.callLater(maybeEnsureDefaultSession)
        }
    }

    onVisibleChanged: {
        if (visible && bottomTerminalOpen && activeSessionId.length === 0) {
            requestTerminalAutoScroll()
            Qt.callLater(maybeEnsureDefaultSession)
        }
    }

    Component.onCompleted: {
        if (bottomTerminalOpen && activeSessionId.length === 0) {
            requestTerminalAutoScroll()
            Qt.callLater(maybeEnsureDefaultSession)
        }
    }

    onActiveSessionIdChanged: {
        terminalAutoScrollRequested = true
        terminalWasNearBottom = true

        if (terminalScroll.contentItem) {
            terminalScroll.contentItem.contentX = 0
            terminalScroll.contentItem.contentY = 0
        }

        if (!restoreTerminalSession(activeSessionId)) {
            resetTerminalView(false)
        }

        Qt.callLater(focusTerminal)
    }

    onTerminalColumnsChanged: scheduleTerminalResize()
    onTerminalRowCountChanged: scheduleTerminalResize()
    onHeightChanged: scheduleTerminalResize()

    Connections {
        target: bottomTerminalPanel.terminalBackend

        function onScreenUpdated(sessionId, rows, x, y) {
            if (String(sessionId || "") !== bottomTerminalPanel.activeSessionId) {
                return
            }

            terminalWasNearBottom = terminalNearBottom()

            var nextText = rows.join("\n")
            var textChanged = nextText !== previousTerminalText
            var rowCountChanged = rows.length !== terminalRows.length

            terminalRows = rows.slice(0)
            cursorX = x
            cursorY = y
            previousTerminalText = nextText
            cacheCurrentTerminalSession()

            if ((textChanged || rowCountChanged || terminalAutoScrollRequested) && Number(cursorY) > 12) {
                Qt.callLater(function() {
                    scrollTerminalToBottom(terminalAutoScrollRequested || terminalWasNearBottom || rowCountChanged)
                })
            }
        }

        function onStatusChanged(sessionId, text) {
            if (String(sessionId || "") === bottomTerminalPanel.activeSessionId) {
                statusText = text
            }
        }

        function onSessionItemsChanged() {
            var sessions = terminalBackend.sessionItems || []
            var found = false

            for (var i = 0; i < sessions.length; i++) {
                if (String(sessions[i].id) === bottomTerminalPanel.activeSessionId) {
                    found = true
                    break
                }
            }

            if (!found) {
                bottomTerminalPanel.activateTerminalSession(sessions.length > 0 ? String(sessions[0].id) : "")

                if (bottomTerminalPanel.activeSessionId.length === 0) {
                    bottomTerminalPanel.resetTerminalView(true)
                }
            }
        }
    }

    Connections {
        target: bottomTerminalPanel.appWindow
        ignoreUnknownSignals: true

        function onWindowStateChanged(state) {
            if (state === Window.Minimized) {
                bottomTerminalPanel.terminalWasMinimized = true
                return
            }
            if (bottomTerminalPanel.terminalWasMinimized) {
                bottomTerminalPanel.terminalWasMinimized = false
                bottomTerminalPanel.scheduleWindowRestoreRefresh()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        anchors.topMargin: 0
        anchors.bottomMargin: 0
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 6

                Flickable {
                    id: terminalTabsFlickable

                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    Layout.leftMargin: 6

                    contentWidth: terminalTabsRow.implicitWidth
                    contentHeight: height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick

                    RowLayout {
                        id: terminalTabsRow

                        height: terminalTabsFlickable.height
                        width: implicitWidth
                        spacing: 6

                        Repeater {
                            model: terminalBackend ? terminalBackend.sessionItems : []

                            delegate: Rectangle {
                                property string sessionId: String(modelData.id || "")
                                property bool selected: bottomTerminalPanel.activeSessionId === sessionId

                                Layout.preferredWidth: Math.min(156, tabLabel.implicitWidth + closeTab.width + 18)
                                Layout.preferredHeight: 26
                                Layout.alignment: Qt.AlignVCenter

                                radius: 6
                                color: selected ?
                                    (Theme.buttonNeutralBackground) :
                                    (tabMouse.containsMouse ? Theme.buttonNeutralBackground : "transparent")

                                Text {
                                    id: tabLabel
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.right: closeTab.left
                                    anchors.rightMargin: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(modelData.title || "Local")
                                    color: Theme.text
                                    font.pixelSize: 12
                                    font.weight: Font.Normal
                                    elide: Text.ElideRight
                                }

                                Item {
                                    id: closeTab
                                    anchors.right: parent.right
                                    anchors.rightMargin: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16

                                    Image {
                                        id: closeIconImage
                                        anchors.centerIn: parent
                                        width: 13
                                        height: 13
                                        sourceSize.width: 13
                                        sourceSize.height: 13
                                        source: "../icons/lucide/x.svg"
                                        visible: false
                                    }

                                    MultiEffect {
                                        anchors.fill: closeIconImage
                                        source: closeIconImage
                                        colorization: 1.0
                                        colorizationColor: closeMouse.containsMouse ? Theme.text : Theme.muted
                                        brightness: 1.0
                                    }

                                    MouseArea {
                                        id: closeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: terminalBackend.closeSession(sessionId)
                                    }
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    anchors.rightMargin: 22
                                    hoverEnabled: true

                                    onClicked: {
                                        bottomTerminalPanel.activateTerminalSession(sessionId)
                                        bottomTerminalPanel.focusTerminal()
                                    }
                                }
                            }
                        }



                        Components.TerminalProfileMenuButton {
                            Layout.alignment: Qt.AlignVCenter
                            tooltip: "New terminal"
                            profiles: bottomTerminalPanel.terminalBackend ?
                                bottomTerminalPanel.terminalBackend.profileItems.filter(function(profile) {
                                    return String(profile.kind || "") === "php"
                                }) :
                                []

                            onProfileSelected: function(profileId) {
                                bottomTerminalPanel.openProfileSession(profileId)
                            }
                        }

                    }
                }

                TerminalIconButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 6

                    iconSource: "../icons/lucide/minus.svg"
                    tooltip: "Hide"
                    onClicked: bottomTerminalPanel.hideRequested()
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
            color: Theme.border
        }

        FocusScope {
            id: terminalFocus
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: bottomTerminalPanel.bottomTerminalOpen
            activeFocusOnTab: true

            Keys.priority: Keys.BeforeItem

            Keys.onShortcutOverride: function(event) {
                bottomTerminalPanel.acceptShortcutOverride(event)
            }

            Keys.onPressed: function(event) {
                bottomTerminalPanel.sendKey(event)
            }

            Rectangle {
                id: terminalViewport
                anchors.fill: parent
                color: Theme.surface
                border.width: 0
                clip: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    propagateComposedEvents: true
                    onPressed: function(mouse) {
                        bottomTerminalPanel.focusTerminal()
                        mouse.accepted = false
                    }
                }

                Item {
                    id: terminalContent
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 0
                    clip: true

                    Native.Menu {
                        id: terminalContextMenu

                        Native.MenuItem {
                            text: Strings.t("copy")
                            enabled: bottomTerminalPanel.terminalRows.length > 0
                            onTriggered: bottomTerminalPanel.copySelection()
                        }

                        Native.MenuItem {
                            text: Strings.t("paste")
                            enabled: bottomTerminalPanel.activeSessionId.length > 0
                            onTriggered: bottomTerminalPanel.pasteClipboard()
                        }

                        Native.MenuItem {
                            text: "Clear Terminal"
                            enabled: bottomTerminalPanel.activeSessionId.length > 0
                            onTriggered: bottomTerminalPanel.clearTerminal()
                        }

                        Native.MenuSeparator {}

                        Native.MenuItem {
                            text: Strings.t("interrupt")
                            enabled: bottomTerminalPanel.activeSessionId.length > 0
                            onTriggered: {
                                bottomTerminalPanel.requestTerminalAutoScroll()
                                bottomTerminalPanel.terminalBackend.sendInterrupt(bottomTerminalPanel.activeSessionId)
                            }
                        }
                    }

                    ScrollView {
                        id: terminalScroll
                        anchors.fill: parent
                        clip: true

                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ScrollBar.vertical: ScrollBar {
                            id: terminalVBar

                            policy: ScrollBar.AsNeeded
                            hoverEnabled: true

                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.rightMargin: 2

                            width: 7

                            opacity: (hovered || pressed || bottomTerminalPanel.terminalScrollBarHoldVisible) ? 1.0 : 0.0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 140
                                }
                            }

                            onHoveredChanged: bottomTerminalPanel.refreshTerminalScrollBarVisibility()
                            onPressedChanged: bottomTerminalPanel.refreshTerminalScrollBarVisibility()

                            background: Rectangle {
                                implicitWidth: 7
                                implicitHeight: 100
                                radius: 3.5
                                color: Theme.dark ? "#202a38" : "#d8dde4"
                                opacity: 0.55
                            }

                            contentItem: Rectangle {
                                implicitWidth: 7
                                implicitHeight: 32
                                radius: 3.5
                                color: Theme.dark ? "#8f98a6" : "#8a93a1"
                                opacity: terminalVBar.pressed ? 1.0 : 0.92
                            }
                        }

                        onContentItemChanged: {
                            bottomTerminalPanel.lockTerminalHorizontalMovement()
                        }

                        Connections {
                            target: terminalScroll.contentItem
                            ignoreUnknownSignals: true

                            function onMovingChanged() {
                                if (terminalScroll.contentItem && !terminalScroll.contentItem.moving) {
                                    bottomTerminalPanel.terminalWasNearBottom = bottomTerminalPanel.terminalNearBottom()
                                }
                            }
                        }

                        TextEdit {
                            id: terminalText
                            text: terminalRows.join("\n")
                            readOnly: true
                            cursorVisible: false
                            activeFocusOnPress: false
                            focus: false

                            color: Theme.text
                            font.family: fontName
                            font.pixelSize: fontSize
                            font.kerning: false
                            font.preferShaping: false

                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.NoWrap
                            width: terminalScroll.availableWidth
                            selectByMouse: true
                            persistentSelection: true
                            textMargin: terminalPadding

                            Text {
                                id: terminalBlinkCursor
                                visible: bottomTerminalPanel.activeSessionId.length > 0
                                text: "_"
                                color: Theme.text
                                font.family: fontName
                                font.pixelSize: fontSize
                                font.kerning: false
                                font.preferShaping: false
                                x: terminalPadding + cursorX * cellWidth
                                y: cursorY * rowHeight + 4
                                opacity: cursorBlinkTimer.cursorOn ? 1.0 : 0.0
                                z: 20
                            }

                            Timer {
                                id: cursorBlinkTimer
                                property bool cursorOn: true
                                interval: 500
                                repeat: true
                                running: bottomTerminalPanel.bottomTerminalOpen && bottomTerminalPanel.activeSessionId.length > 0
                                onTriggered: cursorOn = !cursorOn
                            }

                            onTextChanged: {
                                bottomTerminalPanel.lockTerminalHorizontalMovement()
                            }

                            TapHandler {
                                acceptedButtons: Qt.RightButton

                                onTapped: function(_) {
                                    bottomTerminalPanel.focusTerminal()
                                    terminalContextMenu.open()
                                }
                            }
                        }
                    }

                    Text {
                        visible: activeSessionId.length === 0
                        anchors.centerIn: parent
                        text: Strings.t("no.terminal.session")
                        color: Theme.muted
                        font.pixelSize: 12
                        z: 200
                    }
                }
            }
        }
    }
}

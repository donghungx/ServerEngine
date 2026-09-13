import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Native
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root
    anchors.fill: parent

    signal hideRequested()

    required property var dashboardBridge
    required property bool panelOpen
    // QtWebEngine is optional in development and may not be bundled.
    property bool mailpitWebEngineAvailable: false

    property var mailboxItems: []
    property var readMessageIds: ({})
    property var selectedMessage: ({})
    property string selectedMessageBody: ""
    property string selectedMessageHtmlBody: ""
    property string selectedMessageWebHtml: ""
    property string selectedMessageWebBaseUrl: ""
    property bool selectedMessageBodyIsHtml: false
    property bool mailboxLoading: false
    property bool selectedMessageLoading: false
    property string emptyText: "No mail yet."

    function isMailboxRunning() {
        return String(dashboardBridge.mailpitServiceState || "").toLowerCase() === "running"
    }

    function requestRefreshMailbox() {
        refreshMailbox()
    }

    function currentMessageId() {
        return String(selectedMessage && selectedMessage.id ? selectedMessage.id : "")
    }

    function selectMessage(messageItem, refreshBody) {
        var item = messageItem || {}
        var messageId = String(item.id || "").trim()
        if (messageId.length === 0) {
            selectedMessage = ({})
            selectedMessageBody = ""
            selectedMessageHtmlBody = ""
            selectedMessageWebHtml = ""
            selectedMessageWebBaseUrl = ""
            selectedMessageBodyIsHtml = false
            selectedMessageLoading = false
            return
        }
        readMessageIds[messageId] = true
        readMessageIds = readMessageIds
        item = Object.assign({}, item, { read: true })
        selectedMessage = item
        selectedMessageBody = String((item && (item.body_text || item.body || item.snippet)) || "")
        selectedMessageHtmlBody = ""
        selectedMessageWebHtml = String((item && (item.web_html || item.body_html || item.html)) || "")
        selectedMessageWebBaseUrl = String((item && item.web_base_url) || (dashboardBridge && dashboardBridge.mailpitWebUrl) || "")
        selectedMessageBodyIsHtml = false
        if (refreshBody !== false) {
            selectedMessageLoading = true
            deferredDetailRefreshTimer.restart()
        } else {
            selectedMessageLoading = false
        }
    }

    function refreshSelectedMessageDetail() {
        var messageId = currentMessageId()
        if (!panelOpen || !dashboardBridge || !dashboardBridge.mailpitMailboxMessage || messageId.length === 0) {
            selectedMessageLoading = false
            return
        }

        var detail = dashboardBridge.mailpitMailboxMessage(messageId)
        var selected = detail && Object.keys(detail || {}).length > 0 ? detail : selectedMessage
        selectedMessage = selected
        selectedMessageBody = String((selected && (selected.body_text || selected.body || selected.body_html || selected.html)) || "")
        selectedMessageHtmlBody = String((selected && (selected.body_html || selected.html)) || "")
        selectedMessageWebHtml = String((selected && (selected.web_html || selected.body_html || selected.html)) || "")
        selectedMessageWebBaseUrl = String((selected && selected.web_base_url) || (dashboardBridge && dashboardBridge.mailpitWebUrl) || "")
        selectedMessageBodyIsHtml = String((selected && (selected.html || selected.body_html)) || "").trim().length > 0
        selectedMessageLoading = false
    }

    function refreshMailbox() {
        if (!panelOpen || !dashboardBridge || !dashboardBridge.mailpitMailboxMessages) {
            mailboxLoading = false
            return
        }
        mailboxLoading = true
        if (!isMailboxRunning()) {
            mailboxItems = []
            selectedMessage = ({})
            selectedMessageBody = ""
            selectedMessageHtmlBody = ""
            selectedMessageWebHtml = ""
            selectedMessageWebBaseUrl = ""
            selectedMessageBodyIsHtml = false
            selectedMessageLoading = false
            mailboxLoading = false
            return
        }

        var nextItems = dashboardBridge.mailpitMailboxMessages(100) || []
        for (var itemIndex = 0; itemIndex < nextItems.length; itemIndex++) {
            var itemId = String(nextItems[itemIndex] && nextItems[itemIndex].id || "")
            if (readMessageIds[itemId]) {
                nextItems[itemIndex] = Object.assign({}, nextItems[itemIndex], { read: true })
            }
        }
        mailboxItems = nextItems
        mailboxLoading = false
        if (nextItems.length === 0) {
            selectedMessage = ({})
            selectedMessageBody = ""
            selectedMessageHtmlBody = ""
            selectedMessageWebHtml = ""
            selectedMessageWebBaseUrl = ""
            selectedMessageBodyIsHtml = false
            selectedMessageLoading = false
            return
        }

        var selectedId = currentMessageId()
        var nextItem = null
        for (var i = 0; i < nextItems.length; i++) {
            var candidate = nextItems[i]
            if (String(candidate && candidate.id ? candidate.id : "") === selectedId) {
                nextItem = candidate
                break
            }
        }
        if (!nextItem) {
            nextItem = nextItems[0]
            selectMessage(nextItem, true)
            return
        }
        selectedMessage = Object.assign({}, selectedMessage || {}, nextItem || {})
    }

    function messagePreviewText(messageItem) {
        var preview = String(messageItem && messageItem.snippet ? messageItem.snippet : "")
        if (preview.length === 0) {
            return ""
        }
        return preview
    }

    function humanReadableMessageDate(rawValue) {
        var raw = String(rawValue || "").trim()
        if (raw.length === 0) {
            return ""
        }
        var parsed = new Date(raw)
        if (!isNaN(parsed.getTime())) {
            return Qt.formatDateTime(parsed, "ddd MMM d yyyy hh:mm")
        }
        return raw
    }

    function selectedMessageDateText() {
        return root.humanReadableMessageDate(root.selectedMessage.date || root.selectedMessage.created)
    }

    function selectedMessageBodyText() {
        return root.selectedMessageBodyIsHtml
            ? String(root.selectedMessageHtmlBody || "")
            : String(root.selectedMessageBody || "")
    }

    function selectedMessageBodyFormat() {
        return root.selectedMessageBodyIsHtml ? TextEdit.RichText : TextEdit.PlainText
    }

    Component.onCompleted: {
        if (panelOpen) {
            deferredRefreshTimer.restart()
        }
    }

    onPanelOpenChanged: {
        if (panelOpen) {
            deferredRefreshTimer.restart()
        }
    }

    Connections {
        target: dashboardBridge
        function onMailpitRuntimeFeedbackChanged() {
            if (root.panelOpen) {
                root.refreshMailbox()
            }
        }

        function onMailpitMailboxChanged() {
            if (root.panelOpen) {
                root.refreshMailbox()
            }
        }

        function onAppSettingsFeedbackChanged() {
            if (root.panelOpen) {
                root.refreshMailbox()
            }
        }
    }

    Timer {
        id: autoRefreshTimer
        interval: 5000
        repeat: true
        running: root.panelOpen && root.isMailboxRunning() && !Boolean(dashboardBridge.mailpitMailboxLiveUpdates)
        onTriggered: root.refreshMailbox()
    }

    Timer {
        id: deferredRefreshTimer
        interval: 220
        repeat: false
        onTriggered: root.refreshMailbox()
    }

    Timer {
        id: deferredDetailRefreshTimer
        interval: 0
        repeat: false
        onTriggered: root.refreshSelectedMessageDetail()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surfaceAlt
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 29
                color: Theme.surfaceAlt
                border.width: 0

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.bottomMargin: 3
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter

                        Label {
                            text: "Mailbox"
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Label {
                            text: mailboxItems.length === 0
                                ? "No mail yet."
                                : (mailboxItems.length + " messages")
                            color: Theme.muted
                            font.pixelSize: 11
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter

                        Components.QuickActionButton {
                            iconSource: "icons/lucide/rotate-cw.svg"
                            tooltip: Strings.t("reload")
                            onClicked: root.refreshMailbox()
                        }

                        Components.QuickActionButton {
                            iconSource: "icons/lucide/minus.svg"
                            tooltip: "Hide"
                            onClicked: root.hideRequested()
                        }
                    }

                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    Layout.preferredWidth: 360
                    Layout.minimumWidth: 280
                    Layout.fillHeight: true

                    Components.AppScrollArea {
                        anchors.fill: parent
                        color: Theme.surface
                        showBorder: false
                        viewportMargins: 0

                        Item {
                            width: parent.width
                            height: Math.max(1, messageList.contentHeight + 16)

                            ListView {
                                id: messageList
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: true
                                interactive: false
                                model: root.mailboxItems
                                currentIndex: -1
                                spacing: 0

                            delegate: Rectangle {
                                id: delegateRoot
                                required property var modelData
                                required property int index
                                x: 8
                                width: Math.max(0, ListView.view.width)
                                height: 72
                                radius: 8
                                color: String(root.selectedMessage.id || "") === String(modelData.id || "")
                                    ? Theme.accentStrong
                                    : "transparent"
                                border.width: 0
                                antialiasing: true

                                property var messageItem: modelData
                                property bool isSelected: String(root.selectedMessage.id || "") === String(modelData.id || "")

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 3
                                    Layout.alignment: Qt.AlignTop

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 4

                                        Rectangle {
                                            width: 7
                                            height: 7
                                            radius: 3.5
                                            color: messageItem.read ? "transparent" : (delegateRoot.isSelected ? "white" : Theme.accentStrong)
                                            visible: !messageItem.read
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: messageItem.subject || "(No subject)"
                                            color: delegateRoot.isSelected ? "white" : Theme.text
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: messageItem.from || ""
                                        color: delegateRoot.isSelected ? "white" : Theme.text
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.messagePreviewText(messageItem)
                                        color: delegateRoot.isSelected ? "#f2f2f2" : Theme.muted
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        wrapMode: Text.NoWrap
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: false
                                    acceptedButtons: Qt.LeftButton
                                    preventStealing: true
                                    onClicked: root.selectMessage(messageItem, true)
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    height: 1
                                    visible: !delegateRoot.isSelected
                                        && delegateRoot.index < (root.mailboxItems.length - 1)
                                    color: delegateRoot.isSelected ? "transparent" : Theme.border
                                }
                            }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: root.mailboxItems.length === 0

                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 24, 260)
                            spacing: 6

                            Label {
                                width: parent.width
                                text: "Mailbox empty"
                                color: Theme.text
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Label {
                                width: parent.width
                                text: "Mail sent to Mailpit will appear here."
                                color: Theme.muted
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    color: Theme.border
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Components.AppScrollArea {
                        id: mailScrollArea
                        anchors.fill: parent
                        color: Theme.surface
                        showBorder: false
                        viewportMargins: 0

                        Item {
                            width: parent.width
                            implicitHeight: contentColumn.implicitHeight + 24

                            Column {
                                id: contentColumn
                                x: 12
                                y: 12
                                width: parent.width - 24
                                spacing: 8
                                Item {
                                    width: parent.width
                                    implicitHeight: messageMetaColumn.implicitHeight
                                    visible: String(root.selectedMessage.id || "").length > 0

                                    Column {
                                        id: messageMetaColumn
                                        width: parent.width
                                        spacing: 4

                                        RowLayout {
                                            width: parent.width
                                            spacing: 6

                                            Label {
                                                text: "Subject"
                                                color: Theme.muted
                                                font.pixelSize: 12
                                            }
                                            Label {
                                                text: String(root.selectedMessage.subject || "")
                                                color: Theme.text
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }

                                        RowLayout {
                                            width: parent.width
                                            spacing: 6

                                            Label {
                                                text: "From"
                                                color: Theme.muted
                                                font.pixelSize: 12
                                            }
                                            Label {
                                                text: String(root.selectedMessage.from || "")
                                                color: Theme.text
                                                font.pixelSize: 12
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }

                                        RowLayout {
                                            width: parent.width
                                            spacing: 6

                                            Label {
                                                text: "To"
                                                color: Theme.muted
                                                font.pixelSize: 12
                                            }
                                            Label {
                                                text: String(root.selectedMessage.to || "")
                                                color: Theme.text
                                                font.pixelSize: 12
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }

                                        RowLayout {
                                            width: parent.width
                                            spacing: 6

                                            Label {
                                                text: "Date"
                                                color: Theme.muted
                                                font.pixelSize: 11
                                            }
                                            Label {
                                                text: root.selectedMessageDateText()
                                                color: Theme.text
                                                font.pixelSize: 12
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Theme.border
                                    visible: String(root.selectedMessage.id || "").length > 0
                                }

                                Item {
                                    width: parent.width
                                    height: 180
                                    visible: root.mailboxLoading || root.selectedMessageLoading

                                    BusyIndicator {
                                        anchors.centerIn: parent
                                        running: true
                                    }
                                }

                                Loader {
                                    id: messageBodyLoader
                                    width: parent.width
                                    visible: !root.selectedMessageLoading
                                    active: root.panelOpen
                                        && Boolean(mailpitWebEngineAvailable)
                                        && String(root.selectedMessageWebHtml || "").length > 0
                                    source: active ? Qt.resolvedUrl("MailBodyWebView.qml") : ""
                                    height: item ? item.implicitHeight : 0
                                    onLoaded: {
                                        if (item) {
                                            item.pageRoot = root
                                            item.scrollTarget = mailScrollArea.flick
                                        }
                                    }
                                }

                                TextEdit {
                                    id: bodyText
                                    width: parent.width
                                    visible: !root.selectedMessageLoading
                                        && (!Boolean(mailpitWebEngineAvailable) || String(root.selectedMessageWebHtml || "").length === 0)
                                    text: root.selectedMessageBodyText()
                                    color: Theme.text
                                    font.pixelSize: 12
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                    textFormat: root.selectedMessageBodyFormat()

                                    function openContextMenu() {
                                        forceActiveFocus()
                                        bodyContextMenu.open()
                                    }

                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: function(_) {
                                            bodyText.openContextMenu()
                                        }
                                    }

                                    Native.Menu {
                                        id: bodyContextMenu
                                        Native.MenuItem {
                                            text: Strings.t("copy")
                                            enabled: bodyText.selectedText.length > 0
                                            onTriggered: bodyText.copy()
                                        }
                                        Native.MenuItem {
                                            text: Strings.t("select.all")
                                            enabled: bodyText.length > 0
                                            onTriggered: bodyText.selectAll()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: String(root.selectedMessage.id || "").length === 0

                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 24, 420)
                            spacing: 6

                            Label {
                                width: parent.width
                                text: root.mailboxItems.length > 0 ? "Select a message to read it." : root.emptyText
                                color: Theme.muted
                                font.pixelSize: 24
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }

                            Label {
                                width: parent.width
                                text: root.mailboxItems.length > 0
                                    ? "Preview subject, from, to, and message body here."
                                    : "Send mail to Mailpit and it will appear in the list."
                                color: Theme.muted
                                opacity: 0.85
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}

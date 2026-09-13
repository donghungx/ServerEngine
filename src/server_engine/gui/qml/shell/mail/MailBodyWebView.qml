import QtQuick
import QtWebEngine
import Qt.labs.platform as Native
import "../../theme"

Item {
    id: root

    property var pageRoot: null
    property var scrollTarget: null
    property string contextMenuSelectedText: ""
    property string contextMenuLinkUrl: ""
    property string contextMenuLinkText: ""
    property string contextMenuMediaUrl: ""
    property int contextMenuMediaType: -1
    property real contentHeight: 1
    property string loadedHtml: ""
    property string loadedBaseUrl: ""
    property string loadedMessageId: ""
    implicitHeight: Math.max(1, contentHeight)
    height: implicitHeight

    function currentHtml() {
        return String(pageRoot && pageRoot.selectedMessageWebHtml ? pageRoot.selectedMessageWebHtml : "")
    }

    function currentBaseUrl() {
        return String(pageRoot && pageRoot.selectedMessageWebBaseUrl ? pageRoot.selectedMessageWebBaseUrl : "")
    }

    function refresh() {
        if (!webView) {
            return
        }
        var nextHtml = root.currentHtml()
        var nextBaseUrl = root.currentBaseUrl()
        var nextMessageId = String(root.pageRoot && root.pageRoot.selectedMessage && root.pageRoot.selectedMessage.id
            ? root.pageRoot.selectedMessage.id
            : "")

        if (nextHtml === root.loadedHtml
                && nextBaseUrl === root.loadedBaseUrl
                && nextMessageId === root.loadedMessageId) {
            return
        }

        // Reset the outer scroll position and drop the previous measured height
        // before loading a new message. This prevents a long message from
        // leaving the container stuck at the old height.
        contentHeight = 1
        if (root.scrollTarget && root.scrollTarget.contentY !== undefined) {
            root.scrollTarget.contentY = 0
        }
        root.loadedHtml = nextHtml
        root.loadedBaseUrl = nextBaseUrl
        root.loadedMessageId = nextMessageId
        webView.loadHtml(nextHtml, nextBaseUrl)
    }

    function measureContent() {
        if (!webView) {
            return
        }
        var size = webView.contentsSize
        var nextHeight = Number(size && size.height !== undefined ? size.height : 0)
        if (!isNaN(nextHeight) && nextHeight > 0) {
            root.contentHeight = nextHeight
        }
    }

    function clamp(value, minimum, maximum) {
        return Math.min(Math.max(value, minimum), maximum)
    }

    function scrollOuterArea(event) {
        var target = root.scrollTarget
        if (!target) {
            return
        }

        var deltaY = 0
        if (event.pixelDelta && event.pixelDelta.y) {
            deltaY = event.pixelDelta.y
        } else if (event.angleDelta && event.angleDelta.y) {
            deltaY = event.angleDelta.y / 120 * 48
        }

        if (deltaY === 0) {
            return
        }

        var maxContentY = Math.max(0, (target.contentHeight || 0) - (target.height || 0))
        var nextContentY = root.clamp((target.contentY || 0) - deltaY, 0, maxContentY)
        target.contentY = nextContentY
        event.accepted = true
    }

    function openSearchWithGoogle() {
        var text = String(root.contextMenuSelectedText || "").trim()
        if (text.length === 0) {
            return
        }
        Qt.openUrlExternally("https://www.google.com/search?q=" + encodeURIComponent(text))
    }

    function copySelection() {
        webView.triggerWebAction(WebEngineView.Copy)
    }

    function selectAll() {
        webView.triggerWebAction(WebEngineView.SelectAll)
    }

    function openLink() {
        var url = String(root.contextMenuLinkUrl || "").trim()
        if (url.length > 0) {
            Qt.openUrlExternally(url)
        }
    }

    function copyLink() {
        webView.triggerWebAction(WebEngineView.CopyLinkToClipboard)
    }

    function copyImage() {
        webView.triggerWebAction(WebEngineView.CopyImageToClipboard)
    }

    function copyImageUrl() {
        webView.triggerWebAction(WebEngineView.CopyImageUrlToClipboard)
    }

    function copyMediaUrl() {
        webView.triggerWebAction(WebEngineView.CopyMediaUrlToClipboard)
    }

    Component.onCompleted: refresh()

    onPageRootChanged: {
        refresh()
    }

    onWidthChanged: {
        root.measureContent()
    }

    Connections {
        target: root.pageRoot
        ignoreUnknownSignals: true

        function onSelectedMessageWebHtmlChanged() {
            root.refresh()
        }

        function onSelectedMessageWebBaseUrlChanged() {
            root.refresh()
        }

        function onSelectedMessageChanged() {
            root.refresh()
        }
    }

    Native.Menu {
        id: contextMenu

        Native.MenuItem {
            text: "Copy"
            visible: String(root.contextMenuSelectedText || "").trim().length > 0
            onTriggered: root.copySelection()
        }

        Native.MenuItem {
            text: "Select All"
            visible: true
            onTriggered: root.selectAll()
        }

        Native.MenuSeparator {
            visible: String(root.contextMenuSelectedText || "").trim().length > 0
        }

        Native.MenuItem {
            text: "Search with Google"
            visible: String(root.contextMenuSelectedText || "").trim().length > 0
            onTriggered: root.openSearchWithGoogle()
        }

        Native.MenuSeparator {
            visible: String(root.contextMenuSelectedText || "").trim().length > 0
                && String(root.contextMenuLinkUrl || "").trim().length > 0
        }

        Native.MenuItem {
            text: "Open Link"
            visible: String(root.contextMenuLinkUrl || "").trim().length > 0
            onTriggered: root.openLink()
        }

        Native.MenuItem {
            text: "Copy Link"
            visible: String(root.contextMenuLinkUrl || "").trim().length > 0
            onTriggered: root.copyLink()
        }

        Native.MenuSeparator {
            visible: root.contextMenuMediaType === ContextMenuRequest.MediaTypeImage
                || root.contextMenuMediaType === ContextMenuRequest.MediaTypeVideo
                || root.contextMenuMediaType === ContextMenuRequest.MediaTypeAudio
        }

        Native.MenuItem {
            text: "Copy Image"
            visible: root.contextMenuMediaType === ContextMenuRequest.MediaTypeImage
            onTriggered: root.copyImage()
        }

        Native.MenuItem {
            text: "Copy Image URL"
            visible: root.contextMenuMediaType === ContextMenuRequest.MediaTypeImage
            onTriggered: root.copyImageUrl()
        }

        Native.MenuItem {
            text: "Copy Media URL"
            visible: root.contextMenuMediaType === ContextMenuRequest.MediaTypeVideo
                || root.contextMenuMediaType === ContextMenuRequest.MediaTypeAudio
            onTriggered: root.copyMediaUrl()
        }
    }

    WebEngineView {
        id: webView
        width: parent.width
        height: Math.max(1, root.contentHeight)
        backgroundColor: "transparent"
        settings.javascriptEnabled: false
        settings.javascriptCanOpenWindows: false
        settings.javascriptCanAccessClipboard: false
        settings.javascriptCanPaste: false
        settings.localStorageEnabled: false
        settings.pluginsEnabled: false
        settings.fullScreenSupportEnabled: false
        settings.screenCaptureEnabled: false
        settings.webGLEnabled: false
        settings.autoLoadImages: false
        settings.autoLoadIconsForPage: false
        settings.touchIconsEnabled: false
        settings.spatialNavigationEnabled: false
        settings.pdfViewerEnabled: false
        settings.localContentCanAccessRemoteUrls: false
        activeFocusOnPress: true

        onContentsSizeChanged: {
            root.measureContent()
        }

        onContextMenuRequested: function(request) {
            request.accepted = true
            root.contextMenuSelectedText = String(request.selectedText || "")
            root.contextMenuLinkUrl = String(request.linkUrl || "")
            root.contextMenuLinkText = String(request.linkText || "")
            root.contextMenuMediaUrl = String(request.mediaUrl || "")
            root.contextMenuMediaType = Number(request.mediaType !== undefined ? request.mediaType : -1)
            contextMenu.open()
        }

        onLoadingChanged: function(loadingInfo) {
            if (loadingInfo.status === WebEngineView.LoadSucceededStatus || loadingInfo.status === WebEngineView.LoadStoppedStatus) {
                root.measureContent()
            }
        }
    }

    Item {
        anchors.fill: webView
        z: webView.z + 1

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            blocking: true
            onWheel: function(event) {
                root.scrollOuterArea(event)
            }
        }
    }
}

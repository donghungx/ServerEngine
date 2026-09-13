import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml
import "../components" as Components
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    required property var dashboardBridge
    property bool enableSysStatusSection: false
    border.width: 0
    color: "transparent"
    clip: true

    function serviceBusy(serviceId) {
        if (serviceId === "web") {
            return !!dashboardBridge.stackActionBusy
        }
        if (serviceId === "database") {
            return !!dashboardBridge.databaseActionBusy
        }
        if (serviceId === "redis") {
            return !!dashboardBridge.redisActionBusy
        }
        if (serviceId === "memcached") {
            return !!dashboardBridge.memcachedActionBusy
        }
        if (serviceId === "mailpit") {
            return !!dashboardBridge.mailpitActionBusy
        }
        if (serviceId === "mongodb") {
            return !!dashboardBridge.mongodbActionBusy
        }
        if (serviceId === "postgresql") {
            return !!dashboardBridge.postgresqlActionBusy
        }
        return false
    }

    Components.AppScrollArea {
        anchors.top: parent.top
        anchors.topMargin: 52
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clipContent: true

        Column {
            id: homeColumn
            width: parent.width

            Components.ShellCard {
                width: parent.width
                implicitHeight: servicesColumn.implicitHeight + 48
                border.width: 0
                color: "transparent"

                Column {
                    id: servicesColumn
                    anchors.fill: parent
                    spacing: 18

                    Text {
                        text: Strings.t("services")
                        color: Theme.text
                        font.pixelSize: 28
                        font.weight: Font.Bold
                    }

                    Text {
                        text: Strings.t("live.controls.for.the.active.web.server.database.mongodb.postgresql.redis.memcached.and.mailpit.these.switches.stay.in.sync.with.the.main.start.stop.and.restart.actions")
                        color: Theme.muted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Flow {
                        width: parent.width
                        spacing: 18

                        Repeater {
                            model: dashboardBridge.homeServiceItems

                            delegate: Components.ShellCard {
                                id: serviceCard
                                required property var modelData
                                property var serviceItem: modelData
                                width: 240
                                height: 116
                                property bool serviceRunningDisplay: serviceItem.running

                                    RowLayout {
                                        id: serviceCardRow
                                        anchors.fill: parent
                                        anchors.margins: 18
                                        spacing: 16
                                        property bool serviceBusy: serviceCard.serviceItem.id === "web"
                                            ? !!dashboardBridge.stackActionBusy
                                            : serviceCard.serviceItem.id === "database"
                                            ? !!dashboardBridge.databaseActionBusy
                                            : serviceCard.serviceItem.id === "redis"
                                            ? !!dashboardBridge.redisActionBusy
                                            : serviceCard.serviceItem.id === "memcached"
                                            ? !!dashboardBridge.memcachedActionBusy
                                            : serviceCard.serviceItem.id === "mailpit"
                                            ? !!dashboardBridge.mailpitActionBusy
                                            : serviceCard.serviceItem.id === "mongodb"
                                            ? !!dashboardBridge.mongodbActionBusy
                                            : serviceCard.serviceItem.id === "postgresql"
                                            ? !!dashboardBridge.postgresqlActionBusy
                                            : false

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: serviceItem.title
                                            color: Theme.text
                                            font.pixelSize: 18
                                            font.weight: Font.DemiBold
                                        }

                                        Text {
                                            text: serviceItem.label
                                            color: Theme.accentStrong
                                            font.pixelSize: 15
                                            font.weight: Font.Medium
                                        }

                                        Row {
                                            spacing: 6

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: serviceCardRow.serviceBusy ? "#d89d35" : (serviceItem.running ? "#49ad55" : "#c86b6b")
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: serviceItem.status + " • " + serviceItem.detail
                                                color: Theme.muted
                                                font.pixelSize: 12
                                            }
                                        }

                                        Item {
                                            id: includeGlobalCheck
                                            implicitWidth: includeGlobalRow.implicitWidth
                                            implicitHeight: includeGlobalRow.implicitHeight
                                            property bool checked: root.dashboardBridge.homeServiceIncludedInGlobal(serviceItem.id)
                                            property bool interactiveEnabled: !serviceCardRow.serviceBusy && !root.dashboardBridge.globalStackBusy
                                            opacity: interactiveEnabled ? 1.0 : 0.55

                                            Row {
                                                id: includeGlobalRow
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 8

                                                Rectangle {
                                                    width: 14
                                                    height: 14
                                                    radius: 3
                                                    border.width: 1
                                                    border.color: includeGlobalCheck.checked ? Theme.accentStrong : Theme.border
                                                    color: includeGlobalCheck.checked ? Theme.accentStrong : Theme.surface
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: includeGlobalCheck.checked ? "✓" : ""
                                                        color: "#ffffff"
                                                        font.pixelSize: 10
                                                    }
                                                }

                                                Text {
                                                    text: Strings.t("include.in.global")
                                                    color: Theme.muted
                                                    font.pixelSize: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: includeGlobalCheck.interactiveEnabled
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    includeGlobalCheck.checked = !includeGlobalCheck.checked
                                                    root.dashboardBridge.setHomeServiceIncludedInGlobal(serviceItem.id, includeGlobalCheck.checked)
                                                }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 8

                                        Components.AppSwitch {
                                            id: serviceToggle
                                            property bool toggleLock: false
                                            autoToggle: false
                                            checked: serviceCard.serviceRunningDisplay
                                            enabled: !serviceCardRow.serviceBusy && !toggleLock
                                            opacity: enabled ? 1.0 : 0.55
                                            onToggled: function(nextChecked) {
                                                if (serviceCardRow.serviceBusy || toggleLock) {
                                                    return
                                                }
                                                serviceCard.serviceRunningDisplay = nextChecked
                                                toggleLock = true
                                                toggleActionTimer.restart()
                                            }
                                        }

                                        Timer {
                                            id: toggleActionTimer
                                            interval: 0
                                            repeat: false
                                            onTriggered: {
                                                dashboardBridge.setHomeServiceRunning(serviceItem.id, serviceToggle.checked)
                                                serviceToggle.toggleLock = false
                                            }
                                        }

                                        Binding {
                                            target: serviceCard
                                            property: "serviceRunningDisplay"
                                            value: serviceCard.serviceItem.running
                                            when: !serviceToggle.toggleLock
                                        }

                                        Binding {
                                            target: serviceToggle
                                            property: "checked"
                                            value: serviceCard.serviceRunningDisplay
                                            when: !serviceToggle.toggleLock
                                        }

                                        BusyIndicator {
                                            Layout.alignment: Qt.AlignHCenter
                                            running: serviceCardRow.serviceBusy
                                            visible: running
                                            width: 16
                                            height: 16
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Loader {
                active: root.enableSysStatusSection
                width: parent.width
                height: active ? 386 : 0

            sourceComponent: Flickable {
                width: parent.width
                height: 386
                contentWidth: sysStatusRow.implicitWidth
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: sysStatusRow
                    spacing: 18

                    Components.ShellCard {
                        width: 900
                        height: 386

                        Column {
                            anchors.fill: parent
                            anchors.margins: 24
                            spacing: 20

                            Text {
                                text: Strings.t("sys.status")
                                color: Theme.text
                                font.pixelSize: 28
                                font.weight: Font.Bold
                            }

                            Row {
                                spacing: 22

                                Repeater {
                                    model: dashboardBridge.heroMetrics

                                    delegate: Item {
                                        required property var modelData
                                        property var metric: modelData
                                        width: ringMetric.width
                                        height: ringMetric.height

                                        Components.RingMetric {
                                            id: ringMetric
                                            title: parent.metric.title
                                            value: parent.metric.value
                                            detail: parent.metric.detail
                                            caption: parent.metric.caption
                                            percent: parent.metric.percent
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Components.ShellCard {
                        width: 340
                        height: 386

                        Column {
                            anchors.fill: parent
                            anchors.margins: 24
                            spacing: 22

                            Text {
                                text: dashboardBridge.diskMetric.title
                                color: Theme.text
                                font.pixelSize: 28
                                font.weight: Font.Bold
                            }

                            Text {
                                text: dashboardBridge.diskMetric.value
                                color: Theme.accentStrong
                                font.pixelSize: 46
                                font.weight: Font.Bold
                            }

                            Text {
                                text: dashboardBridge.diskMetric.detail
                                color: Theme.text
                                font.pixelSize: 17
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Theme.border
                            }

                            Column {
                                spacing: 12

                                Text {
                                    text: dashboardBridge.diskMetric.free
                                    color: Theme.muted
                                    font.pixelSize: 15
                                }

                                Text {
                                    text: dashboardBridge.diskMetric.total
                                    color: Theme.muted
                                    font.pixelSize: 15
                                }
                            }
                        }
                    }
                }
            }
        }

            Components.ShellCard {
                width: parent.width
                implicitHeight: overviewColumn.implicitHeight + 24
                border.width: 0
                color: "transparent"

                Column {
                    id: overviewColumn
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: Strings.t("overview")
                        color: Theme.text
                        font.pixelSize: 28
                        font.weight: Font.Bold
                    }

                    Flow {
                        width: parent.width
                        spacing: 12

                        Repeater {
                            model: dashboardBridge.overviewCards

                            delegate: Components.ShellCard {
                                required property var modelData
                                property var overviewCard: modelData
                                width: 210
                                height: 154

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 6

                                    Row {
                                        width: parent.width
                                        spacing: 8

                                        Text {
                                            text: overviewCard.title
                                            color: Theme.text
                                            font.pixelSize: 16
                                            font.weight: Font.DemiBold
                                        }

                                        Rectangle {
                                            width: 10
                                            height: 10
                                            radius: Theme.radius
                                            color: Theme.accent
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Text {
                                        text: overviewCard.accent
                                        color: Theme.accentStrong
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: overviewCard.value
                                        color: Theme.text
                                        font.pixelSize: 28
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        text: overviewCard.detail
                                        color: Theme.muted
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

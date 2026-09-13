import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Window {
    property var root: ({})
    property var dashboardBridge: ({})

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (root && root.dashboardBridge) {
            return root.dashboardBridge
        }
        return ({})
    }

        id: mongodbImportWindow
        visible: root.mongodbImportPopupOpen
        width: 560
        height: 256
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: String(root.mongodbImportDatabaseName || "").length > 0 ? ("Import into " + root.mongodbImportDatabaseName) : "MongoDB Import"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint

        onVisibleChanged: {
            if (visible) {
                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
            } else {
                bridge().clearMongodbImportSelection && bridge().clearMongodbImportSelection()
                root.mongodbImportPopupOpen = false
                root.mongodbImportDatabaseName = ""
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("mongodb.import")
            moveWindow: mongodbImportWindow
            contentSpacing: 16
            color: Theme.surface

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: Strings.t("selected.mongodb.database")
                        color: Theme.muted
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.mongodbImportDatabaseName
                        color: Theme.text
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(bridge().mongodbImportSelectedPath || "").length > 0
                                ? bridge().mongodbImportSelectedPath
                                : ""

                            placeholderText: Strings.t("choose.import.file")
                            readOnly: true
                            selectByMouse: true
                        }

                        Row {
                            Components.AppButton {
                                text: Strings.t("choose.file")
                                enabled: !bridge().mongodbImportBusy

                                onClicked: bridge().chooseMongodbImportFile && bridge().chooseMongodbImportFile()
                            }
                        }
                    }

                    Label {
                        text: String(root.mongodbImportDatabaseName || "").length > 0
                            ? "Import a MongoDB file or archive into " + root.mongodbImportDatabaseName + ". Supported formats: .json, .bson, .zip, .tar.gz, .tgz, .gz."
                            : "Import a MongoDB file or archive."
                        color: Theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            footerRight: Row {
                Components.AppButton {
                    text: bridge().mongodbImportBusy ? "Importing..." : "Import"
                    highlighted: true
                    textColor: "white"

                    enabled: !bridge().mongodbImportBusy
                        && String(bridge().mongodbImportSelectedPath || "").length > 0
                        && String(root.mongodbImportDatabaseName || "").length > 0

                    onClicked: {
                        bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                        bridge().importMongodbFile && bridge().importMongodbFile(
                            root.mongodbImportDatabaseName,
                            bridge().mongodbImportSelectedPath
                        )
                    }
                }
            }
        }
    }

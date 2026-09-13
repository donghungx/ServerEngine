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

        id: postgresqlImportWindow
        visible: root.postgresqlImportPopupOpen
        width: 560
        height: 256
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: String(root.postgresqlImportDatabaseName || "").length > 0 ? ("Import into " + root.postgresqlImportDatabaseName) : "PostgreSQL Import"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint

        onVisibleChanged: {
            if (visible) {
                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
            } else {
                bridge().clearPostgresqlImportSelection && bridge().clearPostgresqlImportSelection()
                root.postgresqlImportPopupOpen = false
                root.postgresqlImportDatabaseName = ""
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("postgresql.import")
            moveWindow: postgresqlImportWindow
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
                        text: Strings.t("selected.postgresql.database")
                        color: Theme.muted
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.postgresqlImportDatabaseName
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
                            text: String(bridge().postgresqlImportSelectedPath || "").length > 0
                                ? bridge().postgresqlImportSelectedPath
                                : ""

                            placeholderText: Strings.t("choose.import.file")
                            readOnly: true
                            selectByMouse: true
                        }

                        Row {
                            Components.AppButton {
                                text: Strings.t("choose.file")
                                enabled: !bridge().postgresqlImportBusy

                                onClicked: bridge().choosePostgresqlImportFile && bridge().choosePostgresqlImportFile()
                            }
                        }
                    }

                    Label {
                        text: String(root.postgresqlImportDatabaseName || "").length > 0
                            ? "Import a SQL file or archive into " + root.postgresqlImportDatabaseName + ". Supported formats: .sql, .zip, .tar.gz, .tgz, .gz."
                            : "Import a SQL file or archive."
                        color: Theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            footerRight: Row {
                Components.AppButton {
                    text: bridge().postgresqlImportBusy ? "Importing..." : "Import"
                    highlighted: true
                    textColor: "white"

                    enabled: !bridge().postgresqlImportBusy
                        && String(bridge().postgresqlImportSelectedPath || "").length > 0
                        && String(root.postgresqlImportDatabaseName || "").length > 0

                    onClicked: {
                        bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                        bridge().importPostgresqlFile && bridge().importPostgresqlFile(
                            root.postgresqlImportDatabaseName,
                            bridge().postgresqlImportSelectedPath
                        )
                    }
                }
            }
        }
    }

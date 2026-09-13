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
    property var functionItems: []
    property string feedbackText: ""
    property bool feedbackIsError: false

    Layout.fillWidth: true
    Layout.fillHeight: true

    readonly property var defaultFunctionCatalog: [
        "exec", "shell_exec", "system", "passthru", "proc_open", "proc_close",
        "proc_get_status", "proc_nice", "proc_terminate", "popen", "pclose",
        "pcntl_exec", "pcntl_fork", "pcntl_signal", "pcntl_waitpid",
        "show_source", "phpinfo", "dl",
        "putenv", "mail", "openlog", "syslog", "closelog",
        "link", "symlink", "readlink", "linkinfo",
        "parse_ini_file", "ini_set",
        "curl_exec", "curl_multi_exec",
        "apache_setenv", "apache_getenv",
        "stream_socket_server", "stream_socket_client", "fsockopen",
        "socket_create", "socket_connect", "socket_bind", "socket_listen",
        "error_log"
    ]

    readonly property var defaultFunctionDescriptions: ({
        "exec": "Run an external program and return the last output line.",
        "shell_exec": "Run a shell command and return the full output.",
        "system": "Run an external program and print output directly.",
        "passthru": "Run a command and send raw output to the browser.",
        "proc_open": "Start a process with full pipe control.",
        "proc_close": "Close a process opened by proc_open.",
        "proc_get_status": "Read status information from an opened process.",
        "proc_nice": "Change process priority.",
        "proc_terminate": "Terminate a process opened by proc_open.",
        "popen": "Open a process pipe.",
        "pclose": "Close a process pipe.",
        "pcntl_exec": "Replace the current process with another program.",
        "pcntl_fork": "Fork the current PHP process.",
        "pcntl_signal": "Register a process signal handler.",
        "pcntl_waitpid": "Wait for a child process to exit.",
        "show_source": "Display PHP source code with syntax highlighting.",
        "phpinfo": "Output detailed PHP configuration information.",
        "dl": "Load a PHP extension at runtime.",
        "putenv": "Set an environment variable for the process.",
        "mail": "Send email through the server mail system.",
        "openlog": "Open a connection to the system logger.",
        "syslog": "Write a message to the system logger.",
        "closelog": "Close the system logger connection.",
        "link": "Create a hard link.",
        "symlink": "Create a symbolic link.",
        "readlink": "Read the target of a symbolic link.",
        "linkinfo": "Return information about a link.",
        "parse_ini_file": "Read and parse an INI configuration file.",
        "ini_set": "Change a PHP configuration value at runtime.",
        "curl_exec": "Execute a prepared cURL request.",
        "curl_multi_exec": "Execute multiple cURL requests.",
        "apache_setenv": "Set an Apache subprocess environment variable.",
        "apache_getenv": "Read an Apache subprocess environment variable.",
        "stream_socket_server": "Create a server socket.",
        "stream_socket_client": "Open a client socket connection.",
        "fsockopen": "Open a socket connection by hostname and port.",
        "socket_create": "Create a low-level socket.",
        "socket_connect": "Connect a socket to a remote endpoint.",
        "socket_bind": "Bind a socket to an address and port.",
        "socket_listen": "Listen for incoming socket connections.",
        "error_log": "Write a message to the PHP or system error log."
    })

    function normalizeList(raw) {
        var parts = String(raw || "").split(",")
        var out = []
        for (var i = 0; i < parts.length; i++) {
            var name = String(parts[i] || "").trim()
            if (name.length > 0 && out.indexOf(name) < 0) {
                out.push(name)
            }
        }
        return out
    }

    function loadFunctions() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        var values = dashboardBridge.phpIniDirectiveMap(phpRuntime.version, ["disable_functions"])
        var disabled = normalizeList(values["disable_functions"])
        var merged = []
        for (var i = 0; i < defaultFunctionCatalog.length; i++) {
            var baseName = String(defaultFunctionCatalog[i])
            if (merged.indexOf(baseName) < 0) {
                merged.push(baseName)
            }
        }
        for (var j = 0; j < disabled.length; j++) {
            var existing = String(disabled[j])
            if (merged.indexOf(existing) < 0) {
                merged.push(existing)
            }
        }
        merged.sort()
        var rows = []
        for (var k = 0; k < merged.length; k++) {
            var fn = merged[k]
            rows.push({
                "name": fn,
                "description": defaultFunctionDescriptions[fn] || "",
                "enabled": disabled.indexOf(fn) < 0
            })
        }
        functionItems = rows
        feedbackText = ""
        feedbackIsError = false
    }

    function saveFunctions() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        var disabled = []
        for (var i = 0; i < functionItems.length; i++) {
            if (!functionItems[i].enabled) {
                disabled.push(String(functionItems[i].name))
            }
        }
        var payload = { "disable_functions": disabled.join(",") }
        var ok = dashboardBridge.savePhpIniDirectiveMap(phpRuntime.version, payload)
        if (ok) {
            feedbackText = "Saved disabled functions for PHP " + phpRuntime.version + ". Restart web server to apply changes."
            feedbackIsError = false
        } else {
            feedbackText = dashboardBridge.lastOperationMessage.length > 0
                ? dashboardBridge.lastOperationMessage
                : "Failed to save disabled functions."
            feedbackIsError = true
        }
        if (ok) {
            loadFunctions()
        }
    }

    function restoreDefaults() {
        var rows = []
        var sorted = defaultFunctionCatalog.slice(0)
        sorted.sort()
        for (var i = 0; i < sorted.length; i++) {
            rows.push({
                "name": String(sorted[i]),
                "description": defaultFunctionDescriptions[String(sorted[i])] || "",
                "enabled": true
            })
        }
        functionItems = rows
        feedbackText = "Defaults loaded into form. Click Save to apply."
        feedbackIsError = false
    }

    onPhpRuntimeChanged: loadFunctions()
    Component.onCompleted: loadFunctions()

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: Strings.t("toggle.functions.for.the.disable.functions.directive.save.writes.only.disable.functions.in.php.ini")
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

                Components.CheckableDescriptionList {
                    anchors.fill: parent
                    headerLeftText: Strings.t("function")
                    headerRightText: Strings.t("description")
                    checkboxColumnWidth: 32
                    titleColumnWidth: 220
                    descriptionColumnWidth: 0
                    model: root.functionItems
                    onToggled: function(index, nextChecked) {
                        root.functionItems[index].enabled = nextChecked
                    }
                }
            }
        }

        footerLeft: Text {
            Layout.fillWidth: true
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackIsError ? Theme.danger : Theme.success
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8

            Text {
                text: Strings.t("total") + root.functionItems.length
                color: Theme.muted
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }

            Components.AppButton {
                text: Strings.t("reload")
                onClicked: root.loadFunctions()
            }

            Components.AppButton {
                text: Strings.t("restore")
                onClicked: root.restoreDefaults()
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                onClicked: root.saveFunctions()
            }
        }
    }
}




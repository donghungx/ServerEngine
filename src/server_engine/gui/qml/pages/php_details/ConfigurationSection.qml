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
    property var timezoneOptions: [{ "label": "(UTC+00:00) UTC", "value": "UTC" }]

    readonly property var settingsDefaults: [
        { directive: "date.timezone", title: "Default time zone", type: "timezone", value: "UTC", note: "", options: [] },
        { directive: "display_errors", title: "Display errors", type: "bool", value: "On", note: "Show detailed PHP errors in the browser while developing." },
        { directive: "error_reporting", title: "Error reporting level", type: "enum", value: "E_ALL & ~E_DEPRECATED & ~E_STRICT", note: "Choose which PHP error classes should be reported.", options: [
            "E_ALL",
            "E_ALL & ~E_DEPRECATED",
            "E_ALL & ~E_STRICT",
            "E_ALL & ~E_DEPRECATED & ~E_STRICT",
            "E_ALL & ~E_NOTICE",
            "E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT",
            "E_ALL & ~E_WARNING",
            "E_ALL & ~E_WARNING & ~E_NOTICE",
            "E_ERROR",
            "E_ERROR | E_WARNING",
            "E_ERROR | E_PARSE",
            "E_ERROR | E_WARNING | E_PARSE",
            "E_ERROR | E_WARNING | E_PARSE | E_NOTICE",
            "0"
        ] },
        { directive: "file_uploads", title: "Allow file uploads", type: "bool", value: "On", note: "Turn this off if the app should reject uploaded files completely." },
        { section: "Upload Limits", directive: "post_max_size", title: "Maximum POST body size", type: "short", value: "5000M", note: "" },
        { directive: "upload_max_filesize", title: "Maximum uploaded file size", type: "short", value: "5000M", note: "" },
        { directive: "max_file_uploads", title: "Maximum uploaded files per request", type: "short", value: "20", note: "" },
        { section: "Execution Time", directive: "max_execution_time", title: "Maximum script execution time", type: "short", value: "3000", note: "" },
        { directive: "max_input_time", title: "Maximum input processing time", type: "short", value: "6000", note: "" },
        { directive: "default_socket_timeout", title: "Default socket timeout", type: "short", value: "60", note: "" },
        { directive: "memory_limit", title: "Memory limit", type: "short", value: "1280M", note: "Sets the maximum memory a script may use before PHP stops it." },
        { section: "Runtime Behavior", directive: "short_open_tag", title: "Allow short open tags", type: "bool", value: "On", note: "Enables the short `<?` syntax for PHP templates." },
        { directive: "cgi.fix_pathinfo", title: "Fix PATH_INFO handling", type: "bool", value: "On", note: "Helps PHP resolve PATH_INFO when scripts are reached through CGI or FastCGI." },
    ]
    property var settingsRows: cloneRows(settingsDefaults)
    Layout.fillWidth: true
    Layout.fillHeight: true

    function cloneRows(rows) {
        var out = []
        for (var i = 0; i < rows.length; i++) {
            var item = rows[i]
            out.push({
                section: item.section,
                directive: item.directive,
                title: item.title,
                label: item.label,
                type: item.type,
                value: item.value,
                note: item.note,
                options: item.options ? item.options.slice(0) : undefined
            })
        }
        return out
    }

    function shortValueIndex(model, value) {
        var target = String(value || "")
        for (var i = 0; i < (model ? model.length : 0); i++) {
            var item = model[i]
            var itemValue = String((item && item.value !== undefined) ? item.value : item)
            if (itemValue === target) {
                return i
            }
        }
        return 0
    }

    function shortValueOptions(directive) {
        switch (String(directive || "")) {
        case "post_max_size":
        case "upload_max_filesize":
            return [
                { label: "8M", value: "8M" },
                { label: "16M", value: "16M" },
                { label: "32M", value: "32M" },
                { label: "64M", value: "64M" },
                { label: "128M", value: "128M" },
                { label: "256M", value: "256M" },
                { label: "512M", value: "512M" },
                { label: "1G", value: "1024MB" },
                { label: "2G", value: "2048MB" },
                { label: "5 GB", value: "5000M" }
            ]
        case "max_file_uploads":
            return [
                { label: "20", value: "20" },
                { label: "50", value: "50" },
                { label: "100", value: "100" },
                { label: "200", value: "200" },
                { label: "500", value: "500" },
                { label: "1000", value: "1000" }
            ]
        case "max_execution_time":
        case "max_input_time":
            return [
                { label: "0", value: "0" },
                { label: "30", value: "30" },
                { label: "60", value: "60" },
                { label: "120", value: "120" },
                { label: "300", value: "300" },
                { label: "600", value: "600" },
                { label: "3000", value: "3000" },
                { label: "6000", value: "6000" }
            ]
        case "default_socket_timeout":
            return [
                { label: "30", value: "30" },
                { label: "60", value: "60" },
                { label: "120", value: "120" },
                { label: "300", value: "300" },
                { label: "600", value: "600" }
            ]
        case "memory_limit":
            return [
                { label: "-1 (unlimited)", value: "-1" },
                { label: "128M", value: "128M" },
                { label: "256M", value: "256M" },
                { label: "512M", value: "512M" },
                { label: "1280M", value: "1280M" },
                { label: "1G", value: "1G" },
                { label: "2G", value: "2G" },
                { label: "4G", value: "4G" }
            ]
        default:
            return []
        }
    }

    function setSettingValue(index, value) {
        if (index < 0 || index >= root.settingsRows.length) {
            return
        }
        var rows = root.cloneRows(root.settingsRows)
        rows[index].value = value
        root.settingsRows = rows
    }

    function loadTimezoneOptions() {
        if (!dashboardBridge || !dashboardBridge.phpTimezoneItems || dashboardBridge.phpTimezoneItems.length === 0) {
            root.timezoneOptions = [{ "label": "(UTC+00:00) UTC", "value": "UTC" }]
            return
        }
        root.timezoneOptions = dashboardBridge.phpTimezoneItems
    }

    function loadSettings() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        function normalizeBoolValue(value) {
            var normalized = String(value || "").trim().toLowerCase()
            if (normalized === "0" || normalized === "off" || normalized === "false" || normalized === "no") {
                return "Off"
            }
            if (normalized === "1" || normalized === "on" || normalized === "true" || normalized === "yes") {
                return "On"
            }
            return value
        }
        function normalizeLoadedValue(item, value, fallbackValue) {
            var raw = String(value || "").trim()
            if (item.type === "bool") {
                return normalizeBoolValue(raw)
            }
            if (item.type === "enum") {
                var opts = item.options || []
                for (var i = 0; i < opts.length; i++) {
                    if (String(opts[i]) === raw) {
                        return raw
                    }
                }
                return String(fallbackValue || item.value || "")
            }
            if (item.type === "timezone") {
                var tzOpts = item.options || root.timezoneOptions || []
                for (var j = 0; j < tzOpts.length; j++) {
                    var tzValue = String((tzOpts[j] && tzOpts[j].value) || "")
                    if (tzValue === raw) {
                        return raw
                    }
                }
                return "UTC"
            }
            return raw
        }
        var fresh = root.cloneRows(root.settingsDefaults)
        var keys = []
        for (var i = 0; i < fresh.length; i++) {
            if (fresh[i].type === "timezone") {
                fresh[i].options = root.timezoneOptions
            }
            keys.push(fresh[i].directive || fresh[i].label || fresh[i].title)
        }
        var data = {}
        try {
            if (dashboardBridge.phpIniManagedDirectiveMap) {
                data = dashboardBridge.phpIniManagedDirectiveMap(phpRuntime.version, keys)
            } else {
                data = dashboardBridge.phpIniDirectiveMap(phpRuntime.version, keys)
            }
        } catch (e) {
            data = dashboardBridge.phpIniDirectiveMap(phpRuntime.version, keys)
        }
        if (!data) {
            data = {}
        }
        for (var j = 0; j < fresh.length; j++) {
            var item = fresh[j]
            var keyName = item.directive || item.label || item.title
            if (data[keyName] !== undefined && String(data[keyName]).length > 0) {
                fresh[j].value = normalizeLoadedValue(item, data[keyName], root.settingsDefaults[j] ? root.settingsDefaults[j].value : "")
            }
        }
        root.settingsRows = fresh
    }

    function saveSettings() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        function normalizeBoolValue(value) {
            var normalized = String(value || "").trim().toLowerCase()
            if (normalized === "0" || normalized === "off" || normalized === "false" || normalized === "no") {
                return "Off"
            }
            if (normalized === "1" || normalized === "on" || normalized === "true" || normalized === "yes") {
                return "On"
            }
            return "Off"
        }
        function normalizeSettingValue(item, fallbackValue) {
            var raw = String(item.value || "").trim()
            if (item.type === "bool") {
                return normalizeBoolValue(raw)
            }
            if (item.type === "enum") {
                var opts = item.options || []
                for (var i = 0; i < opts.length; i++) {
                    if (String(opts[i]) === raw) {
                        return raw
                    }
                }
                return String(fallbackValue || item.value || "")
            }
            if (item.type === "timezone") {
                var tzOpts = item.options || root.timezoneOptions || []
                for (var j = 0; j < tzOpts.length; j++) {
                    var tzValue = String((tzOpts[j] && tzOpts[j].value) || "")
                    if (tzValue === raw) {
                        return raw
                    }
                }
                return "UTC"
            }
            return raw
        }
        var payload = {}
        for (var i = 0; i < root.settingsRows.length; i++) {
            var item = root.settingsRows[i]
            var fallback = root.settingsDefaults[i] ? root.settingsDefaults[i].value : ""
            payload[item.directive || item.label || item.title] = normalizeSettingValue(item, fallback)
        }
        var ok = dashboardBridge.savePhpIniDirectiveMap(phpRuntime.version, payload)
        if (ok && saveButton) {
            saveButton.showSuccess()
        } else if (saveButton) {
            saveButton.successActive = false
        }
    }

    function restoreDefault() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        var fresh = root.cloneRows(root.settingsDefaults)
        for (var i = 0; i < fresh.length; i++) {
            if (fresh[i].type === "timezone") {
                fresh[i].options = root.timezoneOptions
            }
        }
        root.settingsRows = fresh
    }

    onPhpRuntimeChanged: loadSettings()
    onDashboardBridgeChanged: loadTimezoneOptions()
    onVisibleChanged: {
        if (visible) {
            loadTimezoneOptions()
            loadSettings()
        }
    }
    Component.onCompleted: {
        loadTimezoneOptions()
        loadSettings()
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surface
                clip: true

                Components.AppScrollArea {
                    anchors.fill: parent
                    viewportMargins: 1
                    clipContent: true

                    ColumnLayout {
                        id: settingsColumn
                        width: parent.width - 44
                        x: 22
                        y: 22
                        spacing: 14

                        Repeater {
                            model: root.settingsRows

                            delegate: ColumnLayout {
                                required property int index
                                property var settingItem: root.settingsRows[index]

                                Layout.fillWidth: true
                                spacing: 8

                                Components.SettingsCheckableOption {
                                    visible: settingItem.type === "bool"
                                    title: String(settingItem.title || settingItem.label || "")
                                    description: String(settingItem.note || "")
                                    checked: String(settingItem.value || "").toLowerCase() === "on"
                                    onToggled: function(nextChecked) {
                                        root.setSettingValue(index, nextChecked ? "On" : "Off")
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    visible: settingItem.type === "enum"
                                    title: String(settingItem.title || settingItem.label || "")
                                    description: String(settingItem.note || "")

                                    Components.AppComboBox {
                                        id: enumCombo
                                        width: 300
                                        model: settingItem.options || []
                                        editable: false

                                        function syncCurrent() {
                                            var currentValue = String(settingItem.value || "")
                                            var found = -1
                                            for (var i = 0; i < model.length; i++) {
                                                if (String(model[i]) === currentValue) {
                                                    found = i
                                                    break
                                                }
                                            }
                                            currentIndex = found >= 0 ? found : 0
                                        }

                                        Component.onCompleted: syncCurrent()
                                        onModelChanged: syncCurrent()

                                        onActivated: function(activatedIndex) {
                                            var selected = activatedIndex >= 0 && activatedIndex < model.length
                                                ? String(model[activatedIndex])
                                                : String(currentText || "")
                                            root.setSettingValue(index, selected)
                                        }
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    visible: settingItem.type === "timezone"
                                    title: String(settingItem.title || settingItem.label || "")
                                    description: String(settingItem.note || "")

                                    Components.AppComboBox {
                                        id: timezoneCombo
                                        width: 300
                                        model: settingItem.options || root.timezoneOptions
                                        textRole: "label"
                                        editable: false

                                        function syncCurrent() {
                                            var currentValue = String(settingItem.value || "")
                                            var found = -1
                                            for (var i = 0; i < model.length; i++) {
                                                var modelValue = String((model[i] && model[i].value) || "")
                                                if (modelValue === currentValue) {
                                                    found = i
                                                    break
                                                }
                                            }
                                            currentIndex = found >= 0 ? found : 0
                                        }

                                        Component.onCompleted: syncCurrent()
                                        onModelChanged: syncCurrent()

                                        onActivated: function(activatedIndex) {
                                            var selected = activatedIndex >= 0 && activatedIndex < model.length
                                                ? model[activatedIndex]
                                                : null
                                            root.setSettingValue(index, String((selected && selected.value) || "UTC"))
                                        }
                                    }
                                }

                                Components.SettingsLabeledInput {
                                    visible: settingItem.type !== "bool"
                                        && settingItem.type !== "enum"
                                        && settingItem.type !== "timezone"
                                    title: String(settingItem.title || settingItem.label || "")
                                    description: String(settingItem.note || "")

                                    Components.AppComboBox {
                                        id: shortValueCombo
                                        width: 160
                                        editable: false
                                        model: root.shortValueOptions(settingItem.directive || settingItem.label || settingItem.title)
                                        textRole: "label"
                                        currentIndex: root.shortValueIndex(model, settingItem.value)
                                        onActivated: function(activatedIndex) {
                                            var selected = activatedIndex >= 0 && activatedIndex < model.length ? model[activatedIndex] : null
                                            if (selected && selected.value !== undefined) {
                                                root.setSettingValue(index, String(selected.value))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                
                        Item {
                            Layout.fillWidth: true
                            height: 22
                        }
                    }
                }
            }
        }

        footerLeft: Row {
            spacing: 8

            Components.QuickActionButton {
                text: ""
                iconSource: "icons/lucide/circle-question-mark.svg"
                iconSize: 16
                useCustomHoverBackground: true
                hoverBackgroundColor: "transparent"
                tooltip: Strings.t("default.backup") + (dashboardBridge && phpRuntime && phpRuntime.version
                    ? dashboardBridge.phpIniDefaultBackupPath(phpRuntime.version)
                    : "")
                clickToShowTooltip: true
            }
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("refresh")
                onClicked: root.loadSettings()
            }

            Components.AppButton {
                text: Strings.t("restore")
                onClicked: root.restoreDefault()
            }

            Components.AppButton {
                id: saveButton
                text: Strings.t("settings.appearance.save")
                successText: "Saved"
                successDurationMs: 5000
                onClicked: root.saveSettings()
            }
        }
    }
}




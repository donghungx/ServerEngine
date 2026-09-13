pragma Singleton
import QtQuick

QtObject {
    property bool dark: false

    property color bg: dark ? '#1c1e20' : "white"
    property color panel: dark ? "red" : "#f4f5f7"
    property color surface: dark ? "#252627" : "#ffffff"
    property color surfaceAlt: dark ? "#28292a" : "#f6f7f9"
    property color comboBoxBackground: dark ? "#363634" : "#eeeeee"
    property color comboBoxSelectedBackground: dark ? "#454543" : "#e1e1e1"
    property color border: dark ? "#323436" : "#d7dbe1"
    property color borderStrong: dark ? "#2c2e30" : "#c7ced8"
    property color textFieldBorder: dark ? "#363634" : "#eeeeee"
    property color text: dark ? "#e6ebf2" : "#22262b"
    property color muted: dark ? "#8E8E93" : "#8A8A8A"
    property color accent: "#007bff"
    property color accentStrong: "#007bff"
    property color accentSoft: dark ? "#1b2a44" : "#ffffff"
    property color success: "#1f9d55"
    property color danger: "#de6a63"
    property color warning: "#d9a646"
    property color titleBar: dark ? "#353637" : "#f3f4f6"
    property color titleBarItemHover: dark ? "#424243" : "#e6e8eb"
    property color shadow: dark ? "#000000" : "#d7dce4"
    property color popupSidebarSurface: dark ? "#131f2f" : "#f5f6f8"
    property color popupSidebarSelected: dark ? "#2f4769" : "#dbe5ff"
    property color popupSidebarSelectedText: dark ? "#f2f7ff" : "#22262b"
    property color navItemHover: dark ? "blue" : "#f0f2f5"
    property color navItemHoverBorder: dark ? "blue" : "#c7ced8"
    property color navIconChip: dark ? "blue" : "#e7eaef"
    property color navIconChipBorder: dark ? "blue" : "transparent"
    property real navIconOpacity: dark ? 0.84 : 0.72

    property color scrollBarTrack: surfaceAlt
    property color scrollBarThumb: dark ? "#8f98a6" : "#8a93a1"

    property color toolTipBackground: dark ? "#27292b" : "#f7f8fa"
    property color toolTipShadow: dark ? "#70000000" : "#22000000"
    property color toolTipText: dark ? "#dbe3ee" : "#1f2630"
    property color headerIconButtonHoverBackground: dark ? "#292727" : "#eef1f5"
    property color statusTextButtonActiveBackground: dark ? "#292727" : "#e8edf7"
    property color topIconTabSelectedBackground: dark ? "#424243" : "#e6e8eb"
    property color quickActionHoverBackground: dark ? "#424243" : "#e6e8eb"
    property color quickActionDangerHoverBackground: dark ? "#3d2c2c" : "#fdecec"
    property color quickActionDangerText: "#b33a3a"
    property color quickActionDangerIcon: "#b33a3a"

    property color checkboxBackgroundChecked: accentStrong
    property color checkboxBackgroundUnchecked: dark ? "#3d3b3a" : "#e9e9e9"
    property color checkboxBorderChecked: accentStrong
    property color checkboxBorderUnchecked: border
    property color checkboxCheckmark: "#ffffff"

    property color switchTrackChecked: accentStrong
    property color switchTrackUnchecked: dark ? "#424242" : "#e2e2e2"
    property color switchThumb: "#ffffff"

    property color phpBadgeBackground: dark ? "#2b3444" : "#e8edf7"
    property color phpBadgeBorder: dark ? "#42506a" : "#b4c2df"
    property color phpActiveStatusText: "#4aa94b"

    property color websiteSslOnText: "#4aa94b"
    property color websiteSslOffText: "#e29a33"

    property color ringMetricTrackBorder: "#e8edf7"

    property color dialogFeedbackErrorText: "#b33a3a"
    property color dialogFeedbackSuccessText: "#2f7d32"
    property color sidebarButtonActiveText: "#ffffff"

    property color buttonDisabledBackground: surfaceAlt
    property color buttonDisabledBorder: surfaceAlt
    property color buttonDisabledText: muted

    property color buttonOutlineBackground: "transparent"
    property color buttonOutlineBorder: dark ? accentStrong : borderStrong
    property color buttonOutlineText: accentStrong

    property color buttonNeutralBackground: dark ? "#343434" : "#e4e4e4"
    property color buttonNeutralHoverBackground: dark ? "#464444" : '#d0d0d0'
    property color buttonNeutralPressedBackground: dark ? "#464444" : '#bababa'
    property color buttonNeutralBorder: dark ? "#343434" : "#b8b8b8"
    property color buttonNeutralText: dark ? "#ffffff" : text

    property color buttonPrimaryBackground: accentStrong
    property color buttonPrimaryHoverBackground: dark ? Qt.lighter(accentStrong, 1.06) : Qt.darker(accentStrong, 1.03)
    property color buttonPrimaryPressedBackground: dark ? Qt.darker(accentStrong, 1.18) : Qt.darker(accentStrong, 1.12)
    property color buttonPrimaryBorder: dark ? Qt.darker(accentStrong, 1.18) : Qt.darker(accentStrong, 1.12)
    property color buttonPrimaryText: "#ffffff"

    property int radius: 8
}

pragma Singleton
import QtQuick
import "en" as En
import "de" as De
import "vi" as Vi
import "zh-hans" as ZhHans
import "zh-hant" as ZhHant

QtObject {
    property string language: "en"
    property string fallbackLanguage: "en"

    readonly property var english: En.Strings.entries
    readonly property var german: De.Strings.entries
    readonly property var vietnamese: Vi.Strings.entries
    readonly property var chineseSimplified: ZhHans.Strings.entries
    readonly property var chineseTraditional: ZhHant.Strings.entries

    function _dictionaryFor(code) {
        var lang = String(code || "").toLowerCase()
        if (lang === "de") {
            return german
        }
        if (lang === "vi") {
            return vietnamese
        }
        if (lang === "zh-hans" || lang === "zh_cn" || lang === "zh-sg") {
            return chineseSimplified
        }
        if (lang === "zh-hant" || lang === "zh_tw" || lang === "zh_hk" || lang === "zh-mo") {
            return chineseTraditional
        }
        return english
    }

    function _hasKey(dict, key) {
        return !!dict && Object.prototype.hasOwnProperty.call(dict, key)
    }

    function t(key) {
        var activeDict = _dictionaryFor(language)
        var englishValue = _hasKey(english, key) ? english[key] : undefined
        var activeValue = _hasKey(activeDict, key) ? activeDict[key] : undefined

        if (activeValue !== undefined && activeValue !== null && String(activeValue).length > 0) {
            return activeValue
        }
        if (englishValue !== undefined && englishValue !== null && String(englishValue).length > 0) {
            return englishValue
        }
        return String(key || "")
    }
}

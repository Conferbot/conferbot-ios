//
//  FlowI18n.swift
//  Conferbot
//
//  The rich steps' words: the SDK's i18n (Core/I18n, the web's
//  conferbot-widget/src/ts/i18n tables). Kept so the step handlers and
//  views that call FlowI18n.t read the active language, as the React Native
//  SDK's src/core/flow/i18nEn.ts; `key` is loose because they build keys at
//  run time.
//

import Foundation

enum FlowI18n {
    /// A text by key in the active language, {name} placeholders filled (web i18n t).
    static func t(_ key: String, _ vars: [String: Any]? = nil) -> String { I18n.t(key, vars) }
}

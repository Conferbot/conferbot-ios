//
//  HelpCentre.swift
//  Conferbot
//
//  What the chat shows of the help centre (the knowledge base), from the
//  bot's settings. Ported from conferbot-widget/src/core/helpCentre.ts.
//
//  1. The help centre is on only when the owner turned `enableKnowledgeBase`
//     on. The server sends no articles otherwise.
//  2. Recent articles show while the help centre is on, there is at least
//     one article, and the owner has not hidden them (`hideRecentArticles`).
//     The app has no home screen, so they sit at the top of the help centre.
//  3. An article opens (from the list, a source under an AI answer or an
//     article card) only while the help centre is on.
//  4. An article the server picked for a wait (queue-help) opens anyway: in
//     the help centre while it is on, else fetched by id and shown on its
//     own (RN / Flutter fetch it by id the same way, #83).
//
//  The host app can turn the help centre off for its own screens
//  (`ChatView(enableKnowledgeBase: false)`); it cannot turn it on against
//  the owner's setting, as there would be no articles to show.
//

import Foundation

public enum HelpCentre {
    /// Rule 1: the owner's switch.
    public static func isOn(_ customizations: [String: Any]?) -> Bool {
        customizations?["enableKnowledgeBase"] as? Bool == true
    }

    /// Rule 1 with the host app's override: `false` hides the help centre,
    /// `nil` or `true` follow the owner.
    public static func isShown(_ customizations: [String: Any]?, host: Bool?) -> Bool {
        host != false && isOn(customizations)
    }

    /// Rule 2: the Recent articles list.
    public static func showsRecentArticles(_ customizations: [String: Any]?, articleCount: Int) -> Bool {
        isOn(customizations) && customizations?["hideRecentArticles"] as? Bool != true && articleCount > 0
    }

    /// Rule 3: may an article open?
    public static func canOpenArticle(_ customizations: [String: Any]?, articleId: String?) -> Bool {
        isOn(customizations) && !(articleId ?? "").isEmpty
    }

    /// Where an article the server picked for a wait opens (rule 4).
    public enum WaitArticleRoute: Equatable { case helpCentre, byId, nowhere }

    public static func waitArticleRoute(_ customizations: [String: Any]?, articleId: String?) -> WaitArticleRoute {
        if (articleId ?? "").isEmpty { return .nowhere }
        return canOpenArticle(customizations, articleId: articleId) ? .helpCentre : .byId
    }
}

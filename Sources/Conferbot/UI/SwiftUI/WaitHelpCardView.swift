//
//  WaitHelpCardView.swift
//  Conferbot
//
//  The "While you wait, this might help" card (web
//  conferbot-widget src/ts/chat/waitArticles.ts mountHelpCard, its CSS in
//  src/css/polish.css .cb-wait-articles; RN LiveChat/WaitHelpCard.tsx): in
//  the bot bubble's colours, a row per item (an article opens in the app, a
//  page in the browser) and, for the server's pick, "That solved it". Once
//  the wait is over it stays as history under "Articles that might help".
//  The state is ConferBot.waiting's (Core/LiveChat/WaitingExtras); nothing
//  moves on its own.
//

import SwiftUI

@available(iOS 15.0, *)
public struct WaitHelpCardView: View {
    @ObservedObject private var conferBot = ConferBot.shared
    @ObservedObject private var waiting = ConferBot.shared.waiting
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        if let card = waiting.helpCard, !card.items.isEmpty {
            let look = conferBot.customizations
            let bg = Color(hex: look.botBubbleColor)
            let ink = Color(hex: look.botTextColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(card.settled ? WaitArticles.Text.settledTitle : WaitArticles.Text.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ink.opacity(0.8))
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(card.items, id: \.id) { item in
                    Button {
                        waiting.openHelpItem(item)
                        if item.kind == .page, let link = item.url, let url = URL(string: link) { openURL(url) }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(ink)
                                    .multilineTextAlignment(.leading)
                                if let d = item.description {
                                    Text(d)
                                        .font(.system(size: 12))
                                        .foregroundColor(ink.opacity(0.8))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(WaitArticles.Text.read)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ink.opacity(0.85))
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(ink.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(WaitArticles.Text.read): \(item.title)")
                    .accessibilityAddTraits(item.kind == .page ? .isLink : .isButton)
                }
                if card.done {
                    Text(WaitArticles.Text.done)
                        .font(.system(size: 12))
                        .foregroundColor(ink.opacity(0.85))
                        .padding(.horizontal, 2)
                        .padding(.top, 2)
                } else if card.solvable && !card.settled {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            waiting.solveWait()
                        } label: {
                            HStack(spacing: 6) {
                                if card.busy { ProgressView().tint(ink).scaleEffect(0.7) }
                                Text(WaitArticles.Text.solved)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(ink)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .overlay(Capsule().stroke(ink.opacity(0.45), lineWidth: 1))
                            .opacity(card.busy ? 0.6 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(card.busy)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(card.settled ? WaitArticles.Text.settledTitle : WaitArticles.Text.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Under the bot's bubbles, past the avatar column.
            .padding(.leading, 40)
            .padding(.trailing, 12)
        }
    }
}

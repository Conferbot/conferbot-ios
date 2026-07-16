//
//  ContentView.swift
//  ConferbotExample
//
//  Demonstrates three common integration patterns:
//    1. Widget (FAB)  -- floating chat bubble overlaid on your app content,
//                        exactly like the web widget embed (default).
//    2. Modal (sheet) -- tap a button to open ChatView in a sheet.
//    3. Embedded      -- ChatView rendered inline within a NavigationView.
//

import SwiftUI
import Conferbot

struct ContentView: View {
    @ObservedObject private var bot = ConferBot.shared

    @State private var showChatSheet = false
    @State private var selectedPattern: Pattern = .widget

    enum Pattern: String, CaseIterable, Identifiable {
        case widget   = "Widget (FAB)"
        case modal    = "Modal (Sheet)"
        case embedded = "Embedded"
        var id: String { rawValue }
    }

    var body: some View {
        // The floating widget overlays the whole screen for the primary
        // (widget) pattern - matching the web widget embed
        if selectedPattern == .widget {
            mainContent.conferBotWidget()
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        NavigationView {
            VStack(spacing: 32) {

                // -- Connection status ----------------------------------------
                statusBanner

                Spacer()

                // -- Pattern picker -------------------------------------------
                Picker("Integration Pattern", selection: $selectedPattern) {
                    ForEach(Pattern.allCases) { pattern in
                        Text(pattern.rawValue).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // -- Pattern-specific content ---------------------------------
                switch selectedPattern {
                case .modal:
                    modalPatternView
                case .embedded:
                    embeddedPatternView
                case .widget:
                    widgetPatternView
                }

                Spacer()
            }
            .navigationTitle("Conferbot Example")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bot.isConnected ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            Text(bot.isConnected ? "Connected" : "Connecting...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if bot.unreadCount > 0 {
                Text("\(bot.unreadCount) unread")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }

            if !bot.isOnline {
                Text("Offline")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Modal Pattern

    private var modalPatternView: some View {
        VStack(spacing: 16) {
            Text("Opens ChatView in a sheet overlay.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showChatSheet = true }) {
                Label("Start Chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .sheet(isPresented: $showChatSheet) {
                ChatView()
            }
        }
    }

    // MARK: - Widget Pattern

    private var widgetPatternView: some View {
        VStack(spacing: 16) {
            // Demo host-app content the widget floats over
            VStack(alignment: .leading, spacing: 8) {
                Text("Your App Content")
                    .font(.headline)
                Text("This screen stands in for your app. The floating chat bubble in the corner is the live Conferbot widget - styled by your dashboard settings, complete with the CTA tooltip. Tap it to chat.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            Text("Enabled with one modifier on your root view:")
                .font(.footnote)
                .foregroundColor(.secondary)

            Text(".conferBotWidget()")
                .font(.system(.caption, design: .monospaced))
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
        }
    }

    // MARK: - Embedded Pattern

    private var embeddedPatternView: some View {
        VStack(spacing: 0) {
            Text("ChatView rendered inline below.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            ChatView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(12)
                .padding(.horizontal, 8)
        }
    }
}

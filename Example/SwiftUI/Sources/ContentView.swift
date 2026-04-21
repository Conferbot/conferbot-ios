//
//  ContentView.swift
//  ConferbotExample
//
//  Demonstrates two common integration patterns:
//    1. Modal (sheet) -- tap a button to open ChatView in a sheet.
//    2. Embedded      -- ChatView rendered inline within a NavigationView.
//

import SwiftUI
import Conferbot

struct ContentView: View {
    @ObservedObject private var bot = ConferBot.shared

    @State private var showChatSheet = false
    @State private var selectedPattern: Pattern = .modal

    enum Pattern: String, CaseIterable, Identifiable {
        case modal    = "Modal (Sheet)"
        case embedded = "Embedded"
        var id: String { rawValue }
    }

    var body: some View {
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

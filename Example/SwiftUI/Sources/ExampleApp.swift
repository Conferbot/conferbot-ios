//
//  ExampleApp.swift
//  ConferbotExample
//
//  Minimal SwiftUI example app for the Conferbot iOS SDK.
//  Pre-configured with the public Conferbot demo bot so it works
//  out of the box - swap in your own API key and bot ID from the
//  Conferbot dashboard when you are ready.
//

import SwiftUI
import Conferbot

@main
struct ExampleApp: App {

    init() {
        // ------------------------------------------------------------------
        // SDK Initialization
        // ------------------------------------------------------------------
        // Call initialize() once, as early as possible. This establishes the
        // socket connection and restores any persisted session automatically.

        let config = ConferBotConfig(
            enableNotifications: true,
            enableOfflineMode: true
        )

        let customization = ConferBotCustomization(
            primaryColor: .systemBlue,
            headerTitle: "Conferbot Demo",
            showAvatar: true
        )

        ConferBot.shared.initialize(
            apiKey: "conf_test_key_12345",          // Public demo key - replace with your Conferbot API key (conf_...)
            botId: "691c970890527a0468f9b2c9",      // Public demo bot - replace with your bot ID
            config: config,
            customization: customization
        )

        // Optional: identify the current user so the bot has context.
        // ConferBot.shared.identify(user: ConferBotUser(
        //     id: "user-123",
        //     name: "Jane Doe",
        //     email: "jane@example.com"
        // ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

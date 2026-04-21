//
//  ExampleApp.swift
//  ConferbotExample
//
//  Minimal SwiftUI example app for the Conferbot iOS SDK.
//  Replace YOUR_API_KEY and YOUR_BOT_ID with real values from
//  your Conferbot dashboard before running.
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
            apiKey: "YOUR_API_KEY",       // Replace with your Conferbot API key (conf_...)
            botId: "YOUR_BOT_ID",         // Replace with your bot ID
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

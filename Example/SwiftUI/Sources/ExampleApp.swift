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
import UserNotifications
import Conferbot

/// Push notifications (README "Push notifications"): the APNs token goes to
/// the SDK, a tapped Conferbot notification opens its chat, one that arrives
/// in the foreground only counts as unread. Try it on a simulator with
/// `xcrun simctl push booted com.conferbot.example payload.apns`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        ConferBot.shared.setPushToken(deviceToken)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ConferBot.shared.handlePushNotification(response.notification.request.content.userInfo)
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let ours = ConferBot.shared.handlePushNotification(notification.request.content.userInfo, open: false)
        completionHandler(ours ? [] : [.banner, .sound])
    }
}

@main
struct ExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

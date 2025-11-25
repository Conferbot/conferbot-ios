# Examples

Real-world examples of integrating Conferbot iOS SDK into your app.

## Table of Contents

1. [E-commerce App](#e-commerce-app)
2. [Banking App](#banking-app)
3. [SaaS Dashboard](#saas-dashboard)
4. [Healthcare App](#healthcare-app)
5. [Custom UI Examples](#custom-ui-examples)

## E-commerce App

### Product Support Button

```swift
import UIKit
import Conferbot

class ProductDetailViewController: UIViewController {
    let product: Product

    init(product: Product) {
        self.product = product
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let supportButton = UIButton(type: .system)
        supportButton.setTitle("Ask about this product", for: .normal)
        supportButton.addTarget(self, action: #selector(askSupport), for: .touchUpInside)

        view.addSubview(supportButton)
        // Layout...
    }

    @objc func askSupport() {
        // Pre-fill message with product context
        Task {
            try? await Conferbot.shared.startSession()
            try? await Conferbot.shared.sendMessage(
                "I have a question about \(product.name)",
                metadata: [
                    "productId": AnyCodable(product.id),
                    "productName": AnyCodable(product.name),
                    "price": AnyCodable(product.price)
                ]
            )
        }

        Conferbot.shared.present(from: self)
    }
}
```

### Cart Abandonment Support

```swift
class CheckoutViewController: UIViewController {
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Detect cart abandonment
        if isLeavingWithoutPurchase() {
            showAbandonmentSupport()
        }
    }

    func showAbandonmentSupport() {
        let alert = UIAlertController(
            title: "Need help?",
            message: "Have questions about checkout? Chat with us!",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Chat Now", style: .default) { _ in
            Conferbot.shared.present(from: self)
        })

        alert.addAction(UIAlertAction(title: "No Thanks", style: .cancel))

        present(alert, animated: true)
    }
}
```

## Banking App

### Secure Chat with Biometrics

```swift
import UIKit
import LocalAuthentication
import Conferbot

class SecureChatViewController: UIViewController {
    let context = LAContext()

    @IBAction func openSecureChatTapped(_ sender: UIButton) {
        authenticateUser()
    }

    func authenticateUser() {
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Authenticate to access secure support chat"

            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.openChat()
                    } else {
                        self?.showAuthError()
                    }
                }
            }
        } else {
            // Fallback to passcode
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.openChat()
                    }
                }
            }
        }
    }

    func openChat() {
        // Identify user with account info
        let user = ConferBotUser(
            id: CurrentUser.accountNumber,
            name: CurrentUser.fullName,
            email: CurrentUser.email,
            metadata: [
                "accountType": AnyCodable(CurrentUser.accountType),
                "balance": AnyCodable(CurrentUser.balance),
                "branch": AnyCodable(CurrentUser.branchCode)
            ]
        )

        Conferbot.shared.identify(user: user)
        Conferbot.shared.present(from: self)
    }
}
```

### Transaction Dispute

```swift
class TransactionDetailViewController: UIViewController {
    let transaction: Transaction

    @IBAction func disputeTransactionTapped(_ sender: UIButton) {
        Task {
            try? await Conferbot.shared.startSession()
            try? await Conferbot.shared.sendMessage(
                "I want to dispute a transaction",
                metadata: [
                    "transactionId": AnyCodable(transaction.id),
                    "amount": AnyCodable(transaction.amount),
                    "merchant": AnyCodable(transaction.merchant),
                    "date": AnyCodable(transaction.date.ISO8601Format())
                ]
            )
        }

        Conferbot.shared.present(from: self)
    }
}
```

## SaaS Dashboard

### SwiftUI Integration

```swift
import SwiftUI
import Conferbot

@main
struct DashboardApp: App {
    init() {
        // Initialize Conferbot
        Conferbot.shared.initialize(
            apiKey: "conf_sk_...",
            botId: "bot_...",
            config: ConferBotConfig(
                enableNotifications: true,
                enableOfflineMode: true
            ),
            customization: ConferBotCustomization(
                primaryColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0),
                headerTitle: "Support",
                showAvatar: true
            )
        )

        // Identify user
        if let user = AuthManager.shared.currentUser {
            Conferbot.shared.identify(user: ConferBotUser(
                id: user.id,
                name: user.name,
                email: user.email,
                metadata: [
                    "plan": AnyCodable(user.subscriptionPlan),
                    "mrr": AnyCodable(user.monthlyRevenue),
                    "signupDate": AnyCodable(user.signupDate.ISO8601Format())
                ]
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @State private var showSupport = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSupport = true
                } label: {
                    Image(systemName: "message")
                }
            }
        }
        .sheet(isPresented: $showSupport) {
            NavigationView {
                ChatView()
                    .navigationTitle("Support")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showSupport = false
                            }
                        }
                    }
            }
        }
    }
}
```

### Unread Message Badge

```swift
struct SupportButton: View {
    @ObservedObject var conferBot = ConferBot.shared

    var body: some View {
        Button {
            // Open chat
        } label: {
            HStack {
                Image(systemName: "message.fill")

                if conferBot.unreadCount > 0 {
                    Text("\(conferBot.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
        }
    }
}
```

## Healthcare App

### HIPAA-Compliant Chat

```swift
import Conferbot

class PatientPortalViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure for healthcare compliance
        let config = ConferBotConfig(
            enableNotifications: false,  // Don't show message content in notifications
            enableOfflineMode: false     // Don't cache sensitive data
        )

        Conferbot.shared.initialize(
            apiKey: "conf_sk_...",
            botId: "bot_healthcare",
            config: config
        )

        // Identify patient
        if let patient = CurrentPatient.shared {
            Conferbot.shared.identify(user: ConferBotUser(
                id: patient.mrn,  // Medical Record Number
                name: patient.fullName,
                metadata: [
                    "dob": AnyCodable(patient.dateOfBirth.ISO8601Format()),
                    "provider": AnyCodable(patient.primaryProvider),
                    "insuranceId": AnyCodable(patient.insuranceId)
                ]
            ))
        }
    }

    @IBAction func contactNurseTapped(_ sender: UIButton) {
        Task {
            try? await Conferbot.shared.startSession()
            try? await Conferbot.shared.sendMessage("I need to speak with a nurse")
            Conferbot.shared.initiateHandover(message: "Patient requesting nurse")
        }

        Conferbot.shared.present(from: self)
    }
}
```

### Appointment Scheduling

```swift
class AppointmentViewController: UIViewController, ConferBotDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        Conferbot.shared.delegate = self
    }

    @IBAction func scheduleAppointmentTapped(_ sender: UIButton) {
        Task {
            try? await Conferbot.shared.startSession()
            try? await Conferbot.shared.sendMessage("I'd like to schedule an appointment")
        }

        Conferbot.shared.present(from: self)
    }

    // Handle appointment confirmation
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {
        if let botMessage = message as? BotMessageRecord,
           let nodeData = botMessage.nodeData,
           nodeData["type"]?.value as? String == "appointment-confirmed" {

            // Extract appointment details
            if let appointmentData = nodeData["appointment"]?.value as? [String: Any] {
                let appointment = Appointment(from: appointmentData)
                saveToCalendar(appointment)
            }
        }
    }

    func saveToCalendar(_ appointment: Appointment) {
        // Add to device calendar
    }
}
```

## Custom UI Examples

### Floating Action Button (SwiftUI)

```swift
struct MainView: View {
    @State private var showChat = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ContentView()

            Button {
                showChat = true
            } label: {
                Image(systemName: "message.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(20)
        }
        .sheet(isPresented: $showChat) {
            ChatView()
        }
    }
}
```

### Custom Navigation Bar

```swift
class CustomChatViewController: ChatViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Custom navigation items
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "phone.fill"),
                style: .plain,
                target: self,
                action: #selector(callSupportTapped)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis"),
                style: .plain,
                target: self,
                action: #selector(moreOptionsTapped)
            )
        ]
    }

    @objc func callSupportTapped() {
        if let url = URL(string: "tel://18005551234") {
            UIApplication.shared.open(url)
        }
    }

    @objc func moreOptionsTapped() {
        let actionSheet = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .actionSheet
        )

        actionSheet.addAction(UIAlertAction(title: "Email Transcript", style: .default) { _ in
            self.emailTranscript()
        })

        actionSheet.addAction(UIAlertAction(title: "Clear History", style: .destructive) { _ in
            Conferbot.shared.clearHistory()
        })

        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(actionSheet, animated: true)
    }

    func emailTranscript() {
        // Email conversation history
    }
}
```

### Embedded Chat in Tab

```swift
class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let homeVC = HomeViewController()
        let productsVC = ProductsViewController()
        let supportVC = createSupportTab()
        let profileVC = ProfileViewController()

        viewControllers = [
            UINavigationController(rootViewController: homeVC),
            UINavigationController(rootViewController: productsVC),
            supportVC,
            UINavigationController(rootViewController: profileVC)
        ]
    }

    func createSupportTab() -> UIViewController {
        let chatVC = ChatViewController()
        chatVC.title = "Support"
        chatVC.tabBarItem = UITabBarItem(
            title: "Support",
            image: UIImage(systemName: "message"),
            selectedImage: UIImage(systemName: "message.fill")
        )

        let navController = UINavigationController(rootViewController: chatVC)
        return navController
    }
}
```

### Custom Message Handling

```swift
class SmartChatManager: ConferBotDelegate {
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {
        // Log to analytics
        Analytics.logEvent("chat_message_received", parameters: [
            "type": message.type.rawValue
        ])

        // Handle specific message types
        if let botMessage = message as? BotMessageRecord {
            handleBotMessage(botMessage)
        } else if let agentMessage = message as? AgentMessageRecord {
            handleAgentMessage(agentMessage)
        }
    }

    func handleBotMessage(_ message: BotMessageRecord) {
        guard let nodeData = message.nodeData,
              let nodeType = nodeData["nodeType"]?.value as? String else {
            return
        }

        switch nodeType {
        case "product-recommendation":
            showProductRecommendation(nodeData)
        case "discount-offer":
            showDiscountOffer(nodeData)
        case "calendar-booking":
            showCalendarBooking(nodeData)
        default:
            break
        }
    }

    func handleAgentMessage(_ message: AgentMessageRecord) {
        // Show local notification if app is in background
        if UIApplication.shared.applicationState == .background {
            sendLocalNotification(
                title: message.agentDetails.name,
                body: message.text
            )
        }
    }
}
```

### Rate Limiting

```swift
class RateLimitedChatManager {
    private var lastMessageTime: Date?
    private let minimumInterval: TimeInterval = 2.0  // 2 seconds between messages

    func sendMessage(_ text: String) {
        let now = Date()

        if let lastTime = lastMessageTime,
           now.timeIntervalSince(lastTime) < minimumInterval {
            showRateLimitWarning()
            return
        }

        lastMessageTime = now

        Task {
            try? await Conferbot.shared.sendMessage(text)
        }
    }

    func showRateLimitWarning() {
        let alert = UIAlertController(
            title: "Please wait",
            message: "You're sending messages too quickly. Please wait a moment.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))

        // Present alert...
    }
}
```

### Deep Linking

```swift
// AppDelegate
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
    // Handle deep link: yourapp://support?topic=billing
    if url.scheme == "yourapp" && url.host == "support" {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let topic = components?.queryItems?.first(where: { $0.name == "topic" })?.value

        openSupport(topic: topic)
        return true
    }

    return false
}

func openSupport(topic: String?) {
    Task {
        try? await Conferbot.shared.startSession()

        if let topic = topic {
            try? await Conferbot.shared.sendMessage("I need help with \(topic)")
        }
    }

    if let rootVC = window?.rootViewController {
        Conferbot.shared.present(from: rootVC)
    }
}
```

These examples demonstrate real-world integrations across different industries and use cases. Adapt them to your specific needs!

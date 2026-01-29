//
//  NodeComponents.swift
//  Conferbot
//
//  Created by Conferbot SDK
//  Comprehensive SwiftUI components for all 51 node types
//

import SwiftUI
import AVKit
import WebKit
import UniformTypeIdentifiers

// MARK: - NodeUIState

/// UI state representation for all node types
/// Mirrors the Android SDK's NodeUIState sealed class
@available(iOS 14.0, *)
public enum NodeUIState {
    case message(text: String, isTyping: Bool = false, nodeId: String)
    case image(url: String, caption: String?, nodeId: String)
    case video(url: String, caption: String?, nodeId: String)
    case audio(url: String, caption: String?, nodeId: String)
    case file(url: String, fileName: String, nodeId: String)
    case gif(url: String, caption: String?, nodeId: String)
    case textInput(TextInputState)
    case singleChoice(SingleChoiceState)
    case multipleChoice(MultipleChoiceState)
    case buttons(ButtonsState)
    case quickReplies(QuickRepliesState)
    case cardsCarousel(CardsCarouselState)
    case rating(RatingState)
    case opinionScale(OpinionScaleState)
    case calendar(CalendarState)
    case fileUpload(FileUploadState)
    case liveChat(LiveChatState)
    case link(LinkState)
    case embed(EmbedState)
    case loading(nodeId: String)
    case dropdown(DropdownState)
    case range(RangeState)
    case quiz(QuizState)
    case multipleQuestions(MultipleQuestionsState)
    case humanHandover(HumanHandoverState)
    case html(htmlContent: String, nodeId: String)
    case payment(PaymentState)
    case redirect(url: String, openInNewTab: Bool, nodeId: String)
    case imageChoice(ImageChoiceState)
}

// MARK: - State Types

@available(iOS 14.0, *)
public struct TextInputState {
    public let questionText: String
    public let inputType: InputType
    public let placeholder: String?
    public let validationRegex: String?
    public let errorMessage: String?
    public let nodeId: String
    public let answerKey: String

    public enum InputType {
        case text, name, email, phone, number, url, location

        var keyboardType: UIKeyboardType {
            switch self {
            case .email: return .emailAddress
            case .phone: return .phonePad
            case .number: return .decimalPad
            case .url: return .URL
            default: return .default
            }
        }
    }

    public init(
        questionText: String,
        inputType: InputType = .text,
        placeholder: String? = nil,
        validationRegex: String? = nil,
        errorMessage: String? = nil,
        nodeId: String,
        answerKey: String
    ) {
        self.questionText = questionText
        self.inputType = inputType
        self.placeholder = placeholder
        self.validationRegex = validationRegex
        self.errorMessage = errorMessage
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct SingleChoiceState {
    public let questionText: String?
    public let choices: [Choice]
    public let nodeId: String
    public let answerKey: String

    public struct Choice: Identifiable {
        public let id: String
        public let text: String
        public let imageUrl: String?
        public let targetPort: String?

        public init(id: String, text: String, imageUrl: String? = nil, targetPort: String? = nil) {
            self.id = id
            self.text = text
            self.imageUrl = imageUrl
            self.targetPort = targetPort
        }
    }

    public init(questionText: String?, choices: [Choice], nodeId: String, answerKey: String) {
        self.questionText = questionText
        self.choices = choices
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct MultipleChoiceState {
    public let questionText: String?
    public let options: [Option]
    public let nodeId: String
    public let answerKey: String
    public let minSelections: Int
    public let maxSelections: Int?

    public struct Option: Identifiable {
        public let id: String
        public let text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    public init(
        questionText: String?,
        options: [Option],
        nodeId: String,
        answerKey: String,
        minSelections: Int = 1,
        maxSelections: Int? = nil
    ) {
        self.questionText = questionText
        self.options = options
        self.nodeId = nodeId
        self.answerKey = answerKey
        self.minSelections = minSelections
        self.maxSelections = maxSelections
    }
}

@available(iOS 14.0, *)
public struct ButtonsState {
    public let questionText: String?
    public let buttons: [ButtonItem]
    public let layout: Layout
    public let nodeId: String

    public enum Layout {
        case horizontal, vertical
    }

    public struct ButtonItem: Identifiable {
        public let id: String
        public let text: String
        public let style: ButtonStyle
        public let targetPort: String?

        public enum ButtonStyle {
            case primary, secondary, outline
        }

        public init(id: String, text: String, style: ButtonStyle = .primary, targetPort: String? = nil) {
            self.id = id
            self.text = text
            self.style = style
            self.targetPort = targetPort
        }
    }

    public init(questionText: String?, buttons: [ButtonItem], layout: Layout = .vertical, nodeId: String) {
        self.questionText = questionText
        self.buttons = buttons
        self.layout = layout
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct QuickRepliesState {
    public let questionText: String?
    public let replies: [Reply]
    public let nodeId: String

    public struct Reply: Identifiable {
        public let id: String
        public let text: String
        public let icon: String?

        public init(id: String, text: String, icon: String? = nil) {
            self.id = id
            self.text = text
            self.icon = icon
        }
    }

    public init(questionText: String?, replies: [Reply], nodeId: String) {
        self.questionText = questionText
        self.replies = replies
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct CardsCarouselState {
    public let cards: [Card]
    public let nodeId: String

    public struct Card: Identifiable {
        public let id: String
        public let imageUrl: String?
        public let title: String
        public let subtitle: String?
        public let buttons: [CardButton]

        public struct CardButton: Identifiable {
            public let id: String
            public let text: String
            public let action: CardAction

            public enum CardAction {
                case link(url: String)
                case response(value: String)
            }

            public init(id: String, text: String, action: CardAction) {
                self.id = id
                self.text = text
                self.action = action
            }
        }

        public init(id: String, imageUrl: String?, title: String, subtitle: String?, buttons: [CardButton]) {
            self.id = id
            self.imageUrl = imageUrl
            self.title = title
            self.subtitle = subtitle
            self.buttons = buttons
        }
    }

    public init(cards: [Card], nodeId: String) {
        self.cards = cards
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct RatingState {
    public let questionText: String?
    public let ratingType: RatingType
    public let minValue: Int
    public let maxValue: Int
    public let nodeId: String
    public let answerKey: String

    public enum RatingType {
        case star, number, smiley, thumbs, hearts
    }

    public init(
        questionText: String?,
        ratingType: RatingType,
        minValue: Int = 1,
        maxValue: Int = 5,
        nodeId: String,
        answerKey: String
    ) {
        self.questionText = questionText
        self.ratingType = ratingType
        self.minValue = minValue
        self.maxValue = maxValue
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct OpinionScaleState {
    public let questionText: String?
    public let minValue: Int
    public let maxValue: Int
    public let minLabel: String?
    public let maxLabel: String?
    public let nodeId: String
    public let answerKey: String

    public init(
        questionText: String?,
        minValue: Int = 0,
        maxValue: Int = 10,
        minLabel: String? = nil,
        maxLabel: String? = nil,
        nodeId: String,
        answerKey: String
    ) {
        self.questionText = questionText
        self.minValue = minValue
        self.maxValue = maxValue
        self.minLabel = minLabel
        self.maxLabel = maxLabel
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct CalendarState {
    public let questionText: String?
    public let mode: CalendarMode
    public let showTimeSelection: Bool
    public let timezone: String?
    public let minDate: Date?
    public let maxDate: Date?
    public let availableSlots: [TimeSlot]?
    public let nodeId: String
    public let answerKey: String

    public enum CalendarMode {
        case date, time, dateTime, slot
    }

    public struct TimeSlot: Identifiable {
        public let id: String
        public let date: Date
        public let time: String?
        public let available: Bool

        public init(id: String = UUID().uuidString, date: Date, time: String? = nil, available: Bool = true) {
            self.id = id
            self.date = date
            self.time = time
            self.available = available
        }
    }

    public init(
        questionText: String?,
        mode: CalendarMode = .date,
        showTimeSelection: Bool = false,
        timezone: String? = nil,
        minDate: Date? = nil,
        maxDate: Date? = nil,
        availableSlots: [TimeSlot]? = nil,
        nodeId: String,
        answerKey: String
    ) {
        self.questionText = questionText
        self.mode = mode
        self.showTimeSelection = showTimeSelection
        self.timezone = timezone
        self.minDate = minDate
        self.maxDate = maxDate
        self.availableSlots = availableSlots
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct FileUploadState {
    public let questionText: String
    public let maxSizeMb: Int
    public let allowedTypes: [String]?
    public let nodeId: String
    public let answerKey: String

    public init(
        questionText: String,
        maxSizeMb: Int = 5,
        allowedTypes: [String]? = nil,
        nodeId: String,
        answerKey: String
    ) {
        self.questionText = questionText
        self.maxSizeMb = maxSizeMb
        self.allowedTypes = allowedTypes
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct LiveChatState {
    public let status: LiveChatStatus
    public let agentName: String?
    public let agentAvatar: String?
    public let waitTime: Int?
    public let position: Int?
    public let nodeId: String

    public enum LiveChatStatus {
        case connecting
        case waiting
        case connected
        case ended
        case unavailable
    }

    public init(
        status: LiveChatStatus,
        agentName: String? = nil,
        agentAvatar: String? = nil,
        waitTime: Int? = nil,
        position: Int? = nil,
        nodeId: String
    ) {
        self.status = status
        self.agentName = agentName
        self.agentAvatar = agentAvatar
        self.waitTime = waitTime
        self.position = position
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct LinkState {
    public let url: String
    public let title: String?
    public let description: String?
    public let imageUrl: String?
    public let nodeId: String

    public init(url: String, title: String? = nil, description: String? = nil, imageUrl: String? = nil, nodeId: String) {
        self.url = url
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct EmbedState {
    public let embedUrl: String
    public let height: CGFloat
    public let nodeId: String

    public init(embedUrl: String, height: CGFloat = 300, nodeId: String) {
        self.embedUrl = embedUrl
        self.height = height
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct DropdownState {
    public let questionText: String?
    public let options: [Option]
    public let nodeId: String
    public let answerKey: String

    public struct Option: Identifiable {
        public let id: String
        public let text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    public init(questionText: String?, options: [Option], nodeId: String, answerKey: String) {
        self.questionText = questionText
        self.options = options
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct RangeState {
    public let questionText: String?
    public let minValue: Int
    public let maxValue: Int
    public let defaultValue: Int?
    public let step: Int
    public let nodeId: String
    public let answerKey: String

    public init(
        questionText: String?,
        minValue: Int = 0,
        maxValue: Int = 100,
        defaultValue: Int? = nil,
        step: Int = 1,
        nodeId: String,
        answerKey: String
    ) {
        self.questionText = questionText
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.step = step
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct QuizState {
    public let questionText: String
    public let options: [String]
    public let correctAnswerIndex: Int
    public let nodeId: String
    public let answerKey: String

    public init(questionText: String, options: [String], correctAnswerIndex: Int, nodeId: String, answerKey: String) {
        self.questionText = questionText
        self.options = options
        self.correctAnswerIndex = correctAnswerIndex
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

@available(iOS 14.0, *)
public struct MultipleQuestionsState {
    public let questions: [Question]
    public let currentIndex: Int
    public let nodeId: String

    public struct Question {
        public let questionText: String
        public let answerType: String
        public let answerKey: String

        public init(questionText: String, answerType: String, answerKey: String) {
            self.questionText = questionText
            self.answerType = answerType
            self.answerKey = answerKey
        }
    }

    public init(questions: [Question], currentIndex: Int, nodeId: String) {
        self.questions = questions
        self.currentIndex = currentIndex
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct HumanHandoverState {
    public let state: HandoverStatus
    public let preChatQuestions: [PreChatQuestion]?
    public let currentQuestionIndex: Int
    public let handoverMessage: String?
    public let maxWaitTime: Int?
    public let agentName: String?
    public let nodeId: String

    public enum HandoverStatus {
        case preChatQuestions
        case waitingForAgent
        case agentConnected
        case noAgentsAvailable
        case postChatSurvey
    }

    public struct PreChatQuestion: Identifiable {
        public let id: String
        public let questionText: String
        public let answerType: String
        public let answerKey: String

        public init(id: String, questionText: String, answerType: String, answerKey: String) {
            self.id = id
            self.questionText = questionText
            self.answerType = answerType
            self.answerKey = answerKey
        }
    }

    public init(
        state: HandoverStatus,
        preChatQuestions: [PreChatQuestion]? = nil,
        currentQuestionIndex: Int = 0,
        handoverMessage: String? = nil,
        maxWaitTime: Int? = nil,
        agentName: String? = nil,
        nodeId: String
    ) {
        self.state = state
        self.preChatQuestions = preChatQuestions
        self.currentQuestionIndex = currentQuestionIndex
        self.handoverMessage = handoverMessage
        self.maxWaitTime = maxWaitTime
        self.agentName = agentName
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct PaymentState {
    public let paymentUrl: String
    public let amount: Double?
    public let currency: String?
    public let description: String?
    public let nodeId: String

    public init(paymentUrl: String, amount: Double? = nil, currency: String? = nil, description: String? = nil, nodeId: String) {
        self.paymentUrl = paymentUrl
        self.amount = amount
        self.currency = currency
        self.description = description
        self.nodeId = nodeId
    }
}

@available(iOS 14.0, *)
public struct ImageChoiceState {
    public let questionText: String?
    public let images: [ImageOption]
    public let nodeId: String
    public let answerKey: String

    public struct ImageOption: Identifiable {
        public let id: String
        public let imageUrl: String
        public let label: String
        public let targetPort: String?

        public init(id: String, imageUrl: String, label: String, targetPort: String? = nil) {
            self.id = id
            self.imageUrl = imageUrl
            self.label = label
            self.targetPort = targetPort
        }
    }

    public init(questionText: String?, images: [ImageOption], nodeId: String, answerKey: String) {
        self.questionText = questionText
        self.images = images
        self.nodeId = nodeId
        self.answerKey = answerKey
    }
}

// MARK: - Theme Environment

@available(iOS 14.0, *)
public struct ChatTheme {
    public let primaryColor: Color
    public let secondaryColor: Color
    public let backgroundColor: Color
    public let botBubbleColor: Color
    public let userBubbleColor: Color
    public let textColor: Color
    public let bubbleCornerRadius: CGFloat
    public let fontFamily: String?

    public init(
        primaryColor: Color = .blue,
        secondaryColor: Color = Color(UIColor.systemGray5),
        backgroundColor: Color = Color(UIColor.systemBackground),
        botBubbleColor: Color = Color(UIColor.systemGray5),
        userBubbleColor: Color = .blue,
        textColor: Color = .primary,
        bubbleCornerRadius: CGFloat = 16,
        fontFamily: String? = nil
    ) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.backgroundColor = backgroundColor
        self.botBubbleColor = botBubbleColor
        self.userBubbleColor = userBubbleColor
        self.textColor = textColor
        self.bubbleCornerRadius = bubbleCornerRadius
        self.fontFamily = fontFamily
    }

    public static let `default` = ChatTheme()
}

@available(iOS 14.0, *)
private struct ChatThemeKey: EnvironmentKey {
    static let defaultValue = ChatTheme.default
}

@available(iOS 14.0, *)
public extension EnvironmentValues {
    var chatTheme: ChatTheme {
        get { self[ChatThemeKey.self] }
        set { self[ChatThemeKey.self] = newValue }
    }
}

// MARK: - Main Router View

/// Main node renderer that routes to appropriate component based on NodeUIState
@available(iOS 14.0, *)
public struct NodeRenderer: View {
    let uiState: NodeUIState
    let onInput: (Any) -> Void

    @Environment(\.chatTheme) private var theme

    public init(uiState: NodeUIState, onInput: @escaping (Any) -> Void) {
        self.uiState = uiState
        self.onInput = onInput
    }

    public var body: some View {
        Group {
            switch uiState {
            case .message(let text, let isTyping, _):
                MessageBubbleNode(text: text, isTyping: isTyping)

            case .image(let url, let caption, _):
                ImageMessage(url: url, caption: caption)

            case .video(let url, let caption, _):
                VideoMessage(url: url, caption: caption)

            case .audio(let url, let caption, _):
                AudioMessage(url: url, caption: caption)

            case .file(let url, let fileName, _):
                FileMessage(url: url, fileName: fileName)

            case .gif(let url, let caption, _):
                GifMessage(url: url, caption: caption)

            case .textInput(let state):
                TextInputView(state: state, onSubmit: onInput)

            case .singleChoice(let state):
                SingleChoiceView(state: state, onSelect: onInput)

            case .multipleChoice(let state):
                MultiChoiceView(state: state, onSubmit: onInput)

            case .buttons(let state):
                ButtonsView(state: state, onTap: onInput)

            case .quickReplies(let state):
                QuickRepliesView(state: state, onTap: onInput)

            case .cardsCarousel(let state):
                CardsCarousel(state: state, onAction: onInput)

            case .rating(let state):
                RatingView(state: state, onRate: onInput)

            case .opinionScale(let state):
                OpinionScaleView(state: state, onSelect: onInput)

            case .calendar(let state):
                CalendarPicker(state: state, onSelect: onInput)

            case .fileUpload(let state):
                FileUploadView(state: state, onUpload: onInput)

            case .liveChat(let state):
                LiveChatView(state: state)

            case .link(let state):
                LinkView(state: state)

            case .embed(let state):
                EmbedView(state: state)

            case .loading(_):
                LoadingView()

            case .dropdown(let state):
                DropdownView(state: state, onSelect: onInput)

            case .range(let state):
                RangeView(state: state, onSubmit: onInput)

            case .quiz(let state):
                QuizView(state: state, onAnswer: onInput)

            case .multipleQuestions(let state):
                MultipleQuestionsView(state: state, onSubmit: onInput)

            case .humanHandover(let state):
                HumanHandoverView(state: state, onResponse: onInput)

            case .html(let content, _):
                HtmlView(htmlContent: content)

            case .payment(let state):
                PaymentView(state: state)

            case .redirect(let url, _, _):
                RedirectView(url: url)

            case .imageChoice(let state):
                ImageChoiceView(state: state, onSelect: onInput)
            }
        }
    }
}

// MARK: - 1. MessageBubble

@available(iOS 14.0, *)
public struct MessageBubbleNode: View {
    let text: String
    let isTyping: Bool

    @Environment(\.chatTheme) private var theme

    public init(text: String, isTyping: Bool = false) {
        self.text = text
        self.isTyping = isTyping
    }

    public var body: some View {
        HStack {
            if isTyping {
                TypingIndicatorView()
            } else {
                Text(text)
                    .padding(12)
                    .background(theme.botBubbleColor)
                    .foregroundColor(theme.textColor)
                    .cornerRadius(theme.bubbleCornerRadius)
            }
            Spacer()
        }
    }
}

// MARK: - 2. ImageMessage

@available(iOS 14.0, *)
public struct ImageMessage: View {
    let url: String
    let caption: String?

    @Environment(\.chatTheme) private var theme
    @State private var showFullScreen = false

    public init(url: String, caption: String? = nil) {
        self.url = url
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .onTapGesture {
                            showFullScreen = true
                        }
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.systemGray5))
                        .cornerRadius(12)
                case .empty:
                    ProgressView()
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 280)

            if let caption = caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            ImageFullScreenView(url: url, isPresented: $showFullScreen)
        }
    }
}

@available(iOS 14.0, *)
private struct ImageFullScreenView: View {
    let url: String
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: URL(string: url)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - 3. VideoMessage

@available(iOS 14.0, *)
public struct VideoMessage: View {
    let url: String
    let caption: String?

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    public init(url: String, caption: String? = nil) {
        self.url = url
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 200)
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 200)
                        .cornerRadius(12)
                        .overlay(
                            Button(action: loadVideo) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                            }
                        )
                }
            }
            .frame(maxWidth: 280)

            if let caption = caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadVideo() {
        guard let videoURL = URL(string: url) else { return }
        player = AVPlayer(url: videoURL)
        player?.play()
        isPlaying = true
    }
}

// MARK: - 4. AudioMessage

@available(iOS 14.0, *)
public struct AudioMessage: View {
    let url: String
    let caption: String?

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0

    public init(url: String, caption: String? = nil) {
        self.url = url
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color(UIColor.systemGray4))
                                .frame(height: 4)
                                .cornerRadius(2)

                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * CGFloat(progress), height: 4)
                                .cornerRadius(2)
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Text(formatTime(progress * duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
            .frame(maxWidth: 280)

            if let caption = caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func togglePlayback() {
        if player == nil {
            guard let audioURL = URL(string: url) else { return }
            player = AVPlayer(url: audioURL)

            if let duration = player?.currentItem?.asset.duration {
                self.duration = CMTimeGetSeconds(duration)
            }
        }

        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - 5. FileMessage

@available(iOS 14.0, *)
public struct FileMessage: View {
    let url: String
    let fileName: String

    public init(url: String, fileName: String) {
        self.url = url
        self.fileName = fileName
    }

    public var body: some View {
        Button(action: downloadFile) {
            HStack(spacing: 12) {
                Image(systemName: fileIcon)
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("Tap to download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .padding(12)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 280)
    }

    private var fileIcon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "doc.richtext.fill"
        case "zip", "rar": return "doc.zipper"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "mp4", "mov", "avi": return "film.fill"
        default: return "doc.fill"
        }
    }

    private func downloadFile() {
        guard let fileURL = URL(string: url) else { return }
        UIApplication.shared.open(fileURL)
    }
}

// MARK: - 6. GifMessage

@available(iOS 14.0, *)
public struct GifMessage: View {
    let url: String
    let caption: String?

    public init(url: String, caption: String? = nil) {
        self.url = url
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.systemGray5))
                        .cornerRadius(12)
                case .empty:
                    ProgressView()
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 250)

            if let caption = caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 7. TextInputView

@available(iOS 14.0, *)
public struct TextInputView: View {
    let state: TextInputState
    let onSubmit: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var text = ""
    @State private var errorText: String?
    @State private var isSubmitted = false

    public init(state: TextInputState, onSubmit: @escaping (Any) -> Void) {
        self.state = state
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.questionText.isEmpty {
                MessageBubbleNode(text: state.questionText)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField(state.placeholder ?? "Type here...", text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(state.inputType.keyboardType)
                    .autocapitalization(state.inputType == .email ? .none : .sentences)
                    .disableAutocorrection(state.inputType == .email || state.inputType == .url)
                    .disabled(isSubmitted)
                    .onSubmit {
                        validateAndSubmit()
                    }

                if let error = errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Button(action: validateAndSubmit) {
                Text("Submit")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isSubmitted ? Color.gray : theme.primaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitted)
        }
        .padding(.horizontal, 4)
    }

    private func validateAndSubmit() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            errorText = "Please enter a value"
            return
        }

        // Validate based on input type
        switch state.inputType {
        case .email:
            if !isValidEmail(trimmedText) {
                errorText = state.errorMessage ?? "Please enter a valid email address"
                return
            }
        case .phone:
            if !isValidPhone(trimmedText) {
                errorText = state.errorMessage ?? "Please enter a valid phone number"
                return
            }
        case .url:
            if !isValidURL(trimmedText) {
                errorText = state.errorMessage ?? "Please enter a valid URL"
                return
            }
        case .number:
            if Double(trimmedText) == nil {
                errorText = state.errorMessage ?? "Please enter a valid number"
                return
            }
        default:
            break
        }

        // Custom regex validation
        if let regex = state.validationRegex, !regex.isEmpty {
            let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
            if !predicate.evaluate(with: trimmedText) {
                errorText = state.errorMessage ?? "Invalid input format"
                return
            }
        }

        errorText = nil
        isSubmitted = true
        onSubmit(trimmedText)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = "^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: email)
    }

    private func isValidPhone(_ phone: String) -> Bool {
        let cleaned = phone.replacingOccurrences(of: "[\\s-()]", with: "", options: .regularExpression)
        let regex = "^[+]?[0-9]{7,15}$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: cleaned)
    }

    private func isValidURL(_ urlString: String) -> Bool {
        if let url = URL(string: urlString), url.scheme != nil, url.host != nil {
            return true
        }
        return false
    }
}

// MARK: - 8. SingleChoiceView

@available(iOS 14.0, *)
public struct SingleChoiceView: View {
    let state: SingleChoiceState
    let onSelect: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedId: String?

    public init(state: SingleChoiceState, onSelect: @escaping (Any) -> Void) {
        self.state = state
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            VStack(spacing: 8) {
                ForEach(state.choices) { choice in
                    Button(action: {
                        guard selectedId == nil else { return }
                        selectedId = choice.id
                        onSelect([
                            "id": choice.id,
                            "text": choice.text,
                            "targetPort": choice.targetPort as Any
                        ])
                    }) {
                        HStack {
                            Text(choice.text)
                                .fontWeight(.medium)
                            Spacer()
                            if selectedId == choice.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedId == choice.id
                                ? theme.primaryColor
                                : Color(UIColor.systemGray6)
                        )
                        .foregroundColor(selectedId == choice.id ? .white : .primary)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    selectedId == nil ? theme.primaryColor : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedId != nil)
                    .animation(.easeInOut(duration: 0.2), value: selectedId)
                }
            }
        }
    }
}

// MARK: - 9. MultiChoiceView

@available(iOS 14.0, *)
public struct MultiChoiceView: View {
    let state: MultipleChoiceState
    let onSubmit: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedIds: Set<String> = []
    @State private var isSubmitted = false

    public init(state: MultipleChoiceState, onSubmit: @escaping (Any) -> Void) {
        self.state = state
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            VStack(spacing: 8) {
                ForEach(state.options) { option in
                    let isSelected = selectedIds.contains(option.id)

                    Button(action: {
                        guard !isSubmitted else { return }
                        if isSelected {
                            selectedIds.remove(option.id)
                        } else {
                            if let max = state.maxSelections, selectedIds.count >= max {
                                return
                            }
                            selectedIds.insert(option.id)
                        }
                    }) {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(isSelected ? theme.primaryColor : .gray)
                            Text(option.text)
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            isSelected
                                ? theme.primaryColor.opacity(0.1)
                                : Color(UIColor.systemGray6)
                        )
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? theme.primaryColor : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isSubmitted)
                }
            }

            Button(action: {
                isSubmitted = true
                let selectedTexts = state.options
                    .filter { selectedIds.contains($0.id) }
                    .map { $0.text }
                onSubmit(selectedTexts)
            }) {
                Text("Submit")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedIds.count >= state.minSelections && !isSubmitted
                            ? theme.primaryColor
                            : Color.gray
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(selectedIds.count < state.minSelections || isSubmitted)
        }
    }
}

// MARK: - 10. ButtonsView

@available(iOS 14.0, *)
public struct ButtonsView: View {
    let state: ButtonsState
    let onTap: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var tappedId: String?

    public init(state: ButtonsState, onTap: @escaping (Any) -> Void) {
        self.state = state
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            if state.layout == .horizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        buttonViews
                    }
                }
            } else {
                VStack(spacing: 8) {
                    buttonViews
                }
            }
        }
    }

    @ViewBuilder
    private var buttonViews: some View {
        ForEach(state.buttons) { button in
            Button(action: {
                guard tappedId == nil else { return }
                tappedId = button.id
                onTap([
                    "id": button.id,
                    "text": button.text,
                    "targetPort": button.targetPort as Any
                ])
            }) {
                Text(button.text)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(buttonBackground(for: button))
                    .foregroundColor(buttonForeground(for: button))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                button.style == .outline ? theme.primaryColor : Color.clear,
                                lineWidth: 2
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(tappedId != nil)
            .opacity(tappedId != nil && tappedId != button.id ? 0.5 : 1)
        }
    }

    private func buttonBackground(for button: ButtonsState.ButtonItem) -> Color {
        switch button.style {
        case .primary: return theme.primaryColor
        case .secondary: return Color(UIColor.systemGray5)
        case .outline: return .clear
        }
    }

    private func buttonForeground(for button: ButtonsState.ButtonItem) -> Color {
        switch button.style {
        case .primary: return .white
        case .secondary: return .primary
        case .outline: return theme.primaryColor
        }
    }
}

// MARK: - 11. QuickRepliesView

@available(iOS 14.0, *)
public struct QuickRepliesView: View {
    let state: QuickRepliesState
    let onTap: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var tappedId: String?

    public init(state: QuickRepliesState, onTap: @escaping (Any) -> Void) {
        self.state = state
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.replies) { reply in
                        Button(action: {
                            guard tappedId == nil else { return }
                            tappedId = reply.id
                            onTap(["id": reply.id, "text": reply.text])
                        }) {
                            HStack(spacing: 6) {
                                if let icon = reply.icon {
                                    Image(systemName: icon)
                                        .font(.caption)
                                }
                                Text(reply.text)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                tappedId == reply.id
                                    ? theme.primaryColor
                                    : Color(UIColor.systemGray6)
                            )
                            .foregroundColor(tappedId == reply.id ? .white : .primary)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(theme.primaryColor, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(tappedId != nil)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - 12. CardsCarousel

@available(iOS 14.0, *)
public struct CardsCarousel: View {
    let state: CardsCarouselState
    let onAction: (Any) -> Void

    @Environment(\.chatTheme) private var theme

    public init(state: CardsCarouselState, onAction: @escaping (Any) -> Void) {
        self.state = state
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(state.cards) { card in
                    CardView(card: card, onAction: onAction)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

@available(iOS 14.0, *)
private struct CardView: View {
    let card: CardsCarouselState.Card
    let onAction: (Any) -> Void

    @Environment(\.chatTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageUrl = card.imageUrl {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 240, height: 140)
                            .clipped()
                    case .failure, .empty:
                        Rectangle()
                            .fill(Color(UIColor.systemGray5))
                            .frame(width: 240, height: 140)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.headline)
                    .lineLimit(2)

                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !card.buttons.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(card.buttons) { button in
                            Button(action: {
                                switch button.action {
                                case .link(let url):
                                    if let linkURL = URL(string: url) {
                                        UIApplication.shared.open(linkURL)
                                    }
                                case .response(let value):
                                    onAction(["cardId": card.id, "buttonId": button.id, "value": value])
                                }
                            }) {
                                Text(button.text)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(theme.primaryColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(12)
        }
        .frame(width: 240)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 13. RatingView

@available(iOS 14.0, *)
public struct RatingView: View {
    let state: RatingState
    let onRate: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedRating: Int?

    public init(state: RatingState, onRate: @escaping (Any) -> Void) {
        self.state = state
        self.onRate = onRate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            HStack(spacing: 8) {
                Spacer()
                switch state.ratingType {
                case .star:
                    ForEach(state.minValue...state.maxValue, id: \.self) { value in
                        Button(action: { selectRating(value) }) {
                            Image(systemName: (selectedRating ?? 0) >= value ? "star.fill" : "star")
                                .font(.title)
                                .foregroundColor((selectedRating ?? 0) >= value ? .yellow : .gray)
                        }
                        .disabled(selectedRating != nil)
                    }

                case .hearts:
                    ForEach(state.minValue...state.maxValue, id: \.self) { value in
                        Button(action: { selectRating(value) }) {
                            Image(systemName: (selectedRating ?? 0) >= value ? "heart.fill" : "heart")
                                .font(.title)
                                .foregroundColor((selectedRating ?? 0) >= value ? .red : .gray)
                        }
                        .disabled(selectedRating != nil)
                    }

                case .thumbs:
                    Button(action: { selectRating(0) }) {
                        Image(systemName: selectedRating == 0 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.largeTitle)
                            .foregroundColor(selectedRating == 0 ? .red : .gray)
                    }
                    .disabled(selectedRating != nil)

                    Button(action: { selectRating(1) }) {
                        Image(systemName: selectedRating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.largeTitle)
                            .foregroundColor(selectedRating == 1 ? .green : .gray)
                    }
                    .disabled(selectedRating != nil)

                case .smiley:
                    let emojis = ["Very Dissatisfied": "face.smiling", "Dissatisfied": "face.smiling", "Neutral": "face.smiling", "Satisfied": "face.smiling", "Very Satisfied": "face.smiling"]
                    let emojiStrings = ["1": ":(", "2": ":|", "3": ":)", "4": ":D", "5": ":D"]

                    ForEach(state.minValue...state.maxValue, id: \.self) { value in
                        Button(action: { selectRating(value) }) {
                            Text(smileyForValue(value, max: state.maxValue))
                                .font(.title)
                                .opacity(selectedRating == nil || selectedRating == value ? 1 : 0.4)
                        }
                        .disabled(selectedRating != nil)
                    }

                case .number:
                    ForEach(state.minValue...state.maxValue, id: \.self) { value in
                        Button(action: { selectRating(value) }) {
                            Text("\(value)")
                                .font(.headline)
                                .frame(width: 40, height: 40)
                                .background(
                                    selectedRating == value
                                        ? theme.primaryColor
                                        : Color(UIColor.systemGray5)
                                )
                                .foregroundColor(selectedRating == value ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .disabled(selectedRating != nil)
                    }
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: selectedRating)
        }
    }

    private func selectRating(_ value: Int) {
        selectedRating = value
        onRate(value)
    }

    private func smileyForValue(_ value: Int, max: Int) -> String {
        let normalized = Double(value - 1) / Double(max - 1)
        if normalized < 0.2 { return ":((" }
        if normalized < 0.4 { return ":(" }
        if normalized < 0.6 { return ":|" }
        if normalized < 0.8 { return ":)" }
        return ":D"
    }
}

// MARK: - 14. OpinionScaleView

@available(iOS 14.0, *)
public struct OpinionScaleView: View {
    let state: OpinionScaleState
    let onSelect: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedValue: Int?

    public init(state: OpinionScaleState, onSelect: @escaping (Any) -> Void) {
        self.state = state
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(state.minValue...state.maxValue, id: \.self) { value in
                        Button(action: {
                            guard selectedValue == nil else { return }
                            selectedValue = value
                            onSelect(value)
                        }) {
                            Text("\(value)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    selectedValue == value
                                        ? theme.primaryColor
                                        : Color(UIColor.systemGray5)
                                )
                                .foregroundColor(selectedValue == value ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .disabled(selectedValue != nil)
                    }
                }

                HStack {
                    if let minLabel = state.minLabel {
                        Text(minLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let maxLabel = state.maxLabel {
                        Text(maxLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedValue)
        }
    }
}

// MARK: - 15. CalendarPicker

@available(iOS 14.0, *)
public struct CalendarPicker: View {
    let state: CalendarState
    let onSelect: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var isSubmitted = false

    public init(state: CalendarState, onSelect: @escaping (Any) -> Void) {
        self.state = state
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            VStack(spacing: 16) {
                switch state.mode {
                case .date:
                    DatePicker(
                        "Select Date",
                        selection: $selectedDate,
                        in: dateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .disabled(isSubmitted)

                case .time:
                    DatePicker(
                        "Select Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(WheelDatePickerStyle())
                    .disabled(isSubmitted)

                case .dateTime:
                    DatePicker(
                        "Select Date & Time",
                        selection: $selectedDate,
                        in: dateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .disabled(isSubmitted)

                case .slot:
                    if let slots = state.availableSlots {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(slots.filter { $0.available }) { slot in
                                    Button(action: {
                                        guard !isSubmitted else { return }
                                        isSubmitted = true
                                        let formatter = DateFormatter()
                                        formatter.dateFormat = "yyyy-MM-dd"
                                        onSelect([
                                            "date": formatter.string(from: slot.date),
                                            "time": slot.time ?? ""
                                        ])
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(slot.date, style: .date)
                                                    .font(.headline)
                                                if let time = slot.time {
                                                    Text(time)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(12)
                                        .background(Color(UIColor.systemGray6))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }

                if state.mode != .slot {
                    Button(action: submitDate) {
                        Text("Confirm")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSubmitted ? Color.gray : theme.primaryColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(isSubmitted)
                }
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
        }
    }

    private var dateRange: ClosedRange<Date> {
        let min = state.minDate ?? Date()
        let max = state.maxDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        return min...max
    }

    private func submitDate() {
        isSubmitted = true
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var result: [String: String] = ["date": dateFormatter.string(from: selectedDate)]

        if state.showTimeSelection || state.mode == .time || state.mode == .dateTime {
            result["time"] = timeFormatter.string(from: state.mode == .time ? selectedTime : selectedDate)
        }

        onSelect(result)
    }
}

// MARK: - 16. FileUploadView

@available(iOS 14.0, *)
public struct FileUploadView: View {
    let state: FileUploadState
    let onUpload: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var showPicker = false
    @State private var uploadedFileName: String?

    public init(state: FileUploadState, onUpload: @escaping (Any) -> Void) {
        self.state = state
        self.onUpload = onUpload
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.questionText.isEmpty {
                MessageBubbleNode(text: state.questionText)
            }

            Button(action: { showPicker = true }) {
                VStack(spacing: 12) {
                    if let fileName = uploadedFileName {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text(fileName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 40))
                            .foregroundColor(theme.primaryColor)
                        Text("Tap to upload")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Max \(state.maxSizeMb)MB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                        .foregroundColor(theme.primaryColor.opacity(0.5))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(uploadedFileName != nil)
            .sheet(isPresented: $showPicker) {
                DocumentPickerView(
                    allowedTypes: state.allowedTypes,
                    onPick: { url in
                        uploadedFileName = url.lastPathComponent
                        onUpload(["url": url.absoluteString, "name": url.lastPathComponent])
                    }
                )
            }
        }
    }
}

@available(iOS 14.0, *)
private struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedTypes: [String]?
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType]
        if let allowed = allowedTypes {
            types = allowed.compactMap { UTType(filenameExtension: $0) }
        } else {
            types = [.item]
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}

// MARK: - 17. LiveChatView

@available(iOS 14.0, *)
public struct LiveChatView: View {
    let state: LiveChatState

    @Environment(\.chatTheme) private var theme

    public init(state: LiveChatState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch state.status {
            case .connecting, .waiting:
                ProgressView()
                    .scaleEffect(1.5)

                Text(state.status == .connecting ? "Connecting..." : "Waiting for agent...")
                    .font(.headline)

                if let position = state.position {
                    Text("You are #\(position) in queue")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let waitTime = state.waitTime {
                    Text("Estimated wait: \(waitTime) minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .connected:
                HStack(spacing: 12) {
                    if let avatar = state.agentAvatar, let avatarURL = URL(string: avatar) {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable()
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading) {
                        Text(state.agentName ?? "Agent")
                            .font(.headline)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(12)

            case .ended:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("Chat ended")
                    .font(.headline)

            case .unavailable:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                Text("No agents available")
                    .font(.headline)
                Text("Please try again later")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 18. LinkView

@available(iOS 14.0, *)
public struct LinkView: View {
    let state: LinkState

    public init(state: LinkState) {
        self.state = state
    }

    public var body: some View {
        Button(action: openLink) {
            HStack(spacing: 12) {
                if let imageUrl = state.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Color(UIColor.systemGray5)
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                } else {
                    Image(systemName: "link")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 60, height: 60)
                        .background(Color(UIColor.systemGray5))
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title ?? state.url)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let description = state.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Text(extractDomain(from: state.url))
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 300)
    }

    private func openLink() {
        if let url = URL(string: state.url) {
            UIApplication.shared.open(url)
        }
    }

    private func extractDomain(from urlString: String) -> String {
        if let url = URL(string: urlString), let host = url.host {
            return host
        }
        return urlString
    }
}

// MARK: - 19. EmbedView

@available(iOS 14.0, *)
public struct EmbedView: View {
    let state: EmbedState

    public init(state: EmbedState) {
        self.state = state
    }

    public var body: some View {
        WebViewWrapper(urlString: state.embedUrl)
            .frame(height: state.height)
            .cornerRadius(12)
    }
}

@available(iOS 14.0, *)
private struct WebViewWrapper: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - 20. LoadingView (Typing Indicator)

@available(iOS 14.0, *)
public struct LoadingView: View {
    public init() {}

    public var body: some View {
        HStack {
            TypingIndicatorView()
            Spacer()
        }
    }
}

@available(iOS 14.0, *)
public struct TypingIndicatorView: View {
    @State private var animating = false

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .opacity(animating ? 0.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(12)
        .background(Color(UIColor.systemGray5))
        .cornerRadius(16)
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Additional Components

@available(iOS 14.0, *)
public struct DropdownView: View {
    let state: DropdownState
    let onSelect: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedOption: DropdownState.Option?
    @State private var isExpanded = false

    public init(state: DropdownState, onSelect: @escaping (Any) -> Void) {
        self.state = state
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            Menu {
                ForEach(state.options) { option in
                    Button(option.text) {
                        selectedOption = option
                        onSelect(["id": option.id, "text": option.text])
                    }
                }
            } label: {
                HStack {
                    Text(selectedOption?.text ?? "Select an option")
                        .foregroundColor(selectedOption == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
            }
            .disabled(selectedOption != nil)
        }
    }
}

@available(iOS 14.0, *)
public struct RangeView: View {
    let state: RangeState
    let onSubmit: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var value: Double
    @State private var isSubmitted = false

    public init(state: RangeState, onSubmit: @escaping (Any) -> Void) {
        self.state = state
        self.onSubmit = onSubmit
        let defaultVal = state.defaultValue ?? ((state.minValue + state.maxValue) / 2)
        _value = State(initialValue: Double(defaultVal))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("\(state.minValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(
                        value: $value,
                        in: Double(state.minValue)...Double(state.maxValue),
                        step: Double(state.step)
                    )
                    .disabled(isSubmitted)
                    .accentColor(theme.primaryColor)

                    Text("\(state.maxValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Selected: \(Int(value))")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }

            Button(action: {
                isSubmitted = true
                onSubmit(Int(value))
            }) {
                Text("Submit")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isSubmitted ? Color.gray : theme.primaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isSubmitted)
        }
    }
}

@available(iOS 14.0, *)
public struct QuizView: View {
    let state: QuizState
    let onAnswer: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedIndex: Int?

    public init(state: QuizState, onAnswer: @escaping (Any) -> Void) {
        self.state = state
        self.onAnswer = onAnswer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MessageBubbleNode(text: state.questionText)

            VStack(spacing: 8) {
                ForEach(Array(state.options.enumerated()), id: \.offset) { index, option in
                    Button(action: {
                        guard selectedIndex == nil else { return }
                        selectedIndex = index
                        onAnswer(["index": index, "text": option, "correct": index == state.correctAnswerIndex])
                    }) {
                        HStack {
                            Text(option)
                            Spacer()
                            if selectedIndex == index {
                                Image(systemName: index == state.correctAnswerIndex ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(index == state.correctAnswerIndex ? .green : .red)
                            }
                        }
                        .padding(14)
                        .background(backgroundColor(for: index))
                        .foregroundColor(foregroundColor(for: index))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    selectedIndex == nil ? theme.primaryColor : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedIndex != nil)
                }
            }
        }
    }

    private func backgroundColor(for index: Int) -> Color {
        guard let selected = selectedIndex else {
            return Color(UIColor.systemGray6)
        }
        if index == selected {
            return index == state.correctAnswerIndex ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
        }
        if index == state.correctAnswerIndex && selected != index {
            return Color.green.opacity(0.1)
        }
        return Color(UIColor.systemGray6)
    }

    private func foregroundColor(for index: Int) -> Color {
        return .primary
    }
}

@available(iOS 14.0, *)
public struct MultipleQuestionsView: View {
    let state: MultipleQuestionsState
    let onSubmit: (Any) -> Void

    @Environment(\.chatTheme) private var theme

    public init(state: MultipleQuestionsState, onSubmit: @escaping (Any) -> Void) {
        self.state = state
        self.onSubmit = onSubmit
    }

    public var body: some View {
        if state.currentIndex < state.questions.count {
            let question = state.questions[state.currentIndex]

            TextInputView(
                state: TextInputState(
                    questionText: question.questionText,
                    inputType: inputType(for: question.answerType),
                    nodeId: state.nodeId,
                    answerKey: question.answerKey
                ),
                onSubmit: onSubmit
            )
        }
    }

    private func inputType(for answerType: String) -> TextInputState.InputType {
        switch answerType.lowercased() {
        case "email": return .email
        case "phone", "mobile": return .phone
        case "name": return .name
        case "number": return .number
        case "url": return .url
        default: return .text
        }
    }
}

@available(iOS 14.0, *)
public struct HumanHandoverView: View {
    let state: HumanHandoverState
    let onResponse: (Any) -> Void

    @Environment(\.chatTheme) private var theme

    public init(state: HumanHandoverState, onResponse: @escaping (Any) -> Void) {
        self.state = state
        self.onResponse = onResponse
    }

    public var body: some View {
        switch state.state {
        case .preChatQuestions, .postChatSurvey:
            if let questions = state.preChatQuestions,
               state.currentQuestionIndex < questions.count {
                let question = questions[state.currentQuestionIndex]

                TextInputView(
                    state: TextInputState(
                        questionText: question.questionText,
                        inputType: inputType(for: question.answerType),
                        nodeId: state.nodeId,
                        answerKey: question.answerKey
                    ),
                    onSubmit: onResponse
                )
            }

        case .waitingForAgent:
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(state.handoverMessage ?? "Connecting you to an agent...")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let waitTime = state.maxWaitTime {
                    Text("Estimated wait: \(waitTime) minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)

        case .agentConnected:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)

                Text("\(state.agentName ?? "Agent") has joined the chat")
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

        case .noAgentsAvailable:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)

                Text(state.handoverMessage ?? "No agents available")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func inputType(for answerType: String) -> TextInputState.InputType {
        switch answerType.lowercased() {
        case "email": return .email
        case "phone", "mobile": return .phone
        case "name": return .name
        default: return .text
        }
    }
}

@available(iOS 14.0, *)
public struct HtmlView: View {
    let htmlContent: String

    public init(htmlContent: String) {
        self.htmlContent = htmlContent
    }

    public var body: some View {
        HTMLWebView(htmlContent: htmlContent)
            .frame(minHeight: 100)
            .cornerRadius(12)
    }
}

@available(iOS 14.0, *)
private struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                    margin: 0;
                    padding: 12px;
                    color: #000;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #fff; }
                }
            </style>
        </head>
        <body>\(htmlContent)</body>
        </html>
        """
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }
}

@available(iOS 14.0, *)
public struct PaymentView: View {
    let state: PaymentState

    @Environment(\.chatTheme) private var theme

    public init(state: PaymentState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "635BFF"))

            Text("Payment")
                .font(.headline)

            if let amount = state.amount, let currency = state.currency {
                Text("\(currency) \(String(format: "%.2f", amount))")
                    .font(.title)
                    .fontWeight(.bold)
            }

            if let description = state.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: openPayment) {
                Text("Pay Now")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "635BFF"))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(24)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    private func openPayment() {
        if let url = URL(string: state.paymentUrl) {
            UIApplication.shared.open(url)
        }
    }
}

@available(iOS 14.0, *)
public struct RedirectView: View {
    let url: String

    public init(url: String) {
        self.url = url
    }

    public var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Redirecting...")
                .font(.subheadline)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .onAppear {
            if let redirectURL = URL(string: url) {
                UIApplication.shared.open(redirectURL)
            }
        }
    }
}

@available(iOS 14.0, *)
public struct ImageChoiceView: View {
    let state: ImageChoiceState
    let onSelect: (Any) -> Void

    @Environment(\.chatTheme) private var theme
    @State private var selectedId: String?

    public init(state: ImageChoiceState, onSelect: @escaping (Any) -> Void) {
        self.state = state
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionText = state.questionText, !questionText.isEmpty {
                MessageBubbleNode(text: questionText)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(state.images) { image in
                    Button(action: {
                        guard selectedId == nil else { return }
                        selectedId = image.id
                        onSelect([
                            "id": image.id,
                            "label": image.label,
                            "imageUrl": image.imageUrl,
                            "targetPort": image.targetPort as Any
                        ])
                    }) {
                        VStack(spacing: 0) {
                            AsyncImage(url: URL(string: image.imageUrl)) { phase in
                                switch phase {
                                case .success(let loadedImage):
                                    loadedImage
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure, .empty:
                                    Color(UIColor.systemGray5)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(height: 100)
                            .clipped()

                            Text(image.label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selectedId == image.id
                                        ? theme.primaryColor
                                        : Color(UIColor.systemGray6)
                                )
                                .foregroundColor(selectedId == image.id ? .white : .primary)
                        }
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    selectedId == image.id ? theme.primaryColor : Color.clear,
                                    lineWidth: 3
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedId != nil)
                    .opacity(selectedId != nil && selectedId != image.id ? 0.5 : 1)
                }
            }
        }
    }
}

// MARK: - Color Extension

@available(iOS 14.0, *)
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview Provider

@available(iOS 14.0, *)
struct NodeComponents_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Message
                NodeRenderer(
                    uiState: .message(text: "Hello! How can I help you today?", nodeId: "1"),
                    onInput: { _ in }
                )

                // Single Choice
                NodeRenderer(
                    uiState: .singleChoice(SingleChoiceState(
                        questionText: "What would you like to do?",
                        choices: [
                            .init(id: "1", text: "Get support"),
                            .init(id: "2", text: "Make a purchase"),
                            .init(id: "3", text: "Learn more")
                        ],
                        nodeId: "2",
                        answerKey: "action"
                    )),
                    onInput: { _ in }
                )

                // Rating
                NodeRenderer(
                    uiState: .rating(RatingState(
                        questionText: "How would you rate our service?",
                        ratingType: .star,
                        nodeId: "3",
                        answerKey: "rating"
                    )),
                    onInput: { _ in }
                )

                // Text Input
                NodeRenderer(
                    uiState: .textInput(TextInputState(
                        questionText: "What's your email?",
                        inputType: .email,
                        placeholder: "Enter your email",
                        nodeId: "4",
                        answerKey: "email"
                    )),
                    onInput: { _ in }
                )
            }
            .padding()
        }
        .environment(\.chatTheme, ChatTheme.default)
    }
}

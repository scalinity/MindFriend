import Foundation

/// API endpoint definitions
enum APIEndpoint {
    // Auth
    case appleSignIn(AppleSignInRequest)
    case googleSignIn(GoogleSignInRequest)
    case refreshToken(RefreshTokenRequest)
    case logout

    // User
    case getProfile
    case updateProfile(displayName: String?, timezone: String?)
    case updateSettings(UserSettings)
    case registerDevice(apnsToken: String, deviceModel: String, osVersion: String)
    case deleteAccount
    case exportData

    // Quests
    case getTodayQuest
    case completeQuest(id: String, reflectionNote: String?, rating: Int?)
    case skipQuest(id: String)

    // Moods
    case createMood(MoodEntry)
    case getMoods(from: String, to: String)

    // Chat
    case createConversation(title: String?)
    case getConversations
    case getMessages(conversationId: String, limit: Int)
    case sendMessage(conversationId: String, content: String)

    // Circles
    case getCircles
    case createCircle(name: String, description: String?)
    case joinCircle(inviteCode: String)
    case getCircle(id: String)
    case getCircleFeed(id: String, from: String, to: String)
    case postCheckin(circleId: String, moodEmoji: String, bodyText: String?)
    case leaveCircle(id: String)

    // Exercises
    case getExercises(type: ExerciseType?)
    case startExercise(id: String)
    case completeExerciseSession(sessionId: String, rating: Int?, note: String?)

    // Billing
    case submitAppleTransaction(signedTransaction: String)
    case getEntitlements

    // Resources
    case getCrisisResources(country: String?)

    // MARK: - Properties

    var path: String {
        switch self {
        // Auth
        case .appleSignIn: return "/v1/auth/apple"
        case .googleSignIn: return "/v1/auth/google"
        case .refreshToken: return "/v1/auth/refresh"
        case .logout: return "/v1/auth/logout"

        // User
        case .getProfile: return "/v1/me"
        case .updateProfile: return "/v1/me"
        case .updateSettings: return "/v1/me/settings"
        case .registerDevice: return "/v1/devices/register"
        case .deleteAccount: return "/v1/me/delete"
        case .exportData: return "/v1/me/export"

        // Quests
        case .getTodayQuest: return "/v1/quests/today"
        case .completeQuest(let id, _, _): return "/v1/quests/\(id)/complete"
        case .skipQuest(let id): return "/v1/quests/\(id)/skip"

        // Moods
        case .createMood: return "/v1/moods"
        case .getMoods: return "/v1/moods"

        // Chat
        case .createConversation: return "/v1/chat/conversations"
        case .getConversations: return "/v1/chat/conversations"
        case .getMessages(let id, _): return "/v1/chat/conversations/\(id)/messages"
        case .sendMessage(let id, _): return "/v1/chat/conversations/\(id)/messages"

        // Circles
        case .getCircles: return "/v1/circles"
        case .createCircle: return "/v1/circles"
        case .joinCircle: return "/v1/circles/join"
        case .getCircle(let id): return "/v1/circles/\(id)"
        case .getCircleFeed(let id, _, _): return "/v1/circles/\(id)/feed"
        case .postCheckin(let id, _, _): return "/v1/circles/\(id)/checkin"
        case .leaveCircle(let id): return "/v1/circles/\(id)/leave"

        // Exercises
        case .getExercises: return "/v1/exercises"
        case .startExercise(let id): return "/v1/exercises/\(id)/start"
        case .completeExerciseSession(let id, _, _): return "/v1/exercises/sessions/\(id)/complete"

        // Billing
        case .submitAppleTransaction: return "/v1/billing/apple/transaction"
        case .getEntitlements: return "/v1/billing/entitlements"

        // Resources
        case .getCrisisResources: return "/v1/resources/crisis"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .appleSignIn, .googleSignIn, .refreshToken, .logout,
             .registerDevice, .deleteAccount, .exportData,
             .completeQuest, .skipQuest,
             .createMood,
             .createConversation, .sendMessage,
             .createCircle, .joinCircle, .postCheckin, .leaveCircle,
             .startExercise, .completeExerciseSession,
             .submitAppleTransaction:
            return .post

        case .updateProfile, .updateSettings:
            return .patch

        default:
            return .get
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .appleSignIn, .googleSignIn, .refreshToken, .getCrisisResources:
            return false
        default:
            return true
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .getMoods(let from, let to):
            return [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to)
            ]
        case .getMessages(_, let limit):
            return [URLQueryItem(name: "limit", value: String(limit))]
        case .getCircleFeed(_, let from, let to):
            return [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to)
            ]
        case .getExercises(let type):
            if let type = type {
                return [URLQueryItem(name: "type", value: type.rawValue)]
            }
            return nil
        case .getCrisisResources(let country):
            if let country = country {
                return [URLQueryItem(name: "country", value: country)]
            }
            return nil
        default:
            return nil
        }
    }

    var body: Encodable? {
        switch self {
        case .appleSignIn(let request):
            return request
        case .googleSignIn(let request):
            return request
        case .refreshToken(let request):
            return request
        case .updateProfile(let displayName, let timezone):
            return UpdateProfileRequest(displayName: displayName, timezone: timezone)
        case .updateSettings(let settings):
            return settings
        case .registerDevice(let apnsToken, let deviceModel, let osVersion):
            return RegisterDeviceRequest(apnsToken: apnsToken, deviceModel: deviceModel, osVersion: osVersion)
        case .completeQuest(_, let reflectionNote, let rating):
            return CompleteQuestRequest(reflectionNote: reflectionNote, rating: rating)
        case .createMood(let mood):
            return CreateMoodRequest(
                localDate: mood.localDate,
                moodScore: mood.moodScore,
                anxietyScore: mood.anxietyScore,
                energyScore: mood.energyScore,
                note: mood.note
            )
        case .createConversation(let title):
            return CreateConversationRequest(title: title)
        case .sendMessage(_, let content):
            return SendMessageRequest(content: content)
        case .createCircle(let name, let description):
            return CreateCircleRequest(name: name, description: description)
        case .joinCircle(let inviteCode):
            return JoinCircleRequest(inviteCode: inviteCode)
        case .postCheckin(_, let moodEmoji, let bodyText):
            return PostCheckinRequest(moodEmoji: moodEmoji, bodyText: bodyText)
        case .completeExerciseSession(_, let rating, let note):
            return CompleteSessionRequest(rating: rating, note: note)
        case .submitAppleTransaction(let signedTransaction):
            return SubmitTransactionRequest(signedTransaction: signedTransaction)
        default:
            return nil
        }
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - Request Bodies

struct UpdateProfileRequest: Encodable {
    let displayName: String?
    let timezone: String?
}

struct RegisterDeviceRequest: Encodable {
    let apnsToken: String
    let deviceModel: String
    let osVersion: String
}

struct CompleteQuestRequest: Encodable {
    let reflectionNote: String?
    let rating: Int?
}

struct CreateMoodRequest: Encodable {
    let localDate: String
    let moodScore: Int
    let anxietyScore: Int?
    let energyScore: Int?
    let note: String?
}

struct CreateConversationRequest: Encodable {
    let title: String?
}

struct SendMessageRequest: Encodable {
    let content: String
}

struct CreateCircleRequest: Encodable {
    let name: String
    let description: String?
}

struct JoinCircleRequest: Encodable {
    let inviteCode: String
}

struct PostCheckinRequest: Encodable {
    let moodEmoji: String
    let bodyText: String?
}

struct CompleteSessionRequest: Encodable {
    let rating: Int?
    let note: String?
}

struct SubmitTransactionRequest: Encodable {
    let signedTransaction: String
}

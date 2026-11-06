import Foundation

// MARK: - Type Aliases

/// Type alias for contact relationship used in safety plan views
typealias TrustedContactRelationship = ContactRelationship

// MARK: - Safety Plan Models

/// A single item in a safety plan (warning sign, coping strategy, etc.)
struct SafetyPlanItem: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let order: Int
    let isCustom: Bool

    init(id: String = UUID().uuidString, text: String, order: Int = 0, isCustom: Bool = false) {
        self.id = id
        self.text = text
        self.order = order
        self.isCustom = isCustom
    }
}

/// Type of coping strategy
enum CopingStrategyType: String, Codable, CaseIterable, Identifiable {
    case breathing = "breathing"
    case exercise = "exercise"
    case grounding = "grounding"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .exercise: return "Exercise"
        case .grounding: return "Grounding"
        case .custom: return "Custom"
        }
    }
}

/// Category of coping strategy
enum CopingCategory: String, Codable, CaseIterable, Identifiable {
    case breathing = "breathing"
    case movement = "movement"
    case sensory = "sensory"
    case mindfulness = "mindfulness"
    case meditation = "meditation"
    case grounding = "grounding"
    case journaling = "journaling"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .movement: return "Movement"
        case .sensory: return "Sensory"
        case .mindfulness: return "Mindfulness"
        case .meditation: return "Meditation"
        case .grounding: return "Grounding"
        case .journaling: return "Journaling"
        }
    }

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .movement: return "figure.walk"
        case .sensory: return "hand.raised"
        case .mindfulness: return "brain.head.profile"
        case .meditation: return "sparkles"
        case .grounding: return "leaf"
        case .journaling: return "pencil.line"
        }
    }
}

/// A coping strategy in the safety plan
struct CopingStrategy: Identifiable, Codable, Equatable {
    let id: String
    let type: CopingStrategyType
    let label: String
    let duration: Int?  // Duration in minutes
    let category: CopingCategory
    let isFavorite: Bool
    let exerciseId: String?

    init(
        id: String = UUID().uuidString,
        type: CopingStrategyType,
        label: String,
        duration: Int? = nil,
        category: CopingCategory,
        isFavorite: Bool = false,
        exerciseId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.duration = duration
        self.category = category
        self.isFavorite = isFavorite
        self.exerciseId = exerciseId
    }

    /// Creates a custom coping strategy
    static func custom(label: String, category: CopingCategory) -> CopingStrategy {
        CopingStrategy(
            type: .custom,
            label: label,
            category: category
        )
    }
}

/// Relationship type for trusted contacts
enum ContactRelationship: String, Codable, CaseIterable, Identifiable {
    case family = "family"
    case friend = "friend"
    case partner = "partner"
    case therapist = "therapist"
    case doctor = "doctor"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .family: return "Family"
        case .friend: return "Friend"
        case .partner: return "Partner/Spouse"
        case .therapist: return "Therapist"
        case .doctor: return "Doctor"
        case .other: return "Other"
        }
    }
}

/// Preferred contact method
enum ContactMethod: String, Codable, CaseIterable, Identifiable {
    case call = "call"
    case text = "text"
    case inPerson = "in_person"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .call: return "Call"
        case .text: return "Text"
        case .inPerson: return "In Person"
        }
    }

    var icon: String {
        switch self {
        case .call: return "phone.fill"
        case .text: return "message.fill"
        case .inPerson: return "person.fill"
        }
    }
}

/// A trusted contact in the safety plan
struct TrustedContact: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let phone: String
    let relationship: ContactRelationship
    let preferredMethod: ContactMethod
    let isPrimary: Bool
    let notes: String?
    let whatToSay: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        phone: String,
        relationship: ContactRelationship,
        preferredMethod: ContactMethod = .call,
        isPrimary: Bool = false,
        notes: String? = nil,
        whatToSay: String? = nil
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.relationship = relationship
        self.preferredMethod = preferredMethod
        self.isPrimary = isPrimary
        self.notes = notes
        self.whatToSay = whatToSay
    }

    /// Phone number formatted for display
    var formattedPhone: String {
        // Return as-is if already in international format
        if phone.hasPrefix("+") { return phone }
        // Simple formatting: add dashes for 10-digit numbers
        let digits = phone.filter { $0.isNumber }
        guard digits.count == 10 else { return phone }
        let start = digits.index(digits.startIndex, offsetBy: 3)
        let middle = digits.index(start, offsetBy: 3)
        return "\(digits[..<start])-\(digits[start..<middle])-\(digits[middle...])"
    }

    /// Whether the phone number is valid (10+ digits or international format)
    var isValidPhone: Bool {
        let digits = phone.filter { $0.isNumber }
        // Valid if: international format with 10+ digits, or exactly 10 digits
        if phone.hasPrefix("+") {
            return digits.count >= 10
        }
        return digits.count == 10
    }
}

/// Type of professional resource
enum ResourceType: String, Codable, CaseIterable, Identifiable {
    case hotline = "hotline"
    case emergency = "emergency"
    case crisis = "crisis"
    case crisisLine = "crisis_line"
    case warmLine = "warm_line"
    case professional = "professional"
    case therapist = "therapist"
    case custom = "custom"
    case crisisHyphenLine = "crisis-line"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotline: return "Helpline"
        case .emergency: return "Emergency Services"
        case .crisis: return "Crisis Line"
        case .crisisLine: return "Crisis Text Line"
        case .therapist: return "Therapist"
        case .warmLine: return "Warm Line"
        case .professional: return "Professional"
        case .custom: return "Custom"
        case .crisisHyphenLine: return "Crisis Text Line"
        }
    }
}

/// A professional resource in the safety plan
struct ProfessionalResource: Identifiable, Codable, Equatable {
    let id: String
    let type: ResourceType
    let name: String
    let phone: String
    let country: String
    let description: String?
    let website: String?

    init(
        id: String = UUID().uuidString,
        type: ResourceType,
        name: String,
        phone: String,
        country: String = "US",
        description: String? = nil,
        website: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.phone = phone
        self.country = country
        self.description = description
        self.website = website
    }
}

/// The main safety plan payload containing all plan data
struct SafetyPlanPayload: Codable, Equatable {
    let id: String
    let userId: String
    let version: Int
    var warningSigns: [SafetyPlanItem]
    var coping: [CopingStrategy]
    var contacts: [TrustedContact]
    var resources: [ProfessionalResource]
    var environmentSteps: [SafetyPlanItem]
    var anchors: [SafetyPlanItem]  // Reasons to live / anchors
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String = UUID().uuidString,
        version: Int = 1,
        warningSigns: [SafetyPlanItem] = [],
        coping: [CopingStrategy] = [],
        contacts: [TrustedContact] = [],
        resources: [ProfessionalResource] = [],
        environmentSteps: [SafetyPlanItem] = [],
        anchors: [SafetyPlanItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.version = version
        self.warningSigns = warningSigns
        self.coping = coping
        self.contacts = contacts
        self.resources = resources
        self.environmentSteps = environmentSteps
        self.anchors = anchors
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // The handler stores content separately from the row's identity and timestamps.
    // Older local caches include these metadata fields inside the payload.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        userId = try values.decodeIfPresent(String.self, forKey: .userId) ?? ""
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        warningSigns = try values.decode([SafetyPlanItem].self, forKey: .warningSigns)
        coping = try values.decode([CopingStrategy].self, forKey: .coping)
        contacts = try values.decode([TrustedContact].self, forKey: .contacts)
        resources = try values.decode([ProfessionalResource].self, forKey: .resources)
        environmentSteps = try values.decode([SafetyPlanItem].self, forKey: .environmentSteps)
        anchors = try values.decode([SafetyPlanItem].self, forKey: .anchors)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    static let empty = SafetyPlanPayload()
}

/// Safety plan settings
struct SafetyPlanSettings: Codable, Equatable {
    var allowAiReference: Bool
    var pinnedToQuickActions: Bool

    init(
        allowAiReference: Bool = true,
        pinnedToQuickActions: Bool = false
    ) {
        self.allowAiReference = allowAiReference
        self.pinnedToQuickActions = pinnedToQuickActions
    }

    enum CodingKeys: String, CodingKey {
        case allowAiReference = "allow_ai_reference"
        case pinnedToQuickActions = "pinned_to_quick_actions"
        case legacyAllowAiReference = "allowAiReference"
        case legacyPinnedToQuickActions = "pinnedToQuickActions"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        allowAiReference = try values.decodeIfPresent(Bool.self, forKey: .allowAiReference)
            ?? values.decodeIfPresent(Bool.self, forKey: .legacyAllowAiReference) ?? false
        pinnedToQuickActions = try values.decodeIfPresent(Bool.self, forKey: .pinnedToQuickActions)
            ?? values.decodeIfPresent(Bool.self, forKey: .legacyPinnedToQuickActions) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(allowAiReference, forKey: .allowAiReference)
        try values.encode(pinnedToQuickActions, forKey: .pinnedToQuickActions)
    }

    static let `default` = SafetyPlanSettings()
}

/// Cache payload for offline storage
struct SafetyPlanCachePayload: Codable {
    let payload: SafetyPlanPayload
    let settings: SafetyPlanSettings
    let version: Int
    let cachedAt: Date
    let expiresAt: Date

    init(
        payload: SafetyPlanPayload,
        settings: SafetyPlanSettings,
        version: Int = 1,
        cachedAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(86400) // 24 hours default
    ) {
        self.payload = payload
        self.settings = settings
        self.version = version
        self.cachedAt = cachedAt
        self.expiresAt = expiresAt
    }

    /// Whether the cache has expired
    var isExpired: Bool {
        Date() > expiresAt
    }
}

/// API response for safety plan operations
struct SafetyPlanResponse: Codable {
    let success: Bool
    let data: SafetyPlanData?
    let error: String?

    private enum CodingKeys: String, CodingKey { case success, data, error }
    private struct ServerError: Decodable { let message: String }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        success = try values.decode(Bool.self, forKey: .success)
        data = try values.decodeIfPresent(SafetyPlanData.self, forKey: .data)
        if let message = try? values.decode(String.self, forKey: .error) {
            error = message
        } else {
            error = try values.decodeIfPresent(ServerError.self, forKey: .error)?.message
        }
    }
}

/// Inner data for safety plan response
struct SafetyPlanData: Codable {
    let payload: SafetyPlanPayload
    let settings: SafetyPlanSettings
    let version: Int
}

/// Operation type for safety plan
enum SafetyPlanOperation: String, Codable {
    case create
    case update
    case delete
}

/// Content-only request: row metadata and local quick-action preferences stay local.
struct SafetyPlanRequest: Encodable {
    let operation: String
    let payload: Content?
    let settings: Settings?

    struct Content: Encodable {
        let warningSigns: [SafetyPlanItem]
        let coping: [CopingStrategy]
        let contacts: [TrustedContact]
        let resources: [ProfessionalResource]
        let environmentSteps: [SafetyPlanItem]
        let anchors: [SafetyPlanItem]

        init(_ payload: SafetyPlanPayload) {
            warningSigns = payload.warningSigns
            coping = payload.coping
            contacts = payload.contacts
            resources = payload.resources
            environmentSteps = payload.environmentSteps
            anchors = payload.anchors
        }
    }

    struct Settings: Encodable {
        let allow_ai_reference: Bool
    }
}

// The handler accepts older plans without the optional presentation fields.
extension SafetyPlanItem {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
        isCustom = try values.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

extension CopingStrategy {
    private enum LegacyKeys: String, CodingKey {
        case exerciseId = "exercise_id", isFavorite = "is_favorite"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decode(CopingStrategyType.self, forKey: .type)
        label = try values.decode(String.self, forKey: .label)
        duration = try values.decodeIfPresent(Int.self, forKey: .duration)
        category = try values.decode(CopingCategory.self, forKey: .category)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        exerciseId = try values.decodeIfPresent(String.self, forKey: .exerciseId)
            ?? legacy.decodeIfPresent(String.self, forKey: .exerciseId)
    }
}

extension TrustedContact {
    private enum LegacyKeys: String, CodingKey {
        case preferredMethod = "preferred_method", isPrimary = "is_primary", whatToSay = "what_to_say"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        phone = try values.decode(String.self, forKey: .phone)
        relationship = try values.decode(ContactRelationship.self, forKey: .relationship)
        preferredMethod = try values.decodeIfPresent(ContactMethod.self, forKey: .preferredMethod)
            ?? legacy.decodeIfPresent(ContactMethod.self, forKey: .preferredMethod) ?? .call
        isPrimary = try values.decodeIfPresent(Bool.self, forKey: .isPrimary)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        whatToSay = try values.decodeIfPresent(String.self, forKey: .whatToSay)
            ?? legacy.decodeIfPresent(String.self, forKey: .whatToSay)
    }
}

extension ProfessionalResource {
    private enum LegacyKeys: String, CodingKey { case url, notes }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decode(ResourceType.self, forKey: .type)
        name = try values.decode(String.self, forKey: .name)
        phone = try values.decodeIfPresent(String.self, forKey: .phone) ?? ""
        country = try values.decodeIfPresent(String.self, forKey: .country) ?? "US"
        description = try values.decodeIfPresent(String.self, forKey: .description)
            ?? legacy.decodeIfPresent(String.self, forKey: .notes)
        website = try values.decodeIfPresent(String.self, forKey: .website)
            ?? legacy.decodeIfPresent(String.self, forKey: .url)
    }
}

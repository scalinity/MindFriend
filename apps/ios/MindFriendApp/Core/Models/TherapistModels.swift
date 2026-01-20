//
//  TherapistModels.swift
//  MindFriendApp
//
//  Therapist/Coach Marketplace models - Phase 1
//

import Foundation

// MARK: - Profile Type

/// Type of professional profile
enum TherapistProfileType: String, Codable, CaseIterable, Sendable {
    case therapist
    case coach

    var displayName: String {
        switch self {
        case .therapist: return "Licensed Therapist"
        case .coach: return "Certified Coach"
        }
    }

    var description: String {
        switch self {
        case .therapist:
            return "Licensed mental health professional who can diagnose and treat mental health conditions."
        case .coach:
            return "Certified wellness coach focused on personal growth, goal-setting, and life skills."
        }
    }
}

// MARK: - Application Status

/// Application workflow status for becoming a therapist/coach
enum TherapistApplicationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case approved
    case rejected

    var displayName: String {
        switch self {
        case .pending: return "Pending Review"
        case .approved: return "Approved"
        case .rejected: return "Not Approved"
        }
    }

    var statusColor: String {
        switch self {
        case .pending: return "orange"
        case .approved: return "green"
        case .rejected: return "red"
        }
    }
}

// MARK: - Specialties

/// Areas of expertise for therapists and coaches
enum TherapistSpecialty: String, Codable, CaseIterable, Sendable {
    case anxiety
    case depression
    case trauma
    case relationships
    case grief
    case stress
    case selfEsteem = "self_esteem"
    case addiction
    case eatingDisorders = "eating_disorders"
    case ocd
    case ptsd
    case adhd
    case lifeTransitions = "life_transitions"
    case couples
    case family
    case lgbtq
    case bipolar
    case personalityDisorders = "personality_disorders"

    var displayName: String {
        switch self {
        case .anxiety: return "Anxiety"
        case .depression: return "Depression"
        case .trauma: return "Trauma"
        case .relationships: return "Relationships"
        case .grief: return "Grief & Loss"
        case .stress: return "Stress Management"
        case .selfEsteem: return "Self-Esteem"
        case .addiction: return "Addiction"
        case .eatingDisorders: return "Eating Disorders"
        case .ocd: return "OCD"
        case .ptsd: return "PTSD"
        case .adhd: return "ADHD"
        case .lifeTransitions: return "Life Transitions"
        case .couples: return "Couples Therapy"
        case .family: return "Family Therapy"
        case .lgbtq: return "LGBTQ+"
        case .bipolar: return "Bipolar Disorder"
        case .personalityDisorders: return "Personality Disorders"
        }
    }

    var icon: String {
        switch self {
        case .anxiety: return "brain.head.profile"
        case .depression: return "cloud.rain"
        case .trauma: return "heart.slash"
        case .relationships: return "person.2"
        case .grief: return "leaf"
        case .stress: return "bolt.heart"
        case .selfEsteem: return "star"
        case .addiction: return "pills"
        case .eatingDisorders: return "fork.knife"
        case .ocd: return "repeat"
        case .ptsd: return "exclamationmark.shield"
        case .adhd: return "sparkles"
        case .lifeTransitions: return "arrow.triangle.branch"
        case .couples: return "heart.circle"
        case .family: return "figure.2.and.child.holdinghands"
        case .lgbtq: return "rainbow"
        case .bipolar: return "waveform.path.ecg"
        case .personalityDisorders: return "person.crop.circle.badge.questionmark"
        }
    }
}

// MARK: - Credentials

/// Professional credentials and certifications
enum TherapistCredential: String, Codable, CaseIterable, Sendable {
    case lmft = "LMFT"
    case lcsw = "LCSW"
    case lpcc = "LPCC"
    case lpc = "LPC"
    case psyD = "PsyD"
    case phD = "PhD"
    case md = "MD"
    case doCredential = "DO"
    case np = "NP"
    case pmhnp = "PMHNP"
    case certifiedCoach = "Certified Coach"
    case acc = "ACC"
    case pcc = "PCC"
    case mcc = "MCC"
    case nbcHwc = "NBC-HWC"

    var displayName: String {
        rawValue
    }

    var fullName: String {
        switch self {
        case .lmft: return "Licensed Marriage and Family Therapist"
        case .lcsw: return "Licensed Clinical Social Worker"
        case .lpcc: return "Licensed Professional Clinical Counselor"
        case .lpc: return "Licensed Professional Counselor"
        case .psyD: return "Doctor of Psychology"
        case .phD: return "Doctor of Philosophy in Psychology"
        case .md: return "Doctor of Medicine"
        case .doCredential: return "Doctor of Osteopathic Medicine"
        case .np: return "Nurse Practitioner"
        case .pmhnp: return "Psychiatric Mental Health Nurse Practitioner"
        case .certifiedCoach: return "Certified Professional Coach"
        case .acc: return "Associate Certified Coach (ICF)"
        case .pcc: return "Professional Certified Coach (ICF)"
        case .mcc: return "Master Certified Coach (ICF)"
        case .nbcHwc: return "National Board Certified Health & Wellness Coach"
        }
    }

    /// Whether this is a licensed clinical credential (vs coaching certification)
    var isLicensedCredential: Bool {
        switch self {
        case .lmft, .lcsw, .lpcc, .lpc, .psyD, .phD, .md, .doCredential, .np, .pmhnp:
            return true
        case .certifiedCoach, .acc, .pcc, .mcc, .nbcHwc:
            return false
        }
    }
}

// MARK: - Therapeutic Approaches

/// Therapeutic modalities and approaches
enum TherapeuticApproach: String, Codable, CaseIterable, Sendable, Identifiable {
    case cbt = "CBT"
    case dbt = "DBT"
    case act = "ACT"
    case emdr = "EMDR"
    case mindfulness = "Mindfulness"
    case psychodynamic = "Psychodynamic"
    case humanistic = "Humanistic"
    case solutionFocused = "Solution-Focused"
    case narrativeTherapy = "Narrative"
    case attachmentBased = "Attachment-Based"
    case motivationalInterviewing = "Motivational Interviewing"
    case artTherapy = "Art Therapy"
    case playTherapy = "Play Therapy"
    case coachingApproach = "Coaching"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cbt: return "Cognitive Behavioral (CBT)"
        case .dbt: return "Dialectical Behavior (DBT)"
        case .act: return "Acceptance & Commitment (ACT)"
        case .emdr: return "EMDR"
        case .mindfulness: return "Mindfulness-Based"
        case .psychodynamic: return "Psychodynamic"
        case .humanistic: return "Humanistic"
        case .solutionFocused: return "Solution-Focused Brief"
        case .narrativeTherapy: return "Narrative Therapy"
        case .attachmentBased: return "Attachment-Based"
        case .motivationalInterviewing: return "Motivational Interviewing"
        case .artTherapy: return "Art Therapy"
        case .playTherapy: return "Play Therapy"
        case .coachingApproach: return "Coaching"
        }
    }
}

// MARK: - Therapist Profile

/// Complete therapist/coach profile
struct TherapistProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID
    let profileType: TherapistProfileType
    let displayName: String
    let bio: String
    let photoUrl: String?
    let credentials: [String]
    let specialties: [String]
    let approaches: [String]?
    let languages: [String]
    let licenseNumber: String?
    let licenseState: String?
    let verified: Bool
    let verifiedAt: Date?
    let backgroundCheckPassed: Bool?
    let applicationStatus: TherapistApplicationStatus
    let applicationSubmittedAt: Date?
    let rate30Min: Decimal?
    let rate45Min: Decimal?
    let rate60Min: Decimal?
    let acceptsNewClients: Bool
    let ratingAverage: Decimal?
    let ratingCount: Int
    let sessionsCompleted: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case profileType = "profile_type"
        case displayName = "display_name"
        case bio
        case photoUrl = "photo_url"
        case credentials
        case specialties
        case approaches
        case languages
        case licenseNumber = "license_number"
        case licenseState = "license_state"
        case verified
        case verifiedAt = "verified_at"
        case backgroundCheckPassed = "background_check_passed"
        case applicationStatus = "application_status"
        case applicationSubmittedAt = "application_submitted_at"
        case rate30Min = "rate_30_min"
        case rate45Min = "rate_45_min"
        case rate60Min = "rate_60_min"
        case acceptsNewClients = "accepts_new_clients"
        case ratingAverage = "rating_average"
        case ratingCount = "rating_count"
        case sessionsCompleted = "sessions_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    /// Formatted credential string (e.g., "LMFT, LCSW")
    var displayCredentials: String {
        credentials.joined(separator: ", ")
    }

    /// Formatted specialties for display
    var displaySpecialties: [TherapistSpecialty] {
        specialties.compactMap { TherapistSpecialty(rawValue: $0) }
    }

    /// Primary rate (60 min preferred, then 45, then 30)
    var primaryRate: Decimal? {
        rate60Min ?? rate45Min ?? rate30Min
    }

    /// Formatted rate string
    var displayRate: String {
        if let rate = rate60Min {
            return "$\(rate)/60 min"
        } else if let rate = rate45Min {
            return "$\(rate)/45 min"
        } else if let rate = rate30Min {
            return "$\(rate)/30 min"
        }
        return "Contact for rates"
    }

    /// Formatted rating string
    var displayRating: String {
        if let rating = ratingAverage {
            return String(format: "%.1f", NSDecimalNumber(decimal: rating).doubleValue)
        }
        return "New"
    }

    /// Whether the profile is ready to be listed
    var isListable: Bool {
        verified && applicationStatus == .approved && acceptsNewClients
    }

    /// Location display string
    var displayLocation: String? {
        licenseState
    }
}

// MARK: - Search & Filters

/// Filters for searching therapists
struct TherapistSearchFilters: Sendable {
    var specialty: TherapistSpecialty?
    var profileType: TherapistProfileType?
    var verifiedOnly: Bool = true
    var sortBy: SortOption = .ratingDescending
    var page: Int = 0
    var pageSize: Int = 20

    enum SortOption: String, CaseIterable, Sendable {
        case ratingDescending = "rating_desc"
        case ratingAscending = "rating_asc"
        case priceAscending = "price_asc"
        case priceDescending = "price_desc"
        case newest = "newest"

        var displayName: String {
            switch self {
            case .ratingDescending: return "Highest Rated"
            case .ratingAscending: return "Lowest Rated"
            case .priceAscending: return "Lowest Price"
            case .priceDescending: return "Highest Price"
            case .newest: return "Newest"
            }
        }
    }
}

/// Result of a therapist search
struct TherapistSearchResult: Sendable {
    let therapists: [TherapistProfile]
    let totalCount: Int
    let hasMore: Bool
    let page: Int
    let pageSize: Int
}

// MARK: - Application Input

/// Input data for creating a therapist application
struct TherapistApplicationInput: Codable, Sendable {
    let profileType: String
    let displayName: String
    let bio: String
    let credentials: [String]
    let specialties: [String]
    let approaches: [String]?
    let languages: [String]
    let licenseNumber: String?
    let licenseState: String?
    let rate30Min: Decimal?
    let rate45Min: Decimal?
    let rate60Min: Decimal?

    enum CodingKeys: String, CodingKey {
        case profileType = "profile_type"
        case displayName = "display_name"
        case bio
        case credentials
        case specialties
        case approaches
        case languages
        case licenseNumber = "license_number"
        case licenseState = "license_state"
        case rate30Min = "rate_30_min"
        case rate45Min = "rate_45_min"
        case rate60Min = "rate_60_min"
    }
}

/// Updates to an existing therapist profile
struct TherapistProfileUpdate: Codable, Sendable {
    var displayName: String?
    var bio: String?
    var photoUrl: String?
    var credentials: [String]?
    var specialties: [String]?
    var approaches: [String]?
    var languages: [String]?
    var licenseNumber: String?
    var licenseState: String?
    var rate30Min: Decimal?
    var rate45Min: Decimal?
    var rate60Min: Decimal?
    var acceptsNewClients: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bio
        case photoUrl = "photo_url"
        case credentials
        case specialties
        case approaches
        case languages
        case licenseNumber = "license_number"
        case licenseState = "license_state"
        case rate30Min = "rate_30_min"
        case rate45Min = "rate_45_min"
        case rate60Min = "rate_60_min"
        case acceptsNewClients = "accepts_new_clients"
    }
}

// MARK: - US States

/// US states for license selection
enum USState: String, CaseIterable, Identifiable, Sendable {
    case al = "AL", ak = "AK", az = "AZ", ar = "AR", ca = "CA"
    case co = "CO", ct = "CT", de = "DE", fl = "FL", ga = "GA"
    case hi = "HI", id = "ID", il = "IL", `in` = "IN", ia = "IA"
    case ks = "KS", ky = "KY", la = "LA", me = "ME", md = "MD"
    case ma = "MA", mi = "MI", mn = "MN", ms = "MS", mo = "MO"
    case mt = "MT", ne = "NE", nv = "NV", nh = "NH", nj = "NJ"
    case nm = "NM", ny = "NY", nc = "NC", nd = "ND", oh = "OH"
    case ok = "OK", or = "OR", pa = "PA", ri = "RI", sc = "SC"
    case sd = "SD", tn = "TN", tx = "TX", ut = "UT", vt = "VT"
    case va = "VA", wa = "WA", wv = "WV", wi = "WI", wy = "WY"
    case dc = "DC"

    var id: String { rawValue }

    var fullName: String {
        switch self {
        case .al: return "Alabama"
        case .ak: return "Alaska"
        case .az: return "Arizona"
        case .ar: return "Arkansas"
        case .ca: return "California"
        case .co: return "Colorado"
        case .ct: return "Connecticut"
        case .de: return "Delaware"
        case .fl: return "Florida"
        case .ga: return "Georgia"
        case .hi: return "Hawaii"
        case .id: return "Idaho"
        case .il: return "Illinois"
        case .in: return "Indiana"
        case .ia: return "Iowa"
        case .ks: return "Kansas"
        case .ky: return "Kentucky"
        case .la: return "Louisiana"
        case .me: return "Maine"
        case .md: return "Maryland"
        case .ma: return "Massachusetts"
        case .mi: return "Michigan"
        case .mn: return "Minnesota"
        case .ms: return "Mississippi"
        case .mo: return "Missouri"
        case .mt: return "Montana"
        case .ne: return "Nebraska"
        case .nv: return "Nevada"
        case .nh: return "New Hampshire"
        case .nj: return "New Jersey"
        case .nm: return "New Mexico"
        case .ny: return "New York"
        case .nc: return "North Carolina"
        case .nd: return "North Dakota"
        case .oh: return "Ohio"
        case .ok: return "Oklahoma"
        case .or: return "Oregon"
        case .pa: return "Pennsylvania"
        case .ri: return "Rhode Island"
        case .sc: return "South Carolina"
        case .sd: return "South Dakota"
        case .tn: return "Tennessee"
        case .tx: return "Texas"
        case .ut: return "Utah"
        case .vt: return "Vermont"
        case .va: return "Virginia"
        case .wa: return "Washington"
        case .wv: return "West Virginia"
        case .wi: return "Wisconsin"
        case .wy: return "Wyoming"
        case .dc: return "District of Columbia"
        }
    }
}

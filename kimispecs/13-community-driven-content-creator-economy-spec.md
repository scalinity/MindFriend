# Feature Specification: Community-Driven Content + Creator Economy

**COMMUNITY CONTENT & CREATOR ECONOMY SPECIFICATION**
**Version**: 1.0
**Priority**: High-Value
**Category**: Platform & Content

## Feature Overview

**Feature Name:** Community-Driven Content + Creator Economy

**Description:**
Licensed mental health professionals and certified mindfulness coaches can create, publish, and monetize their own exercises, meditations, programs, and content within MindFriend. Features include creator portal for content creation, marketplace for browsing, revenue share model (70% creator / 30% platform), quality curation by licensed clinicians, user reviews and ratings, creator discoverability, subscription options for creator followers, and analytics for creators. Creates infinite content velocity, engages expert community, and establishes MindFriend as platform (not just tool).

**Business Justification:**
Content creation bottleneck is major scaling constraint. Celebrity narrators cost $50k-500k each. Creator economy explodes (YouTube, Patreon, Instagram) showing demand for diverse voices. Therapist-generated content brings clinical credibility. 70/30 revenue share is industry standard (Patreon, Apple). Creates B2B2C model: therapist refers clients → clients subscribe using their exercise → therapist earns revenue + gets client engagement data. Scales content exponentially without production costs. Quality curation addresses concerns about unqualified amateur content.

**User Value:**
Access to diverse voices and therapeutic approaches not available in generic library. Follow favorite therapist/creator for personalized content. Trust: content from their own therapist feels more relevant. Variety: access to 100+ therapeutic modalities. Discovery: find creators whose style resonates. Cost-effective: subscription model cheaper than per-session. Supports therapist practice financially. Content tied to therapeutic relationships (if using therapist's content, more likely to continue therapy).

## Functional Requirements

### Creator Portal & Content Upload

**FR1: Creator Registration & Verification**
- Eligibility: licensed LMFT, LCSW, PhD/PsyD, LPC, LMHC, LPCC, certified meditation teachers (MBSR, MBCT)
- License verification: automated NPI lookup, manual review of certification
- Background check: criminal background (abuse/neglect prevention)
- Profile: photo, credentials, specialties, approach, bio (max 500 chars)
- Verification badge: "Licensed Therapist" or "Certified Teacher" displayed prominently
- Renewal: annual re-verification required (license expires)
- Appeal process: if denied, pathway to appeal
- Tier system: verified therapist, certified teacher, verified creator badges

**User Story:**
- As a licensed therapist, I want to join as verified creator so that my credentials are validated and users trust my content

**Acceptance Criteria:**
- [ ] License types: accepts LMFT, LCSW, PhD, PsyD, LPC, LMHC, LPCC
- [ ] NPI verification: automated lookup validates license
- [ ] Certification: accepts MBSR, MBCT, MSC, yoga teacher (500hr+)
- [ ] Criminal background: Checkr integration for criminal records
- [ ] Profile customization: photo, specialties, bio, approach
- [ ] Verification badge: "Licensed Therapist" displayed next to name
- [ ] Annual renewal: automated email 30 days before cert expires
- [ ] Appeal form: if denied, submit additional docs for review (7-14 days)
- [ ] Tier badges: gold = therapist, silver = certified teacher, bronze = verified creator (basic qualifications)

**FR2: Content Upload & Creation Tools**
- Audio recording: in-app recording tool (iPhone quality: 44.1/16bit)
- Editor: simple cut/trim tool for audio
- Script template: proven structure for different content types
- Length options: 2-20 minute meditations, 5-30 min stories
- Background sounds: library of ambient sounds (rain, waves, forest)
- Format: guided meditation, sleep story, breathing exercise, talk
- Script approval: AI screen for appropriateness, then human review
- Version control: iterate on content, keep history
- Accessibility: automatic subtitle generation (with editing)
- Multiple languages: creator can record in multiple languages

**User Story:**
- As a meditation teacher, I want easy recording tools so that I can create high-quality content without expensive equipment or software

**Acceptance Criteria:**
- [ ] Recording: built-in iPhone recorder (good quality, background noise filter)
- [ ] Simple editor: cut, trim, splice (no advanced features)
- [ ] Script templates: 7 templates (sleep story, breathing, body scan, etc.)
- [ ] Length flexibility: 2-20 minutes meditations, 5-30 min stories
- [ ] Background library: 100+ licensed sounds (free for creators)
- [ ] Formats: guided meditation, sleep story, breathing exercise, educational talk
- [ ] Script AI screen: checks for harmful/disrespectful content
- [ ] Human review: licensed clinician reviews before publication
- [ ] Version history: save iterations, can roll back
- [ ] Auto-generated subtitles: AI creates, creator edits before publish
- [ ] Multi-language: create separate language versions (each reviewed)
- [ ] File upload: upload pre-recorded (.mp3, .m4a accepted)

**FR3: Content Categorization & Tagging**
- Categories: anxiety, depression, sleep, stress, trauma, grief, relationships, ADHD, addiction, panic, PTSD, OCD
- Subcategories: work stress, social anxiety, generalized anxiety, specific phobias
- Intensity levels: beginner, intermediate, advanced
- Therapeutic approach: CBT, DBT, ACT, mindfulness, trauma-informed, EMDR-informed
- Duration: 2-5 min quick, 5-15 standard, 15-30 deep
- Age appropriateness: adult, teen, child (with modifications)
- Cultural context: secular or specific cultural adaptations
- Symptom focus: rumination, irritability, low energy, hyperarousal
- Evidence-base: peer-reviewed research cited (optional)
- Language: specify language of content (with subtitle availability)

**User Story:**
- As a creator, I want granular tagging so that users can find my content when searching for specific issue or therapeutic approach

**Acceptance Criteria:**
- [ ] Category dropdown: 15 primary mental health categories
- [ ] Subcategories: 2-3 sub-areas per category (total 45)
- [ ] Intensity: beginner/medium/advanced
- [ ] Therapeutic approach: CBT, DBT, ACT, mindfulness, trauma-informed listed
- [ ] Duration: short/standard/long
- [ ] Age: adult/teen/child with modifications noted
- [ ] Cultural context: indicates secular vs specific adaptations
- [ ] Symptom tags: 20 common symptoms (rumination, irritability, low energy)
- [ ] Evidence field: optional citation DOI/links to research
- [ ] Language: English (subtitles Spanish), or other languages
- [ ] User search: content appears when searching any tag

### Marketplaces & Discoverability 

**FR4: Creator Marketplace Browsing**
- Featured creators: curated list of top creators (monthly)
- Browse by category: find creators by specialty (anxiety, trauma, etc.)
- Browse by approach: CBT, mindfulness, somatic, etc.
- Search: keyword search for creators or content
- Filters: licensed therapist vs certified teacher, rating, content count
- Creator profiles: photo, bio, credentials, specialties, sample content
- Reviews: user reviews with verified purchase (subscription)
- Ratings: 1-5 stars aggregated
- Statistics: number of followers, content pieces, average rating
- Content preview: 30-60 second sample of creator's content
- Following: user follows creator (get notified of new content)

**User Story:**
- As a user, I want to discover new creators with quality content in my interest area so that I can find therapeutic style that resonates with me

**Acceptance Criteria:**
- [ ] Featured section: 10-15 creators highlighted (rotated monthly)
- [ ] Category browsing: anxiety, depression, sleep, trauma creators grouped
- [ ] Approach filters: CBT, DBT, ACT, mindfulness, somatic
- [ ] Search functionality: name, specialty, keywords (e.g., "panic attacks")
- [ ] Filters: licensed therapist, certified teacher, rating 4.0+, content count (>10)
- [ ] Creator cards: photo, credentials, specialties, short bio, rating, follower count
- [ ] Sample audio: 30-60 second clip of creator's voice/style
- [ ] Verified badge: indicates license/certification verified
- [ ] Statistics displayed: follows, content count, ratings
- [ ] Follow button: one-tap follow (notifications for new content)
- [ ] Sort: by rating, popularity, newest, alphabetical

**FR5: Individual Creator Profile Page**
- Professional credentials: license number (if therapist), certifications
- Bio: who they are, approach, experience (500-2000 chars)
- Content library: all creator's content displayed
- Pricing: subscription cost (if creator offers)
- Reviews: user-written reviews (approved by creator before public)
- Contact: direct message for Q&A (not therapy)
- Social media: links to social profiles (optional)
- Special offers: new subscriber discounts, bundle deals
- Video intro: optional 60-second video introducing themselves
- Upcoming: scheduled releases (coming soon)
- Popularity: follower count, total plays, average rating

**User Story:**
- As a user considering subscribing to creator, I want detailed profile showing their credentials, approach, sample of their content so that I can decide if their style resonates before paying

**Acceptance Criteria:**
- [ ] Credentials displayed: license number, certifications (verifiable)
- [ ] Bio section: rich text, who they are, approach, specialization
- [ ] Content library: thumbnails of all content pieces
- [ ] Pricing transparent: $4.99/mo or $29.99/year clearly shown
- [ ] Reviews: 5-star average, individual reviews (user can write after subscription)
- [ ] Contact: direct message form (response time expectations)
- [ ] Social links: optional links to Instagram, website, etc.
- [ ] Video introduction: optional 60-90 second intro video (not required)
- [ ] Upcoming releases: "New content coming next week" preview
- [ ] Popularity metrics: follower count, total listens, avg rating visible
- [ ] Subscribe: clear "Subscribe" button (with price)
- [ ] Preview: limited listening to 2-3 pieces (with watermark)

### Revenue Share & Monetization

**FR6: Revenue Share Model**
- 70% creator / 30% platform split on individual creator subscriptions
- 80% creator / 20% platform on individual piece purchases ($0.99-4.99/each)
- 50% pool share on app subscription base (proportional to watch time)
- Payout schedule: monthly via Stripe, PayPal, direct deposit (creator choice)
- Threshold: $50 minimum to disburse (per payment method)
- Transparency: detailed dashboard showing plays, subscriptions, revenue
- Currency: USD base, auto-convert to creator's local currency if international
- Tax reporting: 1099-MISC / 1099-K for US creators, equivalent for others
- Refund policy: 48-hour refund window reduces creator payout
- Analytics: real-time stats showing today's revenue, plays, new subscribers

**User Story:**
- As a creator, I want clear revenue sharing (70/30) and transparent analytics so that I understand my earnings and see real-time performance

**Acceptance Criteria:**
- [ ] Subscription split: 70% creator / 30% platform on individual creator subs
- [ ] À la carte: 80% creator / 20% platform (individual purchases)
- [ ] Base subscription: 50% revenue pool shared proportionally by engagement
- [ ] Payout monthly: via Stripe, PayPal, or direct deposit (creator's choice)
- [ ] Minimum threshold: $50 minimum for disbursement (avoids fees on tiny amounts)
- [ ] Dashboard: real-time plays, subscriptions, revenue tracking
- [ ] Transparency: detailed breakdown showing individual vs. pool payments
- [ ] Currency conversion: USD automatically converted to local currency
- [ ] Tax forms: US = 1099-MISC/1099-K; UK = appropriate self-employment
- [ ] Refunds: 48-hour window → if refunded, that month not paid to creator
- [ ] Analytics: today's revenue, new subscribers, total plays updated instantly

**FR7: Subscription Models**
- Individual creator: $4.99-9.99/month (creator sets pricing)
- Creator bundles: subscribe to 3-5 creators for discounted rate 
- à la carte: purchase individual piece ($0.99-4.99)
- All creators: app premium subscription includes all verified creators
- Free trial: 7-day trial for individual creator subscriptions
- Cancellation: easy cancellation anytime (retain access until end of billing period)
- Tier levels: Bronze/Silver/Gold creator tiers (different pricing allowed)
- Loyalty discount: 10% off if subscriber for 12+ months
- Gift subscriptions: can pay for friend/family subscription
- Referral: creator gets bonus payment if refers new user who subscribes to other creators

**User Story:**
- As a user, I want flexible subscription options so that I can choose between subscribing to individual creator or getting all creators via premium app subscription

**Acceptance Criteria:**
- [ ] Individual creator: $4.99-9.99/month (creator sets within range)
- [ ] Bundles: 3 creators $12.99/mo (33% discount), 5 creators $18.99/mo (40% discount)
- [ ] Single purchase: buy one piece for $0.99-4.99 (no subscription)
- [ ] All creators: MindFriend Premium includes all verified creators (premium tier)
- [ ] Free trial: 7-day trial on individual creator subs (credit card required)
- [ ] Cancellation: tap to cancel, access continues until billing end
- [ ] Tiers: Bronze $4.99, Silver $6.99, Gold $9.99 (quality/experience-based)
- [ ] Loyalty discount: 12+ month subscription → 10% off ongoing
- [ ] Gift: purchase 3-month gift subscription for friend
- [ ] Referral bonus: creator gets $5 bonus if refers user who subscribes (any creator)
- [ ] Pause: can pause subscription up to 3 months (retain history)

### Quality Curation & Moderation

**FR8: Clinical Review & Quality Curation**
- Review board: 5 licensed clinical psychologists review submissions
- Random sampling: 10% of content reviewed (for established creators), 100% for new creators (first 10 pieces)
- Feedback: if needs revision, detailed comments to creator
- Approval timeline: 7-14 days for review (notify creator of status)
- Peer review: creators can review each other's content (optional)
- Standards: evidence-based, person-first language, therapeutic appropriateness
- Quality score: 1-10 rating by clinical reviewers
- Minimum quality: score 7+ required for publication
- Re-review: if creator receives low ratings 3x, enhanced supervision
- Continuous: quarterly review of high-performing content (not just new)

**User Story:**
- As a user, I want assurance that creator content is clinically reviewed so that I can trust content quality and not worry about inappropriate or ineffective guidance

**Acceptance Criteria:**
- [ ] Review board: 5 licensed psychologists/clinicians employed/consulted by MindFriend
- [ ] Random sampling: 10% of established creator content reviewed quarterly
- [ ] New creator: first 10 pieces get 100% review
- [ ] Feedback: detailed comments if rejection, specific changes requested
- [ ] Timeline: 7-14 day review period (notify creator of approval, revision, rejection)
- [ ] Standards checklist: evidence-based, person-first, therapeutic appropriateness
- [ ] Quality score: reviewer rates 1-10, must be 7+ for publication
- [ ] Re-review process: if creator gets low ratings 3x → 100% review for next 20 pieces
- [ ] Continuous improvement: high-performing content reviewed quarterly (not stagnating)
- [ ] Peer review optional: creators can opt-in to peer reviews for development

**FR9: User Review & Rating System**
- Star rating: 1-5 stars per piece
- Written reviews: optional, limited to 500 chars
- Verified purchase: can only review content if accessed (subscription or purchase)
- Helpful votes: "Was this review helpful? Yes/No"
- Moderation: creator can flag inappropriate reviews
- Response: creator can publicly respond to reviews
- Aggregate: average rating displayed for piece and creator
- Minimum reviews: 10 reviews before rating displayed
- Review incentives: users earn 10 coin points for leaving review
- Ratings: if rating < 2 stars repeatedly, content flagged for re-review

**User Story:**
- As user, I want to read reviews from other subscribers so that I can decide if content is effective and worth subscribing to

**Acceptance Criteria:**
- [ ] Star rating: 1-5 stars per piece (average calculated)
- [ ] Written reviews: optional, max 500 characters, approved by moderator
- [ ] Verified: only those who accessed content can review (prevents gaming)
- [ ] Helpful votes: community rates review helpful (increases helpful reviews visibility)
- [ ] Moderation: creator can flag reviews that are inappropriate/abusive
- [ ] Creator response: public reply feature to address concerns
- [ ] Aggregate rating: average for both piece level and creator level
- [ ] Minimum threshold: 10 reviews required before rating displayed publicly
- [ ] Review incentive: 10 coins (platform currency) for each review written
- [ ] Quality monitoring: multiple <2 star reviews → flag for clinical review

### Creator Analytics & Discovery

**FR10: Creator Analytics Dashboard**
- Total plays: lifetime plays for all content pieces
- Unique listeners: number of users who listened
- Average completion rate: % who finish full piece
- Subscriber growth: new subscribers over time graph
- Revenue: monthly earnings with detailed breakdown
- Popular content: top 5 pieces by plays/engagement
- Demographics: age, location, primary issues of listeners
- Engagement patterns: what days/times most popular
- Retention: subscriber churn rate
- Comparative: percentile rank vs. other creators (anonymized)
- Feedback themes: AI summarizes common review themes
- Improvement suggestions: based on feedback + engagement

**User Story:**
- As a creator, I want detailed analytics so that I can understand my audience, see what content resonates, track earnings, and improve my content based on data

**Acceptance Criteria:**
- [ ] Total plays: lifetime plays across all content
- [ ] Unique listeners: user IDs (de-duplicated) count
- [ ] Completion rate: average % of full duration listened (for each piece)
- [ ] Subscriber growth: graph showing new subscriptions per day/week/month
- [ ] Revenue dashboard: monthly earnings broken down by piece/subscription type
- [ ] Top content: table showing top 5 pieces by plays (change timeframe)
- [ ] Demographics: age distribution, primary countries, top issues (anonymized)
- [ ] Time patterns: popular days of week, times of day for listens
- [ ] Retention chart: monthly churn rate of subscribers
- [ ] Comparative: "You're in top 15% of creators for engagement"
- [ ] Theme summarizer: AI analyzes reviews, extracts common themes
- [ ] Feedback suggestions: actionable improvement ideas based on data
- [ ] Export: CSV export of analytics for creator's own analysis

**FR11: Creator Discovery & Promotion**
- Featured algorithm: based on rating, engagement, recency
- Search ranking: higher-rated content appears earlier
- Trending: most new followers this week
- New creator: spotlight for first 30 days
- Seasonal promotion: seasonal content boosted (e.g., "spring anxiety")
- User following: subscribers get notified of new content
- Social sharing: share creator profile or piece on social media
- Creator AMA: "Ask Me Anything" sessions hosted in app
- Collaboration: creators can co-create content together
- Challenge participation: creators participate in themed challenges

**User Story:**
- As a new creator, I want discovery features so that users can find my content, and I can grow my subscriber base alongside others

**Acceptance Criteria:**
- [ ] Featured algorithm: rating (40%), engagement (35%), recency (25%) for homepage
- [ ] Search rank: higher rating + more reviews appears at top of search
- [ ] Trending section: creators with most new followers (week-over-week)
- [ ] New creator spotlight: "New Therapist Voices" category for 30 days
- [ ] Seasonal boost: seasonal content gets featured (e.g., "Holiday Stress") seasonal
- [ ] Following notification: push when followed creator publishes new content
- [ ] Social sharing: generate link to creator profile with preview image
- [ ] AMA sessions: host live Q&A within app (scheduled, promoted)
- [ ] Co-creation: two creators can collaborate on joint piece (split revenue)
- [ ] Challenges: monthly themes (e.g., "Self-Compassion February")

### Technical Specifications

#### Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│         Content Creator Portal (Web React)         │
│  ┌───────────┐  ┌──────────┐  ┌─────────────┐     │
│  │ Upload    │  │ Analytics│  │ Subscription│     │
│  │ Studio    │  │ Dashboard│  │ Management  │     │
│  └─────
[Truncated - see full file in source directory]
```

### Data Models

#### creators
```sql
CREATE TABLE creators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) NULL, -- if also app user
    
    -- Identity
    display_name VARCHAR(128) NOT NULL,
    profile_photo_url TEXT NULL,
    
    -- Credentials
    credential_type VARCHAR(32) NOT NULL, -- 'licensed_therapist', 'certified_teacher', 'verified_creator'
    license_number VARCHAR(64) NULL, -- NPI for therapists
    license_state VARCHAR(2) NULL,
    certifications TEXT[] NULL, -- ['MBSR', 'MBCT', 'RYT-500']
    
    -- Verification
    verified BOOLEAN NOT NULL DEFAULT false,
    verified_at TIMESTAMPTZ NULL,
    verification_expires_at TIMESTAMPTZ NULL,
    background_check_passed BOOLEAN NULL,
    background_check_date DATE NULL,
    
    -- Content
    content_count INT NOT NULL DEFAULT 0,
    total_plays BIGINT NOT NULL DEFAULT 0,
    total_unique_listeners INT NOT NULL DEFAULT 0,
    average_rating DECIMAL(3,2) NULL,
    rating_count INT NOT NULL DEFAULT 0,
    subscriber_count INT NOT NULL DEFAULT 0,
    
    -- Monetization
    subscription_price_cents INT NOT NULL DEFAULT 499, -- $4.99
    subscription_currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    billing_interval VARCHAR(16) NOT NULL DEFAULT 'monthly',
    
    -- Profile
    bio TEXT NOT NULL,
    specialties TEXT[] NOT NULL DEFAULT '{}',
    approach TEXT NULL,
    languages TEXT[] NOT NULL DEFAULT '{en}',
    years_experience SMALLINT NULL,
    
    -- Status
    active BOOLEAN NOT NULL DEFAULT true,
    accepting_subscribers BOOLEAN NOT NULL DEFAULT true,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_creators_verified ON creators (verified, active);
CREATE INDEX idx_creators_subscription ON creators (subscription_price_cents, subscriber_count DESC);
CREATE UNIQUE INDEX idx_creators_license ON creators (license_number, license_state) WHERE license_number IS NOT NULL;
```

#### content_pieces
```sql
CREATE TABLE content_pieces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID REFERENCES creators(id) NOT NULL,
    
    -- Metadata
    title VARCHAR(256) NOT NULL,
    description TEXT NOT NULL,
    content_type VARCHAR(32) NOT NULL, -- 'meditation', 'sleep_story', 'breathing', 'talk'
    category VARCHAR(32) NOT NULL,
    duration_seconds INT NOT NULL CHECK (duration_seconds BETWEEN 30 AND 3600),
    
    -- Files
    audio_url TEXT NOT NULL,
    preview_url TEXT NOT NULL, -- 60 second preview
    transcript TEXT NULL, -- for accessibility
    cover_image_url TEXT NULL,
    
    -- Status
    status VARCHAR(16) NOT NULL DEFAULT 'draft', -- draft, review, approved, rejected
    review_status VARCHAR(16) NULL, -- pending, approved, revisions_needed, rejected
    review_feedback TEXT NULL,
    reviewed_by UUID NULL, -- reviewer user ID
    review_score SMALLINT NULL CHECK (review_score BETWEEN 1 AND 10),
    
    -- Pricing
    pricing_type VARCHAR(16) NOT NULL DEFAULT 'subscription', -- subscription, a_la_carte
    a_la_carte_price_cents INT NULL, -- if individual purchase
    
    -- Analytics
    play_count BIGINT NOT NULL DEFAULT 0,
    unique_listener_count INT NOT NULL DEFAULT 0,
    completion_rate_avg DECIMAL(5,2) NULL, -- average % watched
    average_rating DECIMAL(3,2) NULL,
    rating_count INT NOT NULL DEFAULT 0,
    
    -- Tags
    tags TEXT[] NOT NULL DEFAULT '{}',
    therapeutic_approach TEXT[] NOT NULL DEFAULT '{}',
    intensity_level VARCHAR(16) NULL,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_content_creator ON content_pieces (creator_id, status);
CREATE INDEX idx_content_type ON content_pieces (content_type, category);
CREATE INDEX idx_content_published ON content_pieces (published_at DESC) WHERE status = 'approved';
```

[Additional data models for subscriptions, reviews, payments, analytics...]

### API Endpoints

#### POST /creators/register
```typescript
POST /v1/creators/register

Request:
{
  "displayName": "Dr. Sarah Chen, LMFT",
  "email": "sarah@example.com",
  "credentialType": "licensed_therapist",
  "licenseNumber": "LMFT123456",
  "licenseState": "CA",
  "credentials": ["LCSW", "EMDR"],
  "bio": "I specialize in anxiety and trauma using evidence-based approaches...",
  "specialties": ["anxiety", "trauma", "PTSD"],
  "languages": ["en", "mandarin"]
}

Response 201:
{
  "creatorId": "uuid",
  "status": "pending_verification",
  "estimatedReviewTime": "7-10 business days",
  "nextSteps": "Submit sample content for review"
}
```

#### POST /creators/content
```typescript
POST /v1/creators/content

Headers: { "Authorization": "Bearer creator-jwt" }

Request:
{
  "title": "Anxiety Relief Breathing Exercise",
  "description": "3-minute guided breathing for acute anxiety episodes",
  "contentType": "breathing",
  "category": "anxiety",
  "durationSeconds": 180,
  "audioUrl": "uploaded-file-url",
  "previewUrl": "60-second-preview-url",
  "tags": ["anxiety", "breathing", "acute", "panic"],
  "approach": ["mindfulness"],
  "intensityLevel": "beginner"
}

Response 201:
{
  "contentId": "uuid",
  "status": "submitted_for_review",
  "estimatedReviewTime": "5-7 business days",
  "reviewQueuePosition": 12
}
```

[Additional specification continues...]

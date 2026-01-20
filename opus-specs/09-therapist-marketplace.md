# Therapist/Coach Marketplace

> Bridge AI support with human connection through a curated professional network.

**Priority:** P1 - High Value
**Effort:** Very High (12-16 weeks)
**Impact:** Revenue multiplier; opens $10B+ therapy market

---

## 1. Overview

### 1.1 What It Does

A marketplace connecting users with licensed therapists and certified wellness coaches for 1:1 video sessions, with seamless handoff from AI to human support.

### 1.2 Why It Exists

- **AI Limits:** Some users need human connection beyond AI capability
- **Safety Net:** Provides escalation path for crisis situations
- **Revenue:** Commission model (15-25%) on session fees
- **Differentiation:** Calm/Headspace have NO human support; unique positioning

### 1.3 Success Metrics

| Metric               | Target               | Measurement           |
| -------------------- | -------------------- | --------------------- |
| Therapist onboarding | 100+ in year 1       | Count                 |
| Session bookings     | 10% of premium users | Booking / Premium MAU |
| Session completion   | 90%+                 | Completed / Booked    |
| User satisfaction    | 4.7+                 | Post-session rating   |
| Therapist retention  | 80%+ annually        | Retention rate        |

---

## 2. User Types

### 2.1 Users (Clients)

- Browse therapist profiles
- Book and pay for sessions
- Attend video sessions
- Rate and review therapists
- Share AI context with therapist (opt-in)

### 2.2 Therapists

- Create verified profile
- Set availability and rates
- Accept/decline bookings
- Conduct video sessions
- Access client context (with consent)
- Receive payouts

### 2.3 Coaches (Non-Licensed)

- Lower barrier to entry
- Focus on wellness, not clinical
- Lower price point
- Cannot treat mental disorders

---

## 3. Functional Requirements

### 3.1 Therapist Discovery

| ID    | Requirement                                             | Priority |
| ----- | ------------------------------------------------------- | -------- |
| TD-01 | Search by specialty (anxiety, depression, trauma, etc.) | Must     |
| TD-02 | Filter by availability, price, gender, language         | Must     |
| TD-03 | Display credentials and verification badges             | Must     |
| TD-04 | Show ratings and review excerpts                        | Must     |
| TD-05 | "MindFriend Recommended" based on user's mood data      | Should   |
| TD-06 | Insurance compatibility filter                          | Should   |

### 3.2 Booking System

| ID    | Requirement                                 | Priority |
| ----- | ------------------------------------------- | -------- |
| BS-01 | View therapist calendar availability        | Must     |
| BS-02 | Book 30/45/60 minute sessions               | Must     |
| BS-03 | Secure payment via Stripe                   | Must     |
| BS-04 | Cancellation policy (24h free cancellation) | Must     |
| BS-05 | Automatic reminders (24h, 1h before)        | Must     |
| BS-06 | Reschedule functionality                    | Must     |
| BS-07 | Package purchases (4/8 session bundles)     | Should   |

### 3.3 Video Sessions

| ID    | Requirement                   | Priority |
| ----- | ----------------------------- | -------- |
| VS-01 | In-app video calling          | Must     |
| VS-02 | Audio-only option             | Must     |
| VS-03 | Screen sharing for exercises  | Should   |
| VS-04 | Session timer visible to both | Must     |
| VS-05 | End session button            | Must     |
| VS-06 | Connection quality indicator  | Should   |
| VS-07 | Waiting room before session   | Should   |

### 3.4 Context Sharing

| ID    | Requirement                                | Priority |
| ----- | ------------------------------------------ | -------- |
| CS-01 | User can share mood history with therapist | Should   |
| CS-02 | User can share journal entries (selected)  | Should   |
| CS-03 | User can share AI chat summary             | Should   |
| CS-04 | Sharing requires explicit consent          | Must     |
| CS-05 | User can revoke access anytime             | Must     |

### 3.5 Therapist Onboarding

| ID    | Requirement                                | Priority |
| ----- | ------------------------------------------ | -------- |
| TO-01 | License verification (automated + manual)  | Must     |
| TO-02 | Background check integration               | Must     |
| TO-03 | Profile creation (bio, photo, specialties) | Must     |
| TO-04 | Rate setting ($50-$300/session)            | Must     |
| TO-05 | Availability calendar setup                | Must     |
| TO-06 | Payment account setup (Stripe Connect)     | Must     |
| TO-07 | Training on MindFriend platform            | Should   |

### 3.6 Payments & Payouts

| ID    | Requirement                                      | Priority |
| ----- | ------------------------------------------------ | -------- |
| PP-01 | Secure payment processing (Stripe)               | Must     |
| PP-02 | MindFriend commission (20% default)              | Must     |
| PP-03 | Weekly payouts to therapists                     | Must     |
| PP-04 | Invoice generation                               | Must     |
| PP-05 | HSA/FSA payment support                          | Should   |
| PP-06 | Superbill generation for insurance reimbursement | Should   |

---

## 4. Technical Requirements

### 4.1 Data Models

```sql
-- Therapist profiles
CREATE TABLE therapist_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    profile_type TEXT NOT NULL CHECK (profile_type IN ('therapist', 'coach')),

    -- Professional info
    display_name TEXT NOT NULL,
    bio TEXT NOT NULL,
    photo_url TEXT,
    credentials TEXT[], -- 'LMFT', 'LCSW', 'PsyD', etc.
    specialties TEXT[], -- 'anxiety', 'depression', 'trauma', etc.
    approaches TEXT[], -- 'CBT', 'DBT', 'EMDR', etc.
    languages TEXT[] DEFAULT ARRAY['English'],

    -- Verification
    license_number TEXT,
    license_state TEXT,
    verified BOOLEAN DEFAULT false,
    verified_at TIMESTAMPTZ,
    background_check_passed BOOLEAN DEFAULT false,

    -- Rates
    rate_30_min DECIMAL(10,2),
    rate_45_min DECIMAL(10,2),
    rate_60_min DECIMAL(10,2),

    -- Settings
    accepts_new_clients BOOLEAN DEFAULT true,

    -- Stripe
    stripe_account_id TEXT,

    -- Stats
    rating_average DECIMAL(3,2),
    rating_count INTEGER DEFAULT 0,
    sessions_completed INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Therapist availability
CREATE TABLE therapist_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID NOT NULL REFERENCES therapist_profiles(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'America/New_York'
);

-- Session bookings
CREATE TABLE therapy_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    therapist_id UUID NOT NULL REFERENCES therapist_profiles(id),

    -- Timing
    scheduled_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes IN (30, 45, 60)),

    -- Status
    status TEXT DEFAULT 'scheduled' CHECK (status IN (
        'scheduled', 'confirmed', 'in_progress', 'completed',
        'cancelled_user', 'cancelled_therapist', 'no_show'
    )),

    -- Video
    video_room_id TEXT,

    -- Payment
    amount_cents INTEGER NOT NULL,
    commission_cents INTEGER NOT NULL,
    payment_intent_id TEXT,
    paid BOOLEAN DEFAULT false,

    -- Context sharing
    shared_mood_history BOOLEAN DEFAULT false,
    shared_journal_ids UUID[],
    shared_chat_summary BOOLEAN DEFAULT false,

    -- Post-session
    user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5),
    user_review TEXT,
    therapist_notes TEXT, -- Private to therapist

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE therapist_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapist_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapy_sessions ENABLE ROW LEVEL SECURITY;

-- Profiles are publicly viewable if verified
CREATE POLICY "Verified therapists public"
    ON therapist_profiles FOR SELECT
    USING (verified = true AND accepts_new_clients = true);

-- Therapists manage own profile
CREATE POLICY "Therapists manage own profile"
    ON therapist_profiles FOR ALL
    USING (auth.uid() = user_id);

-- Availability readable by all
CREATE POLICY "Availability public for verified"
    ON therapist_availability FOR SELECT
    USING (therapist_id IN (
        SELECT id FROM therapist_profiles WHERE verified = true
    ));

-- Sessions visible to participant
CREATE POLICY "Sessions visible to participants"
    ON therapy_sessions FOR SELECT
    USING (
        auth.uid() = user_id OR
        auth.uid() IN (SELECT user_id FROM therapist_profiles WHERE id = therapist_id)
    );
```

### 4.2 Video Infrastructure

```swift
// Using a service like Daily.co, Twilio, or Agora

protocol VideoSessionProvider {
    func createRoom(sessionId: UUID) async throws -> VideoRoom
    func joinRoom(roomId: String, asHost: Bool) async throws -> VideoSession
    func endRoom(roomId: String) async throws
}

struct VideoRoom {
    let roomId: String
    let joinUrl: URL
    let hostToken: String
    let participantToken: String
    let expiresAt: Date
}

class DailyVideoProvider: VideoSessionProvider {
    let apiKey = ProcessInfo.processInfo.environment["DAILY_API_KEY"]!

    func createRoom(sessionId: UUID) async throws -> VideoRoom {
        // Call Daily.co API to create room
        // Return room details
    }

    func joinRoom(roomId: String, asHost: Bool) async throws -> VideoSession {
        // Initialize Daily SDK
        // Join room with appropriate token
    }
}
```

### 4.3 Edge Functions

```typescript
// supabase/functions/create-therapy-session/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@12";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const COMMISSION_RATE = 0.2; // 20%

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { therapist_id, scheduled_at, duration_minutes } = await req.json();

  // Get therapist info
  const { data: therapist } = await supabase
    .from("therapist_profiles")
    .select("*")
    .eq("id", therapist_id)
    .single();

  if (!therapist || !therapist.verified) {
    return new Response("Therapist not found", { status: 404 });
  }

  // Calculate price
  const rateKey = `rate_${duration_minutes}_min`;
  const amount = Math.round(therapist[rateKey] * 100); // cents
  const commission = Math.round(amount * COMMISSION_RATE);

  // Create Stripe PaymentIntent with destination charge
  const paymentIntent = await stripe.paymentIntents.create({
    amount,
    currency: "usd",
    application_fee_amount: commission,
    transfer_data: {
      destination: therapist.stripe_account_id,
    },
    metadata: {
      user_id: user.id,
      therapist_id,
    },
  });

  // Create session record
  const { data: session, error } = await supabase
    .from("therapy_sessions")
    .insert({
      user_id: user.id,
      therapist_id,
      scheduled_at,
      duration_minutes,
      amount_cents: amount,
      commission_cents: commission,
      payment_intent_id: paymentIntent.id,
    })
    .select()
    .single();

  return new Response(
    JSON.stringify({
      session,
      clientSecret: paymentIntent.client_secret,
    }),
    {
      headers: { "Content-Type": "application/json" },
    },
  );
});
```

---

## 5. UI/UX Specifications

### 5.1 Therapist Discovery

```
┌─────────────────────────────────┐
│ Find a Therapist           🔍   │
├─────────────────────────────────┤
│                                 │
│ What brings you here?           │
│ [Anxiety] [Depression] [Stress] │
│ [Relationships] [Trauma] [More] │
│                                 │
│ Recommended for You             │
│ ┌─────────────────────────────┐ │
│ │ 👤 Dr. Sarah Johnson, LMFT  │ │
│ │ ⭐ 4.9 (127 reviews)        │ │
│ │ Anxiety • CBT • Adults      │ │
│ │ $120 / 50 min               │ │
│ │ Next: Tomorrow 2pm          │ │
│ │                [View →]     │ │
│ └─────────────────────────────┘ │
│                                 │
│ All Therapists                  │
│ ┌─────────────────────────────┐ │
│ │ 👤 Michael Chen, PsyD       │ │
│ │ ⭐ 4.8 (89 reviews)         │ │
│ │ Depression • DBT            │ │
│ │ $150 / 50 min               │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### 5.2 Therapist Profile

```
┌─────────────────────────────────┐
│ ←                               │
├─────────────────────────────────┤
│     ┌─────────────────┐         │
│     │                 │         │
│     │     Photo       │         │
│     │                 │         │
│     └─────────────────┘         │
│                                 │
│ Dr. Sarah Johnson, LMFT         │
│ Licensed Marriage & Family      │
│ Therapist • California          │
│                                 │
│ ⭐ 4.9 (127 reviews) • ✓ Verified│
│                                 │
│ ─────────────────────────────── │
│                                 │
│ About                           │
│ I specialize in helping adults  │
│ manage anxiety and build        │
│ healthier relationships...      │
│                                 │
│ Specialties                     │
│ [Anxiety] [Relationships]       │
│ [Life Transitions] [Self-Esteem]│
│                                 │
│ Approaches                      │
│ [CBT] [Mindfulness] [Attachment]│
│                                 │
│ ─────────────────────────────── │
│                                 │
│ Session Rates                   │
│ 30 min: $80 │ 50 min: $120      │
│                                 │
│ [Book a Session]                │
│                                 │
└─────────────────────────────────┘
```

---

## 6. Acceptance Criteria

- [ ] Users can browse verified therapists by specialty
- [ ] Users can view therapist profiles with credentials
- [ ] Users can book and pay for sessions
- [ ] Video sessions work with good quality
- [ ] Users can rate and review therapists
- [ ] Therapists receive payouts weekly
- [ ] Context sharing requires explicit consent
- [ ] License verification process works

---

## 7. Compliance & Security

| Area                 | Requirement                                       |
| -------------------- | ------------------------------------------------- |
| HIPAA                | BAA with video provider; encrypted communications |
| License Verification | Third-party verification service integration      |
| Data Privacy         | Session notes encrypted; user controls sharing    |
| Payment Security     | PCI-compliant via Stripe                          |
| Background Checks    | Required for all providers                        |

---

## 8. Rollout Plan

### Phase 1: Foundation (Week 1-4)

- Therapist profile system
- Basic discovery UI
- License verification workflow

### Phase 2: Booking (Week 5-8)

- Calendar/availability system
- Payment integration (Stripe Connect)
- Booking flow

### Phase 3: Video (Week 9-12)

- Video provider integration
- In-app video calling
- Session management

### Phase 4: Context & Polish (Week 13-16)

- Context sharing
- Reviews and ratings
- Therapist dashboard
- HSA/FSA support

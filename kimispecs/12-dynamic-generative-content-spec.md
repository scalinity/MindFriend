# Feature Specification: Dynamic Content + Generative Audio

**DYNAMIC CONTENT GENERATION SPECIFICATION**
**Version**: 1.0
**Priority**: High-Value
**Category**: AI-Generated Wellness Content

## Feature Overview

**Feature Name:** Dynamic Content + Generative Audio

**Description:**
AI-powered system that generates personalized mental health content including custom sleep stories, guided meditations, breathing exercises, grounding techniques, mindfulness prompts, and cognitive restructuring exercises tailored to user's immediate needs, preferences, history and biometric context. Content is algorithmically generated, not static library, creating infinite variety while maintaining therapeutic quality. Combines GPT-style generation for text with voice synthesis (ElevenLabs, Play.ht) for natural narration. Users can request "something new about X" and receive tailored content.

**Business Justification:**
Content creation is expensive ($50k-500k per celebrity narrator). Static libraries cost millions to develop. AI generation slashes production costs 90% while enabling infinite personalization. Reduces dependency on limited content inventory. Enables real-time content adaptation based on user state. Creates perpetual novelty driving 25-40% higher retention. Scales globally: instant translation to any language. Customizable for B2B clients (branded, company-specific content). Premium tier differentiator: "Unlimited personalized content" vs generic library.

**User Value:**
Never run out of new content tailored to exact needs. "I need a 7-minute meditation for work stress with ocean sounds and male voice" delivered on-demand. Content adapts to preferences (voice, pace, background). Reflects current mood/energy—gentle when stressed, energizing when low mood. Addresses edge cases: specific phobias, industry-specific scenarios, cultural contexts. Reduces redundancy while maintaining therapeutic quality. Cost-effective access for premium users creates value justification.

## Functional Requirements

### AI-Powered Text Generation

**FR1: Sleep Story Generation**
- Generate custom sleep stories: length (5-30 min), theme (forest, ocean, space), narrator style (calm, playful, whisper)
- Personal integration: user name, location, favorite activities woven into story
- Guided by user: "Create story about hiking in mountains with bear friend"
- Style variations: ASMR whisper, hypnotic pace, traditional storytelling (male/female, various accents)
- Length control: specify exactly to match sleep onset time
- Quality guardrails: therapeutic language filters, no stimulating content
- Background sounds: generate or mix audio cues (rain, crackling fire)
- Serial continuation: multi-night story arcs

**User Story:**
- As someone tired of re-listening to same stories, I want new personalized content so that I can maintain engagement without getting bored

**Acceptance Criteria:**
- [ ] Generate 5-30 minute sleep story within 30 seconds
- [ ] Integrate personal details: user's name, interests, preferences
- [ ] Guided generation: "Make a story about sailing, with calm narrator, 12 minutes"
- [ ] Style options: whisper ASMR (female), calm male, storytelling grandmother
- [ ] Audio background: rain, ocean, leaves, crackling fire mixing
- [ ] Quality filters: no conflict, no excitement, calming pacing
- [ ] Continuation: night 2 of story builds on night 1
- [ ] User rating: 1-5 stars improves generation for user

**FR2: Guided Meditation Generation**
- Request on-demand meditations: length (3-15 min), focus (anxiety, focus, sleep, gratitude)
- Therapeutic approach: mindfulness, body scan, loving-kindness, CBT-style
- Background selection: rain, waves, chimes, forest sounds, or silent
- Narrator options: multiple AI voices (gender, accent, pace)
- Customizable: specific phrasings, religious preferences, cultural context
- Progressive: multi-part series that adapts week-over-week
- Work scenario: desk meditation, walking meditation, pre-meeting calm
- Effectiveness: adapts based on user feedback

**User Story:**
- As someone with very specific meditation needs, I want to request "a 7-minute body scan for anxiety with female voice" and receive exactly what I requested

**Acceptance Criteria:**
- [ ] Generate meditation 3-15 minutes within 15 seconds
- [ ] Choose therapeutic approach: mindfulness, body scan, metta, CBT
- [ ] Background sounds: rain, ocean, chimes, birds, or silence
- [ ] Voice options: 5 different AI narrator voices (male, female, various accents)
- [ ] Customizable pacing: slow/medium/fast options
- [ ] Specific scenario: "meeting stress meditation", "commute meditation"
- [ ] Multi-part series: 7-day sequence, each different but cohesive
- [ ] User feedback: "helpful" → similar content generated; "not helpful" style adjusted

**FR3: Breathing Exercise Generator**
- Pattern variety: 4-4-4 box, 4-7-8, 4-2-4-2 square, alternate nostril
- Customizable: specific counts, hold durations
- Audio narration: guided counts or silent visual/haptic
- Visualization: watchOS/Garmin visual breathing guide
- Integration: adapts to biometric data
- Context: before meetings, sleep, anxiety, energy boost versions
- Speed control: slow/medium/fast pace options
- User-designed: "I want 5-3-5-3 pattern for 3 minutes"

**User Story:**
- As someone who likes specific breathing pattern, I want to customize exact timings so that I can follow exact pattern I was taught

**Acceptance Criteria:**
- [ ] Generate any breathing pattern (e.g., 4-7-8 for sleep, 4-4-4 for focus)
- [ ] Customize inhalation/hold/exhalation individually
- [ ] Visual cue: expanding/contracting circle syncs to pace
- [ ] Haptic guidance: Watch tap pattern matches breathing (privacy mode)
- [ ] Audio counting: optional verbal count-in with voice
- [ ] Context-adaptive: pre-meeting, sleep-onset, energy restoration
- [ ] Speed adjustment: slow/fast without restarting exercise
- [ ] User-designed patterns: custom inputs accepted

**FR4: Grounding Technique Generator**
- 5-4-3-2-1 senses guide: generates unique sensory observations
- Grounding scenarios: anxiety, panic, dissociation, overwhelm
- Progressive: starts with easier senses, moves to detailed
- User-guided: specify current location or let AI infer
- Cultural adaptation: appropriate examples for user's context
- Interactive: tap each sense as you complete (visual feedback)
- Variations: grounding by taste, touch, movement when appropriate
- Quick (2 min) vs thorough (5 min) versions

**User Story:**
- As someone with panic attacks, I want personalized 5-4-3-2-1 grounding so that I can refocus away from panic thoughts quickly

**Acceptance Criteria:**
- [ ] Generate unique observations for each sense (never same twice)
- [ ] Context-aware: indoor vs outdoor scenario different
- [ ] Progressive: starts with 5 things you see (easier), ends with 1 thing you taste (harder)
- [ ] Interactive: tap each item as identified for kinesthetic engagement
- [ ] Appropriate suggestions: "feel texture of your shirt" not "feel grass" if in office
- [ ] Adaptable: can specify panic vs overwhelm vs dissociation
- [ ] Quick 2-minute version available (3 senses only)
- [ ] Cultural sensitivity: examples relatable to user

**FR5: Mindfulness Prompt Generator**
- Daily mindfulness prompts: "Notice three moments of comfort today"
- Contextual: morning, mid-day, evening different tones
- Observing practice: awareness without judgment
- Mindful moment: pause and notice current experience
- Present-focused: anchors in here/now
- Culturally adaptable: secular, spiritual, religious contexts supported
- Specific themes: eating, walking, washing hands, transitions
- Integration suggestions: at red lights, before meals, when waking

**User Story:**
- As someone trying to practice mindfulness daily, I want fresh prompts so that I don't repeat same observations that become routine

**Acceptance Criteria:**
- [ ] Unique prompt generated each day based on user preferences
- [ ] Context-aware: morning = intention-setting, evening = reflection
- [ ] Practice duration: 30 seconds - 3 minutes
- [ ] Observing focus: "notice sensations in your hands" not "feel good"
- [ ] Present anchoring: "right here, right now" language
- [ ] Cultural preferences: secular default, religious/spiritual options available
- [ ] Integration suggestions: prompts tied to daily activities
- [ ] Notification reminder: gentle push at specified times

**FR6: Cognitive Restructuring/CBT Exercise Generation**
- Thought record: personalized worksheets based on user's situation
- Challenge distorted thinking: specific questions for identified distortion
- Adaptation: "You mentioned black-and-white thinking. Let's explore..."
- Re-framing: alternative interpretations based on context
- Balance: find middle ground cognitions
- Behavioral experiments: design based on user's avoidance patterns
- Graded exposure: progressive hierarchy generation for phobias
- Effectiveness: user rates helpfulness for adaptive prompt style

**User Story:**
- As someone practicing CBT, I want thought records adapted to my specific situation so that I can complete exercises most relevant

**Acceptance Criteria:**
- [ ] Identifies cognitive distortion type: catastrophizing, mind reading
- [ ] Prompts specific challenging questions for that distortion
- [ ] Provides alternative interpretations relevant to context
- [ ] Finds balanced thoughts (not just "think positive")
- [ ] Suggests behavioral experiments if avoidance identified
- [ ] Graded exposure: generates progressive hierarchy for phobias
- [ ] Adapts difficulty based on user success/failure with previous exercises
- [ ] User rates helpfulness: system learns prompt style preferences

**FR7: Journaling & Reflection Prompts**
- Daily reflection prompts: uniquely tailored to recent entries
- Follow-up prompts: build on previous day's entry
- Gratitude prompts: novel, specific, not generic
- Emotion processing: "You mentioned anxiety. Explore physical sensations..."
- Values-based: align with expressed values
- Progress review: prompt reflection on how far come
- Pattern insight: notice repeated themes over weeks
- Writing guide: structure reflection (not therapy)

**User Story:**
- As someone who journals regularly, I want fresh prompts that build on previous entries so that I don't rehash same topic but progress deeper

**Acceptance Criteria:**
- [ ] Prompts reference recent entries: "Last week you mentioned struggling with..."
- [ ] Follow-up questions: build each day on previous
- [ ] Gratitude prompts: specific, novel (not "what are you grateful for?")
- [ ] When anxiety mentioned: prompt physical sensation observation
- [ ] Values alignment: based on values assessment or previous expression
- [ ] Periodic review prompts: "How has this improved over last month?"
- [ ] Pattern insight: "You often write about work stress on Sundays..."
- [ ] Writing guidance: prompts structured (not vague)
- [ ] Not therapy: avoids deep trauma processing, focuses on present

### Audio Generation and Narration

**FR8: Text-to-Speech/Voice Synthesis**
- Voice variety: 10+ AI voices (ElevenLabs/Play.ht integration)
- Natural cadence: breathing pauses, natural rhythm, not robotic
- Emotional tone: calm, soothing, energetic options
- Language: English primarily, expand to 20+ languages
- Pace control: slow/medium/fast (75%, 100%, 125% speed)
- Consistency: same voice for continuity across sessions
- Custom voice: optional recording of user's own voice guide
- License compliance: proper commercial licensing for voice use
- Audio quality: 44.1kHz/128kbps minimum

**User Story:**
- As someone sensitive to voice, I want natural-sounding narration so that I find guided exercises pleasant, not annoying

**Acceptance Criteria:**
- [ ] 10+ high-quality voices (including diverse languages)
- [ ] Natural cadence: breathing pauses every 3-4 phrases
- [ ] Emotional tone varies: calm for anxiety, soothing for sleep, energizing for morning
- [ ] English + primary languages: Spanish, French, German, Japanese
- [ ] Pace sliders: 0.75x, 1x, 1.25x, 1.5x speed
- [ ] User selects preferred voice (persistent across sessions)
- [ ] Background consistency: same voice within multi-part series
- [ ] Audio quality: 44.1kHz, 128kbps minimum bitrate
- [ ] Proper licensing: commercial licenses for all voices used

**FR9: Dynamic Audio Assembly**
- Seamless segments: concatenate generated segments without gaps
- Audio mixing: background sounds + voice narration
- Volume balancing: voice prominent, background subtle
- Gapless transitions: no audible glitches between segments
- Real-time assembly: 15-second delay for on-demand content
- Pre-generation: batch generate popular patterns ahead of time
- Quality control: automated checks for audio artifacts
- Streaming: progressive download for long sessions

**User Story:**
- As someone impatient for content, I want generated audio delivered quickly so that I don't wait too long after requesting

**Acceptance Criteria:**
- [ ] Real-time assembly completes within 15 seconds for 10-min content
- [ ] Pre-generated popular patterns load instantly from cache
- [ ] Background + voice mixed seamlessly
- [ ] Volume levels balanced: voice at -6dB, background at -18dB
- [ ] Gapless: cross-fade between segments (0.5 seconds max)
- [ ] Quality check: automated loudness normalization (target -16 LUFS)
- [ ] Streaming: progressive download starts playing after 5 seconds
- [ ] Offline: generates and caches user's favorite patterns

**FR10: Content Filters and Guardrails**
- Therapeutic language: appropriate for mental health support
- Pacing: appropriate for context (sleep = slower, energizing = moderate)
- No stigmatizing language: person-first, non-pathologizing
- Cultural sensitivity: avoid inappropriate spiritual/religious references
- Trigger warnings: alert if generated content contains potentially distressing themes
- Clinical review: baseline models reviewed by licensed clinicians
- User warnings: "generated content, not substitute for therapy"
- Reporting: user can flag problematic generated content
- Continuous improvement: learn from user flags

**User Story:**
- As someone using for mental health, I want content to be therapeutically appropriate and safe so that I can trust it's not misleading or harmful

**Acceptance Criteria:**
- [ ] All generated content reviewed by clinical psychologist initially
- [ ] Language filters prevent stigmatizing terminology
- [ ] Pacing varies contextually: sleep = slower, anxiety = gentle, energizing = moderate
- [ ] Cultural sensitivity: respects user's cultural background (asked in profile)
- [ ] Trigger warnings displayed before content with heavy themes
- [ ] User disclaimer: "generated content; not therapy"
- [ ] Flagging: "Report inappropriate content" button
- [ ] Learning: flagged content improves model (no user-specific adjustment)
- [ ] Clinical review of aggregate flagged data monthly

### Quality Control and Validation

**FR11: Content Validation System**
- Clinical approval: baseline model outputs reviewed by psychologist
- Consistency check: generated content matches user's request
- Safety scan: AI filter for self-harm, inappropriate content
- Quality scoring: estimate generation quality (confidence score)
- User rating: 1-5 stars for generated content (improves model)
- A/B testing: compare human vs. AI content engagement
- Red flags: high crisis language triggers human review
- Continuous training: fine-tune with user feedback and ratings
- Fallback: if generation fails, serve best-match human content
- Transparency: distinguish generated vs. human-curated content

**User Story:**
- As someone cautious about AI, I want clear quality indicators and human oversight so that I can trust content is appropriate and effective

**Acceptance Criteria:**
- [ ] Human psychology review of 500+ generations before launch
- [ ] Consistency check: does 90% match user's request (user survey)
- [ ] Safety scan: crisis language flagged for human review
- [ ] Quality scoring: 1-10 confidence shown to user
- [ ] User ratings: average >3.5/5 indicates acceptable quality
- [ ] A/B testing: engagement rates compare favorably to human (within 80%)
- [ ] Red flag: crisis generation triggers immediate human escalation
- [ ] Model updates: monthly with aggregate user feedback
- [ ] Clear labeling: "AI Generated" badge on generated content
- [ ] Fallback: offer to browse human content if generation unsatisfactory

### Cross-Domain Generation

**FR12: Multi-Domain Content Orchestration**
- Sleep story + breathing: integrated session (story transitions to breathing)
- Meditation + journaling: meditative prompt then journaling
- Exercise + gratitude: physical activity then reflection on experience
- Workday: morning prep, midday check-in, evening reflection sequence
- Thematic: anxiety week (all content focused on anxiety management)
- Personal crisis: emergency kit content specific to event
- Multi-day programs: 7-day themed generated sequences
- Cultural: content adapts to cultural context, holidays, traditions

**User Story:**
- As someone dealing with workplace burnout, I want a week-long program with generated content all aligned to this theme so that every piece supports my recovery

**Acceptance Criteria:**
- [ ] Content across categories (story + meditation) thematically aligned
- [ ] User can request theme: "This week, help with work stress"
- [ ] Multi-day sequences: 7-day cohesive generated content
- [ ] Integrated sessions: sleep story that transitions to breathing
- [ ] Workday sequence: morning routine, midday check-in, evening reflection
- [ ] Crisis-specific: recent loss/grief → all content sensitive to context
- [ ] Cultural adaptation: content adjusts for user-specified cultural context
- [ ] Consistent tone: same voice, pacing, style across sequence
- [ ] Tracking: logs if user completed sequence
- [ ] Continuity: next session references previous

### Business Model Integration

**FR13: Free vs. Premium Generation Tiers**
- Free tier: limited daily generations (3 per day)
- Premium: unlimited generations, all voice options
- Cost model: estimate per-generation cost ($0.01-0.05 per generation)
- Credit system: premium users get monthly generation credits (unused can roll over)
- B2B: enterprise customers branded content generation
- API access: therapist partners can generate for clients (B2B2C)
- Bundling: generate premium content packs for specific needs
- Licensing: commercial usage rights for enterprise content

**User Story:**
- As a premium user, I want unlimited generations so that I can create as much personalized content as I need, limited only by my creativity

**Acceptance Criteria:**
- [ ] Free users: 3 generations per day, limited voice options (3 voices)
- [ ] Premium users: unlimited generations, all 10+ voices available
- [ ] Cost control: average $0.03 per generation (estimating usage)
- [ ] Monthly credit: premium gets 1,000 generation credits (resets monthly)
- [ ] Unused credits: max 2,000 can roll over
- [ ] B2B API: enterprise can brand content (logo, intro/outro)
- [ ] Therapist generation: licensed therapist can request content for clients
- [ ] Special packs: "Sleep story bundle" 10 stories focused on specific theme
- [ ] Commercial rights: premium includes personal use, enterprise includes branding

**FR14: Content Marketplace and Creator Economy**
- Human-generated content library: therapists, meditation teachers contribute
- Hybrid model: human-curated base + AI personalized variants
- Revenue share: creators earn 70% of associated premium revenue
- Quality tiers: verified creators, licensed therapists get higher ranking
- Reviews: user ratings and reviews for human content
- AI enhancement: human content can be used as seed for generation
- Discovery: browse by creator, theme, rating, length
- Licensing: proper content licensing and attribution
- Promotion: popular human creators featured in app

**User Story:**
- As a meditation teacher or therapist, I want to contribute content and earn revenue share so that I can monetize my expertise through platform

**Acceptance Criteria:**
- [ ] Creator portal: upload audio content, set licensing terms
- [ ] Human-curated library: therapist-generated content available
- [ ] AI seeds: generate variations on human-created templates
- [ ] Revenue split: 70% creator / 30% platform on direct purchases
- [ ] Subscription revenue: creators earn % of subscriptions based on listen time
- [ ] Quality verification: licensed therapists, certified meditation teachers verified
- [ ] Browse: search by creator name, specialization, rating
- [ ] Licensing: clear attribution and commercial rights
- [ ] Promotion: featured creators on main browse screen
- [ ] Creator tools: generate subtitles, translations for content

## Technical Specifications

### Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                      iOS App (SwiftUI)                         │
│  ┌─────────────┐   ┌──────────────┐   ┌────────────────────┐  │
│  │ Request UI  │   │ Audio Player │   │ Preferences        │  │
│  │ & Library   │   │ Integration  │   │ Management         │  │
│  └──────┬──────┘   └──────┬───────┘   └────────┬───────────┘  │
│         │                  │                    │              │
│         └──────────────────┼────────────────────┘              │
│                            ▼                                     │
│                    ┌──────────────┐                            │
│                    │   User Auth  │                            │
│                    │ Verification │                            │
│                    └──────┬───────┘                            │
│                           │                                    │
└───────────────────────────┼────────────────────────────────────┘
                            │ HTTPS
┌───────────────────────────▼────────────────────────────────────┐
│                     Supabase Edge Functions                      │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ Content     │  │ Audio        │  │ Voice Synth        │  │
│  │ Generation  │  │ Processing   │  │ (ElevenLabs/Play)  │  │
│  │  (GPT-4)    │  │  (FFmpeg)    │  │  Integration       │  │
│  └──────┬──────┘  └──────┬───────┘  └────────┬───────────┘  │
│         │                  │                    │              │
│         └──────────────────┼────────────────────┘              │
│                            ▼                                     │
│                    ┌──────────────┐                            │
│                    │  PostgreSQL  │                            │
│                    │   Database   │                            │
│                    └──────────────┘                            │
│                                                     │
│  Generative AI Partners:                                        │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ OpenAI GPT │  │  Anthropic   │  │ Voice APIs   │          │
│  │    (4)     │  │   (Claude)   │  │  ElevenLabs  │          │
│  └────────────┘  └──────────────┘  │   Play.ht    │          │
│                                     └──────────────┘          │
└────────────────────────────────────────────────────────────────┘

**Edge Integration:**
- Content generated via external LLM calls
- Audio synthesized through voice partner APIs
- Batch processing of pre-generated popular patterns
- On-demand generation for custom user requests
- Cached results for 24-hour reuse

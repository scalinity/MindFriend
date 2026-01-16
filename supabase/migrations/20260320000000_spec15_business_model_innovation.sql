-- Spec 15: Business Model Innovation
-- Comprehensive monetization schema with subscriptions, gifting, promo codes, enterprise, HSA/FSA
-- Timestamp: 2026-01-16T10:00:00Z

-- ============================================================================
-- SUBSCRIPTION PLANS (Product Catalog)
-- ============================================================================

CREATE TABLE IF NOT EXISTS subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,

    -- Pricing
    price_cents INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    billing_period TEXT NOT NULL, -- 'monthly' | 'yearly' | 'lifetime' | 'custom'
    billing_period_months INTEGER, -- NULL for lifetime

    -- Plan type
    plan_type TEXT NOT NULL, -- 'individual' | 'family' | 'enterprise' | 'gift'
    max_seats INTEGER DEFAULT 1, -- 1 for individual, 6 for family, NULL for enterprise

    -- Features (JSONB allows flexible feature set)
    features JSONB NOT NULL DEFAULT '{}',
    ai_chat_limit INTEGER, -- NULL = unlimited
    exercise_limit INTEGER, -- NULL = unlimited

    -- App Store configuration
    app_store_product_id TEXT,
    play_store_product_id TEXT,

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_visible BOOLEAN NOT NULL DEFAULT true, -- Show on paywall

    -- Regional pricing: {"EU": 899, "IN": 299, ...}
    regional_prices JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_app_store_id UNIQUE(app_store_product_id),
    CONSTRAINT valid_billing_period CHECK (billing_period IN ('monthly', 'yearly', 'lifetime', 'custom')),
    CONSTRAINT valid_plan_type CHECK (plan_type IN ('individual', 'family', 'enterprise', 'gift')),
    CONSTRAINT max_seats_positive CHECK (max_seats IS NULL OR max_seats > 0),
    CONSTRAINT limits_non_negative CHECK ((ai_chat_limit IS NULL OR ai_chat_limit >= 0) AND (exercise_limit IS NULL OR exercise_limit >= 0))
);

CREATE INDEX idx_subscription_plans_type_active ON subscription_plans(plan_type, is_active) WHERE is_active = true;
CREATE INDEX idx_subscription_plans_visible ON subscription_plans(is_visible) WHERE is_visible = true;
CREATE INDEX idx_subscription_plans_app_store ON subscription_plans(app_store_product_id) WHERE app_store_product_id IS NOT NULL;

-- ============================================================================
-- PROMO CODES & REDEMPTIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS promo_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,

    -- Discount specifics
    discount_type TEXT NOT NULL, -- 'percent' | 'fixed' | 'trial_extension'
    discount_value INTEGER NOT NULL, -- Percent (0-100) or cents
    trial_extension_days INTEGER, -- For trial_extension type

    -- Restrictions
    applicable_plans UUID[], -- NULL = all plans
    min_billing_period TEXT, -- 'monthly' | 'yearly' - minimum billing period to apply
    first_time_only BOOLEAN NOT NULL DEFAULT true, -- Only for first subscription

    -- Limits
    max_uses INTEGER, -- NULL = unlimited
    uses_count INTEGER NOT NULL DEFAULT 0,
    max_uses_per_user INTEGER DEFAULT 1,

    -- Validity period
    valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Tracking
    campaign_name TEXT,
    affiliate_id UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_discount_type CHECK (discount_type IN ('percent', 'fixed', 'trial_extension')),
    CONSTRAINT valid_percent CHECK ((discount_type != 'percent') OR (discount_value >= 0 AND discount_value <= 100)),
    CONSTRAINT valid_fixed CHECK ((discount_type != 'fixed') OR discount_value >= 0),
    CONSTRAINT valid_trial_ext CHECK ((discount_type != 'trial_extension') OR trial_extension_days > 0),
    CONSTRAINT max_uses_positive CHECK (max_uses IS NULL OR max_uses > 0)
);

CREATE INDEX idx_promo_codes_code ON promo_codes(code);
CREATE INDEX idx_promo_codes_active_valid ON promo_codes(is_active, valid_from, valid_until) WHERE is_active = true;
CREATE INDEX idx_promo_codes_campaign ON promo_codes(campaign_name) WHERE campaign_name IS NOT NULL;

-- Track promo code usage per user (for max_uses_per_user constraint)
CREATE TABLE IF NOT EXISTS promo_code_redemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promo_code_id UUID NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,

    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    discount_applied_cents INTEGER NOT NULL,

    CONSTRAINT unique_user_promo UNIQUE(promo_code_id, user_id)
);

CREATE INDEX idx_promo_redemptions_code ON promo_code_redemptions(promo_code_id);
CREATE INDEX idx_promo_redemptions_user ON promo_code_redemptions(user_id);

-- ============================================================================
-- GIFT SUBSCRIPTIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS gift_subscriptions_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchaser_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    purchaser_email TEXT NOT NULL,

    -- Gift details
    plan_id UUID NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
    duration_months INTEGER NOT NULL,
    price_cents INTEGER NOT NULL,

    -- Recipient details
    recipient_email TEXT NOT NULL,
    recipient_name TEXT,
    personal_message TEXT,

    -- Delivery
    delivery_date DATE NOT NULL,
    delivered_at TIMESTAMPTZ,
    delivery_method TEXT NOT NULL DEFAULT 'email', -- 'email' | 'in_app'

    -- Redemption
    redemption_code TEXT NOT NULL UNIQUE,
    redeemed_at TIMESTAMPTZ,
    redeemed_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Payment
    payment_intent_id TEXT, -- Stripe PaymentIntent ID
    transaction_id TEXT, -- App Store or alternative

    -- Status
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'delivered' | 'redeemed' | 'expired' | 'refunded'
    expires_at TIMESTAMPTZ NOT NULL, -- Redemption deadline (default: 1 year from creation)

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_status CHECK (status IN ('pending', 'delivered', 'redeemed', 'expired', 'refunded')),
    CONSTRAINT valid_delivery CHECK (delivery_method IN ('email', 'in_app')),
    CONSTRAINT duration_positive CHECK (duration_months > 0)
);

-- Note: Rename old gift_subscriptions to _legacy if exists, or just use v2 as primary
CREATE INDEX idx_gift_code ON gift_subscriptions_v2(redemption_code);
CREATE INDEX idx_gift_purchaser ON gift_subscriptions_v2(purchaser_user_id);
CREATE INDEX idx_gift_recipient ON gift_subscriptions_v2(recipient_email);
CREATE INDEX idx_gift_redeemed_user ON gift_subscriptions_v2(redeemed_by_user_id);
CREATE INDEX idx_gift_status_expires ON gift_subscriptions_v2(status, expires_at);

-- ============================================================================
-- ENTERPRISE ACCOUNTS (B2B Customers)
-- ============================================================================

CREATE TABLE IF NOT EXISTS enterprise_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE, -- For SSO/URLs

    -- Contacts
    admin_email TEXT NOT NULL,
    billing_email TEXT,

    -- Contract terms
    contract_start DATE NOT NULL,
    contract_end DATE,
    seat_count INTEGER NOT NULL,
    price_per_seat_cents INTEGER NOT NULL,
    billing_period TEXT NOT NULL, -- 'monthly' | 'yearly'

    -- Features & configuration
    features JSONB NOT NULL DEFAULT '{}',
    custom_branding JSONB, -- {"logo_url": "...", "primary_color": "..."}
    sso_config JSONB, -- {"provider": "okta", "metadata_url": "..."}

    -- Status
    status TEXT NOT NULL DEFAULT 'active', -- 'active' | 'suspended' | 'churned'

    -- Stripe integration
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_status CHECK (status IN ('active', 'suspended', 'churned')),
    CONSTRAINT valid_billing CHECK (billing_period IN ('monthly', 'yearly')),
    CONSTRAINT seat_count_positive CHECK (seat_count > 0),
    CONSTRAINT price_positive CHECK (price_per_seat_cents >= 0)
);

CREATE INDEX idx_enterprise_slug ON enterprise_accounts(slug);
CREATE INDEX idx_enterprise_admin ON enterprise_accounts(admin_email);
CREATE INDEX idx_enterprise_status ON enterprise_accounts(status);

-- ============================================================================
-- ENTERPRISE EMPLOYEES
-- ============================================================================

CREATE TABLE IF NOT EXISTS enterprise_employees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enterprise_account_id UUID NOT NULL REFERENCES enterprise_accounts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Employee info
    email TEXT NOT NULL,
    employee_id TEXT, -- External employee ID from HRIS
    department TEXT,

    -- Status tracking
    status TEXT NOT NULL DEFAULT 'invited', -- 'invited' | 'active' | 'deactivated'
    invited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activated_at TIMESTAMPTZ,
    deactivated_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_status CHECK (status IN ('invited', 'active', 'deactivated')),
    CONSTRAINT unique_enterprise_email UNIQUE(enterprise_account_id, email)
);

CREATE INDEX idx_enterprise_employees_account ON enterprise_employees(enterprise_account_id);
CREATE INDEX idx_enterprise_employees_user ON enterprise_employees(user_id);
CREATE INDEX idx_enterprise_employees_email ON enterprise_employees(email);
CREATE INDEX idx_enterprise_employees_status ON enterprise_employees(enterprise_account_id, status);

-- ============================================================================
-- HSA/FSA ELIGIBILITY & RECORDS
-- ============================================================================

CREATE TABLE IF NOT EXISTS hsa_fsa_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,

    -- Eligibility status
    is_hsa_eligible BOOLEAN NOT NULL DEFAULT true,
    is_fsa_eligible BOOLEAN NOT NULL DEFAULT true,

    -- Letter of Medical Necessity
    lomn_generated_at TIMESTAMPTZ,
    lomn_url TEXT,

    -- Receipt for reimbursement
    receipt_generated_at TIMESTAMPTZ,
    receipt_url TEXT,
    receipt_amount_cents INTEGER,

    -- IRS compliance codes
    merchant_category_code TEXT DEFAULT '8099', -- Health services (IRS code)
    diagnosis_codes TEXT[], -- ICD-10 codes if applicable

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT receipt_amount_positive CHECK (receipt_amount_cents IS NULL OR receipt_amount_cents >= 0)
);

CREATE INDEX idx_hsa_fsa_user ON hsa_fsa_records(user_id);
CREATE INDEX idx_hsa_fsa_subscription ON hsa_fsa_records(subscription_id) WHERE subscription_id IS NOT NULL;

-- ============================================================================
-- REVENUE EVENTS (For Analytics & Reporting)
-- ============================================================================

CREATE TABLE IF NOT EXISTS revenue_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,

    -- Event categorization
    event_type TEXT NOT NULL, -- 'purchase' | 'renewal' | 'upgrade' | 'downgrade' | 'refund' | 'chargeback' | 'gift_purchase' | 'gift_redeemed'
    event_date DATE NOT NULL,

    -- Financial details
    amount_cents INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    amount_usd_cents INTEGER NOT NULL, -- Normalized for reporting

    -- Attribution
    source TEXT, -- 'organic' | 'paid' | 'referral' | 'enterprise' | 'gift'
    campaign TEXT,
    promo_code_id UUID REFERENCES promo_codes(id) ON DELETE SET NULL,

    -- Payment provider
    payment_provider TEXT NOT NULL, -- 'app_store' | 'play_store' | 'stripe' | 'enterprise' | 'gift'
    external_transaction_id TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_event_type CHECK (event_type IN ('purchase', 'renewal', 'upgrade', 'downgrade', 'refund', 'chargeback', 'gift_purchase', 'gift_redeemed')),
    CONSTRAINT valid_source CHECK (source IS NULL OR source IN ('organic', 'paid', 'referral', 'enterprise', 'gift')),
    CONSTRAINT valid_provider CHECK (payment_provider IN ('app_store', 'play_store', 'stripe', 'enterprise', 'gift')),
    CONSTRAINT amount_positive CHECK (amount_cents >= 0),
    CONSTRAINT usd_positive CHECK (amount_usd_cents >= 0)
);

CREATE INDEX idx_revenue_events_date ON revenue_events(event_date);
CREATE INDEX idx_revenue_events_user ON revenue_events(user_id);
CREATE INDEX idx_revenue_events_type ON revenue_events(event_type);
CREATE INDEX idx_revenue_events_promo ON revenue_events(promo_code_id) WHERE promo_code_id IS NOT NULL;

-- ============================================================================
-- ENTERPRISE ANALYTICS (Aggregated, Privacy-Preserving)
-- ============================================================================

CREATE TABLE IF NOT EXISTS enterprise_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enterprise_account_id UUID NOT NULL REFERENCES enterprise_accounts(id) ON DELETE CASCADE,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,

    -- Engagement (aggregated, never per-user)
    active_users INTEGER NOT NULL,
    total_sessions INTEGER NOT NULL,
    avg_session_duration_seconds INTEGER,

    -- Feature usage (aggregated counts)
    ai_chats_count INTEGER NOT NULL,
    exercises_completed INTEGER NOT NULL,
    quests_completed INTEGER NOT NULL,
    moods_logged INTEGER NOT NULL,

    -- Trends & scoring
    engagement_score DECIMAL(5, 2), -- 0-100 scale
    wellness_trend TEXT, -- 'improving' | 'stable' | 'declining'

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_enterprise_period UNIQUE(enterprise_account_id, period_start),
    CONSTRAINT valid_trend CHECK (wellness_trend IS NULL OR wellness_trend IN ('improving', 'stable', 'declining')),
    CONSTRAINT valid_score CHECK (engagement_score IS NULL OR (engagement_score >= 0 AND engagement_score <= 100))
);

CREATE INDEX idx_enterprise_analytics_account ON enterprise_analytics(enterprise_account_id);
CREATE INDEX idx_enterprise_analytics_period ON enterprise_analytics(period_start, period_end);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Plans are publicly readable (for displaying paywall)
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Plans readable by all authenticated users"
    ON subscription_plans FOR SELECT
    USING (is_active = true);

-- Promo codes - readable for validation, not for discovering all codes
ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active promo codes readable for validation"
    ON promo_codes FOR SELECT
    USING (is_active = true);

-- Promo redemptions - users see only their own
ALTER TABLE promo_code_redemptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own promo redemptions"
    ON promo_code_redemptions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "System can insert promo redemptions"
    ON promo_code_redemptions FOR INSERT
    WITH CHECK (true); -- Service role can insert

-- Gift subscriptions - purchasers see their gifts, recipients see received gifts
ALTER TABLE gift_subscriptions_v2 ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Purchasers view own gifts"
    ON gift_subscriptions_v2 FOR SELECT
    USING (purchaser_user_id = auth.uid() OR purchaser_email = (SELECT email FROM auth.users WHERE id = auth.uid()));

CREATE POLICY "Recipients view gifts sent to them"
    ON gift_subscriptions_v2 FOR SELECT
    USING (recipient_email = (SELECT email FROM auth.users WHERE id = auth.uid()));

CREATE POLICY "System can update gift redemption"
    ON gift_subscriptions_v2 FOR UPDATE
    USING (true); -- Service role manages redemptions

-- Enterprise accounts - only admins see their account
ALTER TABLE enterprise_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enterprise admins manage own account"
    ON enterprise_accounts FOR ALL
    USING (admin_email = (SELECT email FROM auth.users WHERE id = auth.uid()));

-- Enterprise employees - admins manage, employees see own status
ALTER TABLE enterprise_employees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enterprise admins manage employees"
    ON enterprise_employees FOR ALL
    USING (enterprise_account_id IN (
        SELECT id FROM enterprise_accounts WHERE admin_email = (
            SELECT email FROM auth.users WHERE id = auth.uid()
        )
    ));

CREATE POLICY "Employees view own record"
    ON enterprise_employees FOR SELECT
    USING (user_id = auth.uid());

-- HSA/FSA records - users see only their own
ALTER TABLE hsa_fsa_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own HSA/FSA records"
    ON hsa_fsa_records FOR SELECT
    USING (auth.uid() = user_id);

-- Revenue events - internal only (not exposed via RLS, used by backend)
ALTER TABLE revenue_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Revenue events - service role only"
    ON revenue_events FOR ALL
    USING (false); -- No direct user access

-- Enterprise analytics - admins see their account's analytics
ALTER TABLE enterprise_analytics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enterprise admins view own analytics"
    ON enterprise_analytics FOR SELECT
    USING (enterprise_account_id IN (
        SELECT id FROM enterprise_accounts WHERE admin_email = (
            SELECT email FROM auth.users WHERE id = auth.uid()
        )
    ));

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Update updated_at timestamp on subscription_plans
CREATE OR REPLACE FUNCTION update_subscription_plans_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER subscription_plans_updated_at
    BEFORE UPDATE ON subscription_plans
    FOR EACH ROW
    EXECUTE FUNCTION update_subscription_plans_updated_at();

-- Update updated_at timestamp on enterprise_accounts
CREATE OR REPLACE FUNCTION update_enterprise_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enterprise_accounts_updated_at
    BEFORE UPDATE ON enterprise_accounts
    FOR EACH ROW
    EXECUTE FUNCTION update_enterprise_accounts_updated_at();

-- Update updated_at timestamp on enterprise_employees
CREATE OR REPLACE FUNCTION update_enterprise_employees_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enterprise_employees_updated_at
    BEFORE UPDATE ON enterprise_employees
    FOR EACH ROW
    EXECUTE FUNCTION update_enterprise_employees_updated_at();

-- Increment promo code uses_count when redeemed
CREATE OR REPLACE FUNCTION increment_promo_uses()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE promo_codes
    SET uses_count = uses_count + 1
    WHERE id = NEW.promo_code_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER promo_redemption_increment_uses
    AFTER INSERT ON promo_code_redemptions
    FOR EACH ROW
    EXECUTE FUNCTION increment_promo_uses();

-- ============================================================================
-- SEED DATA (Optional - adjust per your needs)
-- ============================================================================

-- Insert default subscription plans (if not exists)
INSERT INTO subscription_plans (
    name, description, price_cents, currency, billing_period, billing_period_months,
    plan_type, max_seats, features, ai_chat_limit, exercise_limit,
    app_store_product_id, is_active, is_visible
) VALUES
    (
        'Free',
        'Limited access - perfect for trying MindFriend',
        0,
        'USD',
        'custom',
        NULL,
        'individual',
        1,
        '{"unlimited_chat": false, "unlimited_exercises": false, "premium_content": false, "priority_support": false, "family_sharing": false, "offline_mode": false, "custom_themes": false, "advanced_insights": false}',
        3,
        5,
        NULL,
        true,
        true
    ),
    (
        'Premium Monthly',
        'Unlimited access, month-to-month',
        999,
        'USD',
        'monthly',
        1,
        'individual',
        1,
        '{"unlimited_chat": true, "unlimited_exercises": true, "premium_content": true, "priority_support": true, "family_sharing": false, "offline_mode": true, "custom_themes": true, "advanced_insights": true}',
        NULL,
        NULL,
        'com.mindfriend.premium.monthly',
        true,
        true
    ),
    (
        'Premium Annual',
        'Best value - save 2 months',
        7999,
        'USD',
        'yearly',
        12,
        'individual',
        1,
        '{"unlimited_chat": true, "unlimited_exercises": true, "premium_content": true, "priority_support": true, "family_sharing": false, "offline_mode": true, "custom_themes": true, "advanced_insights": true}',
        NULL,
        NULL,
        'com.mindfriend.premium.annual',
        true,
        true
    ),
    (
        'Premium Lifetime',
        'One-time purchase, unlimited forever',
        29999,
        'USD',
        'lifetime',
        NULL,
        'individual',
        1,
        '{"unlimited_chat": true, "unlimited_exercises": true, "premium_content": true, "priority_support": true, "family_sharing": false, "offline_mode": true, "custom_themes": true, "advanced_insights": true}',
        NULL,
        NULL,
        'com.mindfriend.premium.lifetime',
        true,
        true
    ),
    (
        'Family Annual',
        'Up to 6 family members',
        11999,
        'USD',
        'yearly',
        12,
        'family',
        6,
        '{"unlimited_chat": true, "unlimited_exercises": true, "premium_content": true, "priority_support": true, "family_sharing": true, "offline_mode": true, "custom_themes": true, "advanced_insights": true}',
        NULL,
        NULL,
        'com.mindfriend.family.annual',
        true,
        true
    )
ON CONFLICT DO NOTHING;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- All tables, indexes, policies, and functions created successfully.
-- Run: supabase db push

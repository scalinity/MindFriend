-- Migration: Create subscription_plans table for Gift/Paywall functionality
-- Required for BillingService.loadAvailablePlans()

-- ============================================================================
-- SUBSCRIPTION PLANS TABLE
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
    plan_type TEXT NOT NULL, -- 'individual' | 'couples' | 'family' | 'enterprise' | 'gift'
    max_seats INTEGER DEFAULT 1, -- 1 for individual, 2 for couples, 6 for family, NULL for enterprise

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
    CONSTRAINT valid_plan_type CHECK (plan_type IN ('individual', 'couples', 'family', 'enterprise', 'gift')),
    CONSTRAINT max_seats_positive CHECK (max_seats IS NULL OR max_seats > 0),
    CONSTRAINT limits_non_negative CHECK ((ai_chat_limit IS NULL OR ai_chat_limit >= 0) AND (exercise_limit IS NULL OR exercise_limit >= 0))
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_subscription_plans_type_active ON subscription_plans(plan_type, is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_subscription_plans_visible ON subscription_plans(is_visible) WHERE is_visible = true;
CREATE INDEX IF NOT EXISTS idx_subscription_plans_app_store ON subscription_plans(app_store_product_id) WHERE app_store_product_id IS NOT NULL;

-- Enable RLS
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Anyone authenticated can read active, visible plans
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'subscription_plans'
        AND policyname = 'Anyone can read visible plans'
    ) THEN
        CREATE POLICY "Anyone can read visible plans"
            ON subscription_plans
            FOR SELECT
            TO authenticated
            USING (is_active = true AND is_visible = true);
    END IF;
END $$;

-- ============================================================================
-- INSERT DEFAULT SUBSCRIPTION PLANS
-- ============================================================================

-- Individual Monthly - $9.99/month
INSERT INTO subscription_plans (
    name, description, price_cents, currency, billing_period, billing_period_months,
    plan_type, max_seats, features, ai_chat_limit, exercise_limit,
    app_store_product_id, is_active, is_visible
) VALUES (
    'Premium Monthly',
    'Full access to MindFriend Premium features',
    999, 'USD', 'monthly', 1,
    'individual', 1,
    '{"unlimitedChat": true, "priorityResponse": true, "advancedAnalytics": true, "smartReminders": true}'::jsonb,
    NULL, NULL,
    'com.mindfriend.premium.monthly',
    true, true
) ON CONFLICT (app_store_product_id) DO NOTHING;

-- Individual Annual - $59.99/year (50% savings)
INSERT INTO subscription_plans (
    name, description, price_cents, currency, billing_period, billing_period_months,
    plan_type, max_seats, features, ai_chat_limit, exercise_limit,
    app_store_product_id, is_active, is_visible
) VALUES (
    'Premium Annual',
    'Full access to MindFriend Premium features - Best value!',
    5999, 'USD', 'yearly', 12,
    'individual', 1,
    '{"unlimitedChat": true, "priorityResponse": true, "advancedAnalytics": true, "smartReminders": true}'::jsonb,
    NULL, NULL,
    'com.mindfriend.premium.yearly',
    true, true
) ON CONFLICT (app_store_product_id) DO NOTHING;

-- Couples Monthly - $14.99/month
INSERT INTO subscription_plans (
    name, description, price_cents, currency, billing_period, billing_period_months,
    plan_type, max_seats, features, ai_chat_limit, exercise_limit,
    app_store_product_id, is_active, is_visible
) VALUES (
    'Couples Monthly',
    'Premium access for you and your partner',
    1499, 'USD', 'monthly', 1,
    'couples', 2,
    '{"unlimitedChat": true, "priorityResponse": true, "advancedAnalytics": true, "smartReminders": true, "partnerMode": true}'::jsonb,
    NULL, NULL,
    'com.mindfriend.couples.monthly',
    true, true
) ON CONFLICT (app_store_product_id) DO NOTHING;

-- Couples Annual - $89.99/year
INSERT INTO subscription_plans (
    name, description, price_cents, currency, billing_period, billing_period_months,
    plan_type, max_seats, features, ai_chat_limit, exercise_limit,
    app_store_product_id, is_active, is_visible
) VALUES (
    'Couples Annual',
    'Premium access for you and your partner - Best value!',
    8999, 'USD', 'yearly', 12,
    'couples', 2,
    '{"unlimitedChat": true, "priorityResponse": true, "advancedAnalytics": true, "smartReminders": true, "partnerMode": true}'::jsonb,
    NULL, NULL,
    'com.mindfriend.couples.annual',
    true, true
) ON CONFLICT (app_store_product_id) DO NOTHING;

-- Family Monthly - $19.99/month
INSERT INTO subscription_plans (
    name, description, price_cents, currency, billing_period, billing_period_months,
    plan_type, max_seats, features, ai_chat_limit, exercise_limit,
    app_store_product_id, is_active, is_visible
) VALUES (
    'Family Monthly',
    'Premium access for up to 6 family members',
    1999, 'USD', 'monthly', 1,
    'family', 6,
    '{"unlimitedChat": true, "priorityResponse": true, "advancedAnalytics": true, "smartReminders": true, "familySharing": true}'::jsonb,
    NULL, NULL,
    'com.mindfriend.family.monthly',
    true, true
) ON CONFLICT (app_store_product_id) DO NOTHING;

-- Family Annual - $119.99/year
INSERT INTO subscription_plans (
    name, description, price_cents, currency, billing_period, billing_period_months,
    plan_type, max_seats, features, ai_chat_limit, exercise_limit,
    app_store_product_id, is_active, is_visible
) VALUES (
    'Family Annual',
    'Premium access for up to 6 family members - Best value!',
    11999, 'USD', 'yearly', 12,
    'family', 6,
    '{"unlimitedChat": true, "priorityResponse": true, "advancedAnalytics": true, "smartReminders": true, "familySharing": true}'::jsonb,
    NULL, NULL,
    'com.mindfriend.family.annual',
    true, true
) ON CONFLICT (app_store_product_id) DO NOTHING;

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION update_subscription_plans_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS subscription_plans_updated_at ON subscription_plans;
CREATE TRIGGER subscription_plans_updated_at
    BEFORE UPDATE ON subscription_plans
    FOR EACH ROW
    EXECUTE FUNCTION update_subscription_plans_updated_at();

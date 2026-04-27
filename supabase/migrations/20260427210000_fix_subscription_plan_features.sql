-- Migration: Repair subscription_plans.features JSONB so it matches the
-- PlanFeatures Codable contract used by the iOS client (BusinessModels.swift).
--
-- The original seed in 20260124040000_create_subscription_plans_table.sql wrote
-- ad-hoc camelCase keys (unlimitedChat, priorityResponse, advancedAnalytics, ...)
-- that don't match PlanFeatures' snake_case CodingKeys. The Swift decoder needs:
--   unlimited_chat, unlimited_exercises, premium_content, priority_support,
--   family_sharing, offline_mode, custom_themes, advanced_insights
-- All 8 are non-optional Bools, so any missing key fails decoding with
-- "The data couldn't be read because it is missing." and the gift/paywall
-- sheet shows an error instead of plans.
--
-- Semantic note on family_sharing:
-- The flag means "this plan is shareable across multiple users" (i.e. seats > 1),
-- so it is true for couples (2 seats), family (6 seats), and enterprise (unlimited);
-- false for individual and gift. This intentionally diverges from the iOS
-- PlanFeatures.premium static (which sets family_sharing=false because that
-- constant is reused by the individual plan). The flag is currently not gated
-- in any UI — it's a marketing/display flag — so this divergence is documentation,
-- not behavior.

UPDATE subscription_plans
SET features = CASE plan_type
    WHEN 'individual' THEN jsonb_build_object(
        'unlimited_chat',      true,
        'unlimited_exercises', true,
        'premium_content',     true,
        'priority_support',    true,
        'family_sharing',      false,
        'offline_mode',        true,
        'custom_themes',       true,
        'advanced_insights',   true
    )
    WHEN 'couples' THEN jsonb_build_object(
        'unlimited_chat',      true,
        'unlimited_exercises', true,
        'premium_content',     true,
        'priority_support',    true,
        'family_sharing',      true,
        'offline_mode',        true,
        'custom_themes',       true,
        'advanced_insights',   true
    )
    WHEN 'family' THEN jsonb_build_object(
        'unlimited_chat',      true,
        'unlimited_exercises', true,
        'premium_content',     true,
        'priority_support',    true,
        'family_sharing',      true,
        'offline_mode',        true,
        'custom_themes',       true,
        'advanced_insights',   true
    )
    WHEN 'enterprise' THEN jsonb_build_object(
        'unlimited_chat',      true,
        'unlimited_exercises', true,
        'premium_content',     true,
        'priority_support',    true,
        'family_sharing',      true,
        'offline_mode',        true,
        'custom_themes',       true,
        'advanced_insights',   true
    )
    WHEN 'gift' THEN jsonb_build_object(
        'unlimited_chat',      true,
        'unlimited_exercises', true,
        'premium_content',     true,
        'priority_support',    true,
        'family_sharing',      false,
        'offline_mode',        true,
        'custom_themes',       true,
        'advanced_insights',   true
    )
    ELSE features
END
WHERE NOT (
    features ? 'unlimited_chat'
    AND features ? 'unlimited_exercises'
    AND features ? 'premium_content'
    AND features ? 'priority_support'
    AND features ? 'family_sharing'
    AND features ? 'offline_mode'
    AND features ? 'custom_themes'
    AND features ? 'advanced_insights'
);

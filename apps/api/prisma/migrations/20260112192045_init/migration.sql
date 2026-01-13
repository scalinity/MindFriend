-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('active', 'grace', 'expired', 'canceled');

-- CreateEnum
CREATE TYPE "ConversationStatus" AS ENUM ('active', 'archived');

-- CreateEnum
CREATE TYPE "MessageRole" AS ENUM ('user', 'assistant', 'system');

-- CreateEnum
CREATE TYPE "ModerationLabel" AS ENUM ('ok', 'self_harm', 'violence', 'sexual', 'minors', 'hate', 'unknown');

-- CreateEnum
CREATE TYPE "MoodSource" AS ENUM ('manual', 'quest', 'circle_checkin');

-- CreateEnum
CREATE TYPE "QuestInstanceStatus" AS ENUM ('assigned', 'completed', 'skipped', 'expired');

-- CreateEnum
CREATE TYPE "CircleMemberRole" AS ENUM ('owner', 'member');

-- CreateEnum
CREATE TYPE "CirclePostKind" AS ENUM ('checkin', 'achievement', 'reflection');

-- CreateEnum
CREATE TYPE "ContentKind" AS ENUM ('text', 'audio');

-- CreateEnum
CREATE TYPE "NotificationType" AS ENUM ('daily_quest', 'inactivity_nudge', 'circle_activity');

-- CreateEnum
CREATE TYPE "NotificationStatus" AS ENUM ('scheduled', 'sent', 'failed', 'canceled');

-- CreateEnum
CREATE TYPE "CrisisSeverity" AS ENUM ('low', 'medium', 'high');

-- CreateEnum
CREATE TYPE "CrisisSource" AS ENUM ('ai_input', 'ai_output', 'mood_entry', 'user_action');

-- CreateEnum
CREATE TYPE "CrisisAction" AS ENUM ('show_resources', 'block_response', 'handoff_message');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "handle" VARCHAR(24) NOT NULL,
    "display_name" VARCHAR(40) NOT NULL,
    "email" VARCHAR(255),
    "birthdate" DATE,
    "country_code" CHAR(2),
    "timezone" VARCHAR(64) NOT NULL DEFAULT 'UTC',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,
    "deleted_at" TIMESTAMPTZ,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "auth_identities" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "provider" VARCHAR(16) NOT NULL,
    "provider_subject" VARCHAR(128) NOT NULL,
    "email" VARCHAR(255),
    "email_verified" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "auth_identities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" VARCHAR(128) NOT NULL,
    "device_id" UUID,
    "expires_at" TIMESTAMPTZ NOT NULL,
    "revoked_at" TIMESTAMPTZ,
    "replaced_by_id" UUID,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "platform" VARCHAR(16) NOT NULL DEFAULT 'ios',
    "device_model" VARCHAR(64),
    "os_version" VARCHAR(32),
    "locale" VARCHAR(16) NOT NULL DEFAULT 'en-US',
    "timezone" VARCHAR(64) NOT NULL,
    "apns_token" VARCHAR(200),
    "push_enabled" BOOLEAN NOT NULL DEFAULT true,
    "last_seen_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_settings" (
    "user_id" UUID NOT NULL,
    "daily_quest_time_local" VARCHAR(8) NOT NULL DEFAULT '09:00:00',
    "quiet_hours_start_local" VARCHAR(8),
    "quiet_hours_end_local" VARCHAR(8),
    "reminders_enabled" BOOLEAN NOT NULL DEFAULT true,
    "nudge_after_days_inactive" INTEGER NOT NULL DEFAULT 2,
    "share_mood_in_circles" BOOLEAN NOT NULL DEFAULT true,
    "ai_tone" VARCHAR(16) NOT NULL DEFAULT 'friendly',
    "privacy_mode" VARCHAR(16) NOT NULL DEFAULT 'standard',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "user_settings_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "user_stats" (
    "user_id" UUID NOT NULL,
    "current_streak_days" INTEGER NOT NULL DEFAULT 0,
    "longest_streak_days" INTEGER NOT NULL DEFAULT 0,
    "last_streak_local_date" VARCHAR(10),
    "total_quests_completed" INTEGER NOT NULL DEFAULT 0,
    "total_exercises_completed" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "user_stats_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "subscriptions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "status" "SubscriptionStatus" NOT NULL,
    "current_period_end" TIMESTAMPTZ,
    "original_transaction_id" VARCHAR(64),
    "latest_transaction_id" VARCHAR(64),
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "conversations" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "title" VARCHAR(64),
    "status" "ConversationStatus" NOT NULL DEFAULT 'active',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "conversations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "messages" (
    "id" UUID NOT NULL,
    "conversation_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" "MessageRole" NOT NULL,
    "content" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "moderation_label" "ModerationLabel",
    "blocked" BOOLEAN NOT NULL DEFAULT false,
    "token_in" INTEGER,
    "token_out" INTEGER,
    "provider_message_id" VARCHAR(128),

    CONSTRAINT "messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "daily_ai_usage" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "local_date" VARCHAR(10) NOT NULL,
    "message_count" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "daily_ai_usage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "mood_entries" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "local_date" VARCHAR(10) NOT NULL,
    "mood_score" SMALLINT NOT NULL,
    "anxiety_score" SMALLINT,
    "energy_score" SMALLINT,
    "note" TEXT,
    "source" "MoodSource" NOT NULL DEFAULT 'manual',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "mood_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quest_templates" (
    "id" UUID NOT NULL,
    "type" VARCHAR(32) NOT NULL,
    "title" VARCHAR(64) NOT NULL,
    "description" VARCHAR(240) NOT NULL,
    "estimated_minutes" SMALLINT NOT NULL,
    "difficulty" SMALLINT NOT NULL,
    "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "instructions_json" JSONB NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "quest_templates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quest_instances" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "template_id" UUID NOT NULL,
    "local_date" VARCHAR(10) NOT NULL,
    "status" "QuestInstanceStatus" NOT NULL DEFAULT 'assigned',
    "personalization_json" JSONB NOT NULL DEFAULT '{}',
    "assigned_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMPTZ,

    CONSTRAINT "quest_instances_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quest_completions" (
    "id" UUID NOT NULL,
    "quest_instance_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "reflection_note" TEXT,
    "rating" SMALLINT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "quest_completions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "badges" (
    "id" UUID NOT NULL,
    "code" VARCHAR(32) NOT NULL,
    "title" VARCHAR(64) NOT NULL,
    "description" VARCHAR(240) NOT NULL,
    "criteria_json" JSONB NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "badges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_badges" (
    "user_id" UUID NOT NULL,
    "badge_id" UUID NOT NULL,
    "earned_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_badges_pkey" PRIMARY KEY ("user_id","badge_id")
);

-- CreateTable
CREATE TABLE "circles" (
    "id" UUID NOT NULL,
    "owner_user_id" UUID NOT NULL,
    "name" VARCHAR(40) NOT NULL,
    "description" VARCHAR(160),
    "is_private" BOOLEAN NOT NULL DEFAULT true,
    "invite_code" VARCHAR(12) NOT NULL,
    "max_members" SMALLINT NOT NULL DEFAULT 8,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "circles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "circle_members" (
    "circle_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" "CircleMemberRole" NOT NULL DEFAULT 'member',
    "status" VARCHAR(16) NOT NULL DEFAULT 'active',
    "joined_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "circle_members_pkey" PRIMARY KEY ("circle_id","user_id")
);

-- CreateTable
CREATE TABLE "circle_posts" (
    "id" UUID NOT NULL,
    "circle_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "kind" "CirclePostKind" NOT NULL,
    "mood_emoji" VARCHAR(8),
    "body_text" VARCHAR(280),
    "local_date" VARCHAR(10) NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "circle_posts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "exercises" (
    "id" UUID NOT NULL,
    "type" VARCHAR(24) NOT NULL,
    "title" VARCHAR(64) NOT NULL,
    "description" VARCHAR(240) NOT NULL,
    "duration_seconds" INTEGER NOT NULL,
    "content_kind" "ContentKind" NOT NULL,
    "content_text" TEXT,
    "audio_url" TEXT,
    "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "exercises_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "exercise_sessions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "exercise_id" UUID NOT NULL,
    "started_at" TIMESTAMPTZ NOT NULL,
    "ended_at" TIMESTAMPTZ,
    "completed" BOOLEAN NOT NULL DEFAULT false,
    "rating" SMALLINT,
    "note" TEXT,

    CONSTRAINT "exercise_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "device_id" UUID NOT NULL,
    "type" "NotificationType" NOT NULL,
    "title" VARCHAR(64) NOT NULL,
    "body" VARCHAR(160) NOT NULL,
    "data_json" JSONB NOT NULL DEFAULT '{}',
    "scheduled_at" TIMESTAMPTZ NOT NULL,
    "sent_at" TIMESTAMPTZ,
    "status" "NotificationStatus" NOT NULL DEFAULT 'scheduled',

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crisis_events" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "severity" "CrisisSeverity" NOT NULL,
    "source" "CrisisSource" NOT NULL,
    "message_id" UUID,
    "detected_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "action_taken" "CrisisAction" NOT NULL,
    "metadata_json" JSONB NOT NULL DEFAULT '{}',

    CONSTRAINT "crisis_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crisis_resources" (
    "id" UUID NOT NULL,
    "country_code" VARCHAR(10) NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "contact" VARCHAR(200) NOT NULL,
    "kind" VARCHAR(20) NOT NULL,
    "description" VARCHAR(255),
    "priority" INTEGER NOT NULL DEFAULT 100,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "crisis_resources_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_handle_key" ON "users"("handle");

-- CreateIndex
CREATE INDEX "users_created_at_idx" ON "users"("created_at");

-- CreateIndex
CREATE INDEX "auth_identities_user_id_idx" ON "auth_identities"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "auth_identities_provider_provider_subject_key" ON "auth_identities"("provider", "provider_subject");

-- CreateIndex
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_token_hash_idx" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE UNIQUE INDEX "devices_apns_token_key" ON "devices"("apns_token");

-- CreateIndex
CREATE INDEX "devices_user_id_idx" ON "devices"("user_id");

-- CreateIndex
CREATE INDEX "subscriptions_user_id_idx" ON "subscriptions"("user_id");

-- CreateIndex
CREATE INDEX "subscriptions_status_idx" ON "subscriptions"("status");

-- CreateIndex
CREATE INDEX "conversations_user_id_idx" ON "conversations"("user_id");

-- CreateIndex
CREATE INDEX "messages_conversation_id_created_at_idx" ON "messages"("conversation_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "daily_ai_usage_user_id_local_date_key" ON "daily_ai_usage"("user_id", "local_date");

-- CreateIndex
CREATE INDEX "mood_entries_user_id_local_date_idx" ON "mood_entries"("user_id", "local_date");

-- CreateIndex
CREATE UNIQUE INDEX "mood_entries_user_id_local_date_source_key" ON "mood_entries"("user_id", "local_date", "source");

-- CreateIndex
CREATE INDEX "quest_templates_type_idx" ON "quest_templates"("type");

-- CreateIndex
CREATE INDEX "quest_templates_active_idx" ON "quest_templates"("active");

-- CreateIndex
CREATE INDEX "quest_instances_user_id_local_date_idx" ON "quest_instances"("user_id", "local_date");

-- CreateIndex
CREATE UNIQUE INDEX "quest_instances_user_id_local_date_key" ON "quest_instances"("user_id", "local_date");

-- CreateIndex
CREATE UNIQUE INDEX "quest_completions_quest_instance_id_key" ON "quest_completions"("quest_instance_id");

-- CreateIndex
CREATE UNIQUE INDEX "badges_code_key" ON "badges"("code");

-- CreateIndex
CREATE UNIQUE INDEX "circles_invite_code_key" ON "circles"("invite_code");

-- CreateIndex
CREATE INDEX "circles_invite_code_idx" ON "circles"("invite_code");

-- CreateIndex
CREATE INDEX "circle_posts_circle_id_local_date_idx" ON "circle_posts"("circle_id", "local_date");

-- CreateIndex
CREATE UNIQUE INDEX "circle_posts_circle_id_user_id_local_date_kind_key" ON "circle_posts"("circle_id", "user_id", "local_date", "kind");

-- CreateIndex
CREATE INDEX "exercises_type_idx" ON "exercises"("type");

-- CreateIndex
CREATE INDEX "exercises_active_idx" ON "exercises"("active");

-- CreateIndex
CREATE INDEX "exercise_sessions_user_id_idx" ON "exercise_sessions"("user_id");

-- CreateIndex
CREATE INDEX "notifications_user_id_scheduled_at_idx" ON "notifications"("user_id", "scheduled_at");

-- CreateIndex
CREATE INDEX "notifications_status_scheduled_at_idx" ON "notifications"("status", "scheduled_at");

-- CreateIndex
CREATE INDEX "crisis_events_user_id_detected_at_idx" ON "crisis_events"("user_id", "detected_at");

-- CreateIndex
CREATE INDEX "crisis_resources_country_code_idx" ON "crisis_resources"("country_code");

-- AddForeignKey
ALTER TABLE "auth_identities" ADD CONSTRAINT "auth_identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_replaced_by_id_fkey" FOREIGN KEY ("replaced_by_id") REFERENCES "refresh_tokens"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_settings" ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_stats" ADD CONSTRAINT "user_stats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "messages" ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "messages" ADD CONSTRAINT "messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "daily_ai_usage" ADD CONSTRAINT "daily_ai_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mood_entries" ADD CONSTRAINT "mood_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quest_instances" ADD CONSTRAINT "quest_instances_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quest_instances" ADD CONSTRAINT "quest_instances_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "quest_templates"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quest_completions" ADD CONSTRAINT "quest_completions_quest_instance_id_fkey" FOREIGN KEY ("quest_instance_id") REFERENCES "quest_instances"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quest_completions" ADD CONSTRAINT "quest_completions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "badges"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circles" ADD CONSTRAINT "circles_owner_user_id_fkey" FOREIGN KEY ("owner_user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circle_members" ADD CONSTRAINT "circle_members_circle_id_fkey" FOREIGN KEY ("circle_id") REFERENCES "circles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circle_members" ADD CONSTRAINT "circle_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circle_posts" ADD CONSTRAINT "circle_posts_circle_id_fkey" FOREIGN KEY ("circle_id") REFERENCES "circles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circle_posts" ADD CONSTRAINT "circle_posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exercise_sessions" ADD CONSTRAINT "exercise_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "exercise_sessions" ADD CONSTRAINT "exercise_sessions_exercise_id_fkey" FOREIGN KEY ("exercise_id") REFERENCES "exercises"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crisis_events" ADD CONSTRAINT "crisis_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crisis_events" ADD CONSTRAINT "crisis_events_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;

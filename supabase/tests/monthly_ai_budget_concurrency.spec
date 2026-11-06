# PostgreSQL isolationtester specification, disposable local database only.
# Apply the forward migration first. Each permutation starts with an empty ledger.
# The second caller must block until the first commits; tests assert the durable
# counter and receipt count as well as each returned decision. No provider calls.

setup
{
  TRUNCATE public.monthly_ai_budget_receipts, public.monthly_ai_budget_months;
}

teardown
{
  TRUNCATE public.monthly_ai_budget_receipts, public.monthly_ai_budget_months;
}

session "one"
step "one_begin" { BEGIN; SET LOCAL ROLE service_role; }
step "one_seven" {
  DO $$ BEGIN
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000101', 'chat', 7000000)->>'allowed' <> 'true'
    THEN RAISE EXCEPTION 'first admission denied'; END IF;
  END $$;
}
step "one_five" {
  DO $$ BEGIN
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000101', 'chat', 5000000)->>'allowed' <> 'true'
    THEN RAISE EXCEPTION 'first half denied'; END IF;
  END $$;
}
step "one_commit" { COMMIT; }

session "two"
step "two_begin" { BEGIN; SET LOCAL ROLE service_role; }
step "two_four_denied" {
  DO $$ BEGIN
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000102', 'tts', 4000000)->>'reason' <> 'exhausted'
    THEN RAISE EXCEPTION 'concurrent features overshot ceiling'; END IF;
  END $$;
}
step "two_five" {
  DO $$ BEGIN
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000102', 'tts', 5000000)->>'allowed' <> 'true'
    THEN RAISE EXCEPTION 'exact concurrent ceiling denied'; END IF;
  END $$;
}
step "two_retry" {
  DO $$ BEGIN
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000101', 'chat', 7000000)->>'allowed' <> 'true'
    THEN RAISE EXCEPTION 'matching concurrent retry denied'; END IF;
  END $$;
}
step "two_mismatch" {
  DO $$ BEGIN
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000102', 'tts', 7000000)->>'reason' <> 'request_mismatch'
    THEN RAISE EXCEPTION 'concurrent cross-owner UUID reuse allowed'; END IF;
  END $$;
}
step "two_commit" { COMMIT; }

session "check"
step "check_seven_two_receipts" {
  DO $$ BEGIN
    IF (SELECT sum(reserved_microdollars) FROM public.monthly_ai_budget_months) <> 7000000
      OR (SELECT count(*) FROM public.monthly_ai_budget_months) <> 1
      OR (SELECT count(*) FROM public.monthly_ai_budget_receipts) <> 2
    THEN RAISE EXCEPTION 'concurrent ledger invariant failed'; END IF;
  END $$;
}
step "check_seven_one_receipt" {
  DO $$ BEGIN
    IF (SELECT sum(reserved_microdollars) FROM public.monthly_ai_budget_months) <> 7000000
      OR (SELECT count(*) FROM public.monthly_ai_budget_months) <> 1
      OR (SELECT count(*) FROM public.monthly_ai_budget_receipts) <> 1
    THEN RAISE EXCEPTION 'concurrent UUID debited twice'; END IF;
  END $$;
}
step "check_ten" {
  SET ROLE service_role;
  DO $$ DECLARE v_result jsonb; BEGIN
    -- Finish the volatile RPC before inspecting its receipt; SQL expression
    -- evaluation order does not guarantee a subquery sees that new receipt.
    v_result := public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000003',
      '00000000-0000-0000-0000-000000000103', 'image', 1);
    IF v_result->>'reason' <> 'exhausted'
      OR (SELECT sum(reserved_microdollars) FROM public.monthly_ai_budget_months) <> 10000000
      OR (SELECT count(*) FROM public.monthly_ai_budget_receipts) <> 3
    THEN RAISE EXCEPTION 'concurrent exact-limit invariant failed'; END IF;
  END $$;
  RESET ROLE;
}

permutation "one_begin" "two_begin" "one_seven" "two_four_denied" "one_commit" "two_commit" "check_seven_two_receipts"
permutation "one_begin" "two_begin" "one_seven" "two_retry" "one_commit" "two_commit" "check_seven_one_receipt"
permutation "one_begin" "two_begin" "one_seven" "two_mismatch" "one_commit" "two_commit" "check_seven_one_receipt"
permutation "one_begin" "two_begin" "one_five" "two_five" "one_commit" "two_commit" "check_ten"

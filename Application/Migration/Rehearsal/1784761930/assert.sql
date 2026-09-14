DO $$
BEGIN
    IF (SELECT count(*) FROM venues WHERE name = 'Preserved Venue') <> 1 THEN
        RAISE EXCEPTION 'billing_predecessor_venue_preservation failed';
    END IF;
    IF (
        SELECT count(*)
        FROM venue_billing_customers
        WHERE stripe_customer_id = 'cus_preserved'
          AND livemode = FALSE
          AND created_by_user_id IS NULL
    ) <> 1 THEN
        RAISE EXCEPTION 'billing_customer_backfill_preservation failed';
    END IF;
    IF (
        SELECT count(*)
        FROM venue_subscriptions
        WHERE stripe_subscription_id = 'sub_preserved'
          AND livemode = FALSE
          AND last_applied_stripe_event_id IS NULL
    ) <> 1 THEN
        RAISE EXCEPTION 'billing_subscription_backfill_preservation failed';
    END IF;
    IF (
        SELECT count(*)
        FROM billing_events
        WHERE stripe_event_id = 'evt_preserved'
          AND livemode = FALSE
          AND stripe_created_at IS NULL
    ) <> 1 THEN
        RAISE EXCEPTION 'billing_event_backfill_preservation failed';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name IN (
              'venue_billing_customers',
              'venue_subscriptions',
              'billing_events'
          )
          AND column_name = 'livemode'
          AND column_default IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'billing_livemode_temporary_default_removal failed';
    END IF;
END
$$;

INSERT INTO billing_checkout_attempts (
    venue_id,
    initiated_by_user_id,
    livemode,
    stripe_customer_id,
    stripe_price_id
) VALUES (
    'a1000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    FALSE,
    'cus_preserved',
    'price_preserved'
);

DO $$
BEGIN
    BEGIN
        INSERT INTO billing_checkout_attempts (
            venue_id,
            initiated_by_user_id,
            livemode,
            stripe_customer_id,
            stripe_price_id
        ) VALUES (
            'a1000000-0000-0000-0000-000000000001',
            'a0000000-0000-0000-0000-000000000001',
            FALSE,
            'cus_second_open',
            'price_preserved'
        );
        RAISE EXCEPTION 'billing_one_open_checkout_attempt_invariant failed';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;
END
$$;

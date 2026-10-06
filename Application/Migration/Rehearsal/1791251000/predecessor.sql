-- Fictional venues with contrasting existing configuration.
INSERT INTO venues (id, name) VALUES
    ('a6540000-0000-0000-0000-000000000001', 'Duration rehearsal A'),
    ('a6540000-0000-0000-0000-000000000002', 'Duration rehearsal B');
INSERT INTO venue_config (id, venue_id, timezone, roster_week_starts_on,
    time_picker_start_minute_of_day, time_picker_final_selectable_minute_of_day,
    minute_precision_shift_times_enabled, updated_at)
VALUES
    ('a6540000-0000-0000-0000-000000000011', 'a6540000-0000-0000-0000-000000000001', 'Australia/Melbourne', 4, 540, 1020, TRUE, '2026-01-01T00:00:00Z'),
    ('a6540000-0000-0000-0000-000000000012', 'a6540000-0000-0000-0000-000000000002', 'Australia/Melbourne', 1, 360, 345, FALSE, '2026-01-01T00:00:00Z');

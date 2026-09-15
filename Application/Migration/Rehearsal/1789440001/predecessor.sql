-- Minimal production-shaped incident; no customer identifiers.
INSERT INTO public_holidays (jurisdiction, holiday_date, name, source, imported_at)
SELECT 'VIC', d, n, 'Business Victoria', TIMESTAMPTZ '2026-07-31 18:26:21+00'
FROM (VALUES
    (DATE '2026-01-01', 'New Year''s Day'), (DATE '2026-01-26', 'Australia Day'),
    (DATE '2026-03-09', 'Labour Day'), (DATE '2026-04-03', 'Good Friday'),
    (DATE '2026-04-04', 'Saturday before Easter Sunday'), (DATE '2026-04-05', 'Easter Sunday'),
    (DATE '2026-04-06', 'Easter Monday'), (DATE '2026-04-25', 'ANZAC Day'),
    (DATE '2026-06-08', 'King''s Birthday'), (DATE '2026-11-03', 'Melbourne Cup'),
    (DATE '2026-12-25', 'Christmas Day'), (DATE '2026-12-26', 'Boxing Day'),
    (DATE '2026-12-28', 'Boxing Day'),
    (DATE '2027-03-28', 'Easter Monday'), (DATE '2027-03-28', 'Easter Sunday')
) fixture(d, n);
INSERT INTO public_holidays (jurisdiction, holiday_date, name, is_regional, region)
VALUES ('VIC', DATE '2026-09-25', 'Local-only fixture', TRUE, 'Local fixture'),
       ('NSW', DATE '2026-09-25', 'Other-state fixture', FALSE, NULL);

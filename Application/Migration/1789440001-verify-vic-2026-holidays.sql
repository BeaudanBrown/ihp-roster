-- Operator approval required: public-holiday-override-runbook.md.
-- IHP runs this complete revision transactionally. Stop app and worker first.
-- No row deletions, no imported_at renewal, no sealed payroll changes.
LOCK TABLE public_holidays, public_holiday_overrides IN ACCESS EXCLUSIVE MODE;

DO $$
DECLARE
    before_rows JSONB;
    after_rows JSONB;
    expected_rows JSONB;
BEGIN
    -- Repeat execution must never reactivate a retired override or rewrite audit.
    IF EXISTS (SELECT 1 FROM public_holiday_overrides WHERE snapshot_key = 'business-victoria-vic-2026-20260915-v1') THEN
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM public_holiday_overrides WHERE jurisdiction = 'VIC' AND target_year = 2026 AND retired_at IS NULL) THEN
        RAISE EXCEPTION 'Unexpected active VIC 2026 override; review before proceeding';
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(h) ORDER BY holiday_date, name, id), '[]'::JSONB) INTO before_rows
    FROM public_holidays h
    WHERE jurisdiction = 'VIC' AND NOT is_regional
      AND (holiday_date BETWEEN DATE '2026-01-01' AND DATE '2026-12-31'
           OR (holiday_date BETWEEN DATE '2027-01-01' AND DATE '2027-12-31' AND name = 'Easter Monday'));

    -- Review unexpected dates/regions rather than silently adding a second holiday.
    IF EXISTS (SELECT 1 FROM public_holidays WHERE jurisdiction = 'VIC' AND NOT is_regional
        AND holiday_date BETWEEN DATE '2026-01-01' AND DATE '2026-12-31'
        AND (region IS NOT NULL OR (lower(name) LIKE '%afl%' AND
             (holiday_date <> DATE '2026-09-25' OR name <> 'Friday before the AFL grand final')))) THEN
        RAISE EXCEPTION 'Unexpected VIC 2026 holiday identity; manual review required';
    END IF;
    IF (SELECT count(*) FROM public_holidays WHERE jurisdiction = 'VIC' AND NOT is_regional
        AND holiday_date BETWEEN DATE '2027-01-01' AND DATE '2027-12-31' AND name = 'Easter Monday') > 1
       OR EXISTS (SELECT 1 FROM public_holidays WHERE jurisdiction = 'VIC' AND NOT is_regional
        AND holiday_date BETWEEN DATE '2027-01-01' AND DATE '2027-12-31' AND name = 'Easter Monday'
        AND (region IS NOT NULL OR holiday_date NOT IN (DATE '2027-03-28', DATE '2027-03-29'))) THEN
        RAISE EXCEPTION 'Ambiguous Easter Monday 2027; manual review required';
    END IF;

    INSERT INTO public_holidays (jurisdiction, holiday_date, name, source, source_id, source_url, description)
    SELECT 'VIC', DATE '2026-09-25', 'Friday before the AFL grand final',
        'Business Victoria (Bepis verified correction)', 'business-victoria-vic-2026-20260915-v1:grand-final',
        'https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026',
        'Verified 2026-09-15; added by migration 1789440001. Not a DataVic refresh.'
    WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE jurisdiction = 'VIC' AND NOT is_regional
        AND holiday_date = DATE '2026-09-25' AND name = 'Friday before the AFL grand final');

    UPDATE public_holidays SET holiday_date = DATE '2027-03-29',
        source = 'Business Victoria (Bepis verified correction)',
        source_url = 'https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2027',
        description = concat_ws(E'\n', description, 'Easter Monday corrected from 2027-03-28 by migration 1789440001; verified 2026-09-15.'),
        updated_at = NOW()
    WHERE jurisdiction = 'VIC' AND NOT is_regional AND region IS NULL
      AND name = 'Easter Monday' AND holiday_date = DATE '2027-03-28';

    -- Full reviewed multiset: a count alone would accept shifted or extra dates.
    SELECT jsonb_agg(jsonb_build_array(d, n) ORDER BY d, n) INTO expected_rows FROM (VALUES
        (DATE '2026-01-01', 'New Year''s Day'), (DATE '2026-01-26', 'Australia Day'),
        (DATE '2026-03-09', 'Labour Day'), (DATE '2026-04-03', 'Good Friday'),
        (DATE '2026-04-04', 'Saturday before Easter Sunday'), (DATE '2026-04-05', 'Easter Sunday'),
        (DATE '2026-04-06', 'Easter Monday'), (DATE '2026-04-25', 'ANZAC Day'),
        (DATE '2026-06-08', 'King''s Birthday'), (DATE '2026-09-25', 'Friday before the AFL grand final'),
        (DATE '2026-11-03', 'Melbourne Cup'), (DATE '2026-12-25', 'Christmas Day'),
        (DATE '2026-12-26', 'Boxing Day'), (DATE '2026-12-28', 'Boxing Day')
    ) expected(d, n);
    IF (SELECT jsonb_agg(jsonb_build_array(holiday_date, name) ORDER BY holiday_date, name)
        FROM public_holidays WHERE jurisdiction = 'VIC' AND NOT is_regional
        AND holiday_date BETWEEN DATE '2026-01-01' AND DATE '2026-12-31') IS DISTINCT FROM expected_rows THEN
        RAISE EXCEPTION 'VIC 2026 calendar differs from verified snapshot; entire correction rolled back';
    END IF;

    SELECT jsonb_agg(to_jsonb(h) ORDER BY holiday_date, name, id) INTO after_rows
    FROM public_holidays h
    WHERE jurisdiction = 'VIC' AND NOT is_regional
      AND (holiday_date BETWEEN DATE '2026-01-01' AND DATE '2026-12-31'
           OR (holiday_date BETWEEN DATE '2027-01-01' AND DATE '2027-12-31' AND name = 'Easter Monday'));

    INSERT INTO public_holiday_overrides
        (jurisdiction, target_year, snapshot_key, source_url, verified_at, review_due_at, correction_before, correction_after)
    VALUES ('VIC', 2026, 'business-victoria-vic-2026-20260915-v1',
        'https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026',
        TIMESTAMPTZ '2026-09-15 02:30:00+00', TIMESTAMPTZ '2026-10-15 00:00:00+00', before_rows, after_rows);
END;
$$;

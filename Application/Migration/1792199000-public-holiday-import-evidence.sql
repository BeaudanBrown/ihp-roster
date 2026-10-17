-- Additive acceptance ledger. No calendar or override is changed at deployment.
CREATE TABLE public_holiday_import_batches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    jurisdiction TEXT NOT NULL,
    target_years INT[] NOT NULL,
    accepted_at TIMESTAMP WITH TIME ZONE NOT NULL,
    source TEXT NOT NULL,
    previous_calendar JSONB DEFAULT '[]'::JSONB NOT NULL,
    accepted_calendar JSONB DEFAULT '[]'::JSONB NOT NULL,
    reviewed_by_user_id UUID DEFAULT NULL,
    FOREIGN KEY (reviewed_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (cardinality(target_years) > 0),
    CHECK ((source = 'datavic_v2') OR (source = 'legacy_import'))
);

-- Preserve existing import evidence, not deployment time or reviewed-override
-- timestamps. Overrides continue to supersede this evidence until cutover.
INSERT INTO public_holiday_import_batches (jurisdiction, target_years, accepted_at, source)
SELECT jurisdiction, ARRAY[extract(year FROM holiday_date)::int],
       max(imported_at), 'legacy_import'
FROM public_holidays
WHERE jurisdiction = 'VIC' AND NOT is_regional AND imported_at IS NOT NULL
GROUP BY jurisdiction, extract(year FROM holiday_date)::int;

CREATE TYPE award_penalty_kind_enum AS ENUM ('evening_after_7pm', 'late_night_after_midnight', 'saturday_penalty', 'sunday_penalty', 'public_holiday_penalty');

ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_default_pay_level_id_fk;
ALTER TABLE shift_types DROP CONSTRAINT IF EXISTS shift_types_default_pay_level_id_fk;

DO $$
DECLARE
    dependent_constraint RECORD;
BEGIN
    FOR dependent_constraint IN
        SELECT conrelid::regclass AS table_name, conname AS constraint_name
        FROM pg_constraint
        WHERE contype = 'f'
            AND confrelid IN (
                SELECT oid
                FROM pg_class
                WHERE relnamespace = 'public'::regnamespace
                    AND relname IN ('pay_levels', 'pay_level_day_rules')
            )
    LOOP
        EXECUTE format(
            'ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I',
            dependent_constraint.table_name,
            dependent_constraint.constraint_name
        );
    END LOOP;
END
$$;

DROP TABLE IF EXISTS pay_level_day_rules;
DROP TABLE IF EXISTS pay_levels;

ALTER TABLE staff RENAME COLUMN default_pay_level_id TO default_award_level_id;
ALTER TABLE shift_types RENAME COLUMN default_pay_level_id TO override_award_level_id;
ALTER TABLE shift_types ALTER COLUMN override_award_level_id DROP NOT NULL;
ALTER TABLE venue_config ADD COLUMN public_holiday_jurisdiction TEXT DEFAULT 'VIC' NOT NULL;
ALTER TABLE fwc_mapd_sync_runs ADD COLUMN fetched_penalty_rate_count INT DEFAULT 0 NOT NULL;

CREATE TABLE fwc_mapd_penalty_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT DEFAULT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    clause_description TEXT DEFAULT NULL,
    employee_rate_type_code TEXT DEFAULT NULL,
    base_pay_rate_id TEXT DEFAULT NULL,
    penalty_fixed_id INT DEFAULT NULL,
    penalty_description TEXT DEFAULT NULL,
    penalty_text TEXT DEFAULT NULL,
    rate NUMERIC(12,4) DEFAULT NULL,
    penalty_rate_unit TEXT DEFAULT NULL,
    penalty_calculated_value NUMERIC(12,4) DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    version_number INT DEFAULT NULL,
    last_modified_datetime TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE award_levels (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT NOT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    clause_description TEXT DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_fixed_id, classification_fixed_id, published_year)
);

ALTER TABLE staff
    ADD CONSTRAINT staff_default_award_level_id_fk
    FOREIGN KEY (default_award_level_id) REFERENCES award_levels (id) ON DELETE SET NULL;

ALTER TABLE shift_types
    ADD CONSTRAINT shift_types_override_award_level_id_fk
    FOREIGN KEY (override_award_level_id) REFERENCES award_levels (id) ON DELETE SET NULL;

CREATE TABLE award_level_base_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_level_id UUID NOT NULL,
    employment_basis staff_employment_basis_enum NOT NULL,
    fwc_mapd_pay_rate_id UUID NOT NULL,
    hourly_rate NUMERIC(12,4) NOT NULL,
    rate_label TEXT NOT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_level_id, employment_basis, operative_from, operative_to),
    FOREIGN KEY (award_level_id) REFERENCES award_levels (id) ON DELETE CASCADE,
    FOREIGN KEY (fwc_mapd_pay_rate_id) REFERENCES fwc_mapd_pay_rates (id) ON DELETE CASCADE
);

CREATE TABLE award_level_penalty_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_level_id UUID NOT NULL,
    employment_basis staff_employment_basis_enum NOT NULL,
    penalty_kind award_penalty_kind_enum NOT NULL,
    fwc_mapd_penalty_rate_id UUID NOT NULL,
    hourly_rate NUMERIC(12,4) NOT NULL,
    starts_at_time TIME DEFAULT NULL,
    ends_at_time TIME DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_level_id, employment_basis, penalty_kind, operative_from, operative_to),
    FOREIGN KEY (award_level_id) REFERENCES award_levels (id) ON DELETE CASCADE,
    FOREIGN KEY (fwc_mapd_penalty_rate_id) REFERENCES fwc_mapd_penalty_rates (id) ON DELETE CASCADE
);

CREATE TABLE public_holidays (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    jurisdiction TEXT NOT NULL,
    holiday_date DATE NOT NULL,
    name TEXT NOT NULL,
    region TEXT DEFAULT NULL,
    is_regional BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(jurisdiction, holiday_date, name, region)
);

CREATE INDEX idx_staff_default_award_level ON staff (default_award_level_id) WHERE default_award_level_id IS NOT NULL;
CREATE INDEX idx_fwc_mapd_penalty_rates_award_current ON fwc_mapd_penalty_rates (award_fixed_id, operative_to, classification_fixed_id);
CREATE INDEX idx_award_levels_classification ON award_levels (award_fixed_id, classification_fixed_id, is_active);
CREATE INDEX idx_award_level_base_rates_lookup ON award_level_base_rates (award_level_id, employment_basis, operative_from, operative_to);
CREATE INDEX idx_award_level_penalty_rates_lookup ON award_level_penalty_rates (award_level_id, employment_basis, penalty_kind, operative_from, operative_to);
CREATE INDEX idx_public_holidays_lookup ON public_holidays (jurisdiction, holiday_date);

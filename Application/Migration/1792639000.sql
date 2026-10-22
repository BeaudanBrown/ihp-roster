-- Additive settings only: existing venues remain opted out of payroll email.
CREATE TABLE payroll_report_settings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL UNIQUE,
    configuration_id UUID,
    recipients TEXT[] DEFAULT '{}' NOT NULL,
    enabled BOOLEAN DEFAULT FALSE NOT NULL,
    weekday INT DEFAULT 1 NOT NULL,
    minute_of_day INT DEFAULT 540 NOT NULL,
    revision INT DEFAULT 0 NOT NULL,
    delivery_revision INT DEFAULT 0 NOT NULL,
    schedule_activated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_by_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (configuration_id) REFERENCES payroll_workbook_configurations (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((weekday >= 0) AND (weekday <= 6)),
    CHECK ((minute_of_day >= 0) AND (minute_of_day < 1440)),
    CHECK ((revision >= 0) AND (delivery_revision >= 0)),
    CHECK (cardinality(recipients) <= 50),
    CHECK ((enabled = FALSE) OR ((configuration_id IS NOT NULL) AND (cardinality(recipients) > 0)))
);

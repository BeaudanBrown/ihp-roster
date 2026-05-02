CREATE TYPE roster_layout_mode_enum AS ENUM ('day_rows', 'day_columns');

CREATE TABLE user_preferences (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    roster_layout_mode roster_layout_mode_enum DEFAULT 'day_rows' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(user_id),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

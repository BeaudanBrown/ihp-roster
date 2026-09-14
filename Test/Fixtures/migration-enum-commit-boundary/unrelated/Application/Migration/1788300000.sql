-- Semicolons and SQL-looking text in comments must not affect classification:
-- ALTER TYPE example ADD VALUE 'ignored'; UPDATE example SET state = 'ignored';
ALTER TYPE mood RENAME VALUE 'sad' TO 'ADD VALUE';

CREATE TABLE migration_guard_unrelated (
    id UUID PRIMARY KEY,
    note TEXT DEFAULT 'a semicolon; and ALTER TYPE example ADD VALUE ''also_ignored'''
);

DO $body$
BEGIN
    PERFORM 'ALTER TYPE example ADD VALUE ''still_ignored'';';
END
$body$;

-- Permit one transaction to build the next immutable roster-template version.
-- The version is sealed when roster_templates.current_version advances.
CREATE OR REPLACE FUNCTION prevent_saved_roster_template_content_mutation()
RETURNS TRIGGER
AS $$
DECLARE
    old_design_id UUID;
    new_design_id UUID;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        old_design_id := OLD.roster_template_design_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        new_design_id := NEW.roster_template_design_id;
    END IF;
    IF TG_OP = 'INSERT' AND EXISTS (
        SELECT 1
        FROM roster_template_designs d
        JOIN roster_templates t ON t.id = d.template_id
        WHERE d.id = new_design_id
          AND d.draft_owner_user_id IS NULL
          AND d.version_number = t.current_version + 1
    ) THEN
        RETURN NEW;
    END IF;
    IF EXISTS (
        SELECT 1 FROM roster_template_designs d
        WHERE (d.id = old_design_id OR d.id = new_design_id)
          AND d.draft_owner_user_id IS NULL
    ) THEN
        RAISE EXCEPTION 'sealed roster template version content is immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

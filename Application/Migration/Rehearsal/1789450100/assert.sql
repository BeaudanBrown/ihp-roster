DO $$
BEGIN
    IF (SELECT count(*) FROM app_jobs WHERE id IN (
        '10000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000003'
    )) <> 3 THEN
        RAISE EXCEPTION 'Wage-source cutover did not preserve historical jobs';
    END IF;

    IF (SELECT count(*) FROM operational_incidents
        WHERE category = 'wage_source' AND scope_key = 'global') <> 2 THEN
        RAISE EXCEPTION 'Wage-source cutover sentinel count was not source-bounded';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM operational_incidents
        WHERE category = 'wage_source'
          AND scope_key = 'global'
          AND stable_identity = 'fwc_mapd'
          AND impact_key = 'legacy_notified_cutover'
          AND safe_metadata = '{"cutover":"legacy_email_delivery_history"}'::JSONB
    ) OR NOT EXISTS (
        SELECT 1 FROM operational_incidents
        WHERE category = 'wage_source'
          AND scope_key = 'global'
          AND stable_identity = 'data_vic_public_holidays'
          AND impact_key = 'legacy_notified_cutover'
          AND safe_metadata = '{"cutover":"legacy_email_delivery_history"}'::JSONB
    ) THEN
        RAISE EXCEPTION 'Wage-source cutover omitted a legacy notification sentinel';
    END IF;

    IF (SELECT count(*) FROM operational_incident_events) <> 0
       OR (SELECT count(*) FROM operational_incident_event_recipients) <> 0
       OR (SELECT count(*) FROM app_jobs) <> 3 THEN
        RAISE EXCEPTION 'Wage-source cutover replayed historical notification activity';
    END IF;
END;
$$;

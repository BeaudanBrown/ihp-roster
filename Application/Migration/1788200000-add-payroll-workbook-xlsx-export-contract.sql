-- Payroll Workbook bytes remain in the existing text-backed export lifecycle as
-- base64. Existing rows are untouched; only ready jobs of the new type are
-- required to retain the XLSX download contract.
ALTER TABLE export_jobs
    ADD CONSTRAINT export_jobs_payroll_workbook_xlsx_contract
    CHECK (
        (export_type <> 'payroll_workbook_xlsx')
        OR (status <> 'ready')
        OR (
            (file_encoding = 'base64')
            AND (content_type IS NOT NULL)
            AND (content_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            AND (file_name IS NOT NULL)
            AND (right(file_name, 5) = '.xlsx')
        )
    );

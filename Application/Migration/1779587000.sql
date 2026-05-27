DELETE FROM public_holidays keep
USING public_holidays duplicate
WHERE keep.ctid > duplicate.ctid
  AND keep.jurisdiction = duplicate.jurisdiction
  AND keep.holiday_date = duplicate.holiday_date
  AND keep.name = duplicate.name
  AND COALESCE(keep.region, '') = COALESCE(duplicate.region, '');

CREATE UNIQUE INDEX idx_public_holidays_unique_null_safe
ON public_holidays (jurisdiction, holiday_date, name, COALESCE(region, ''));

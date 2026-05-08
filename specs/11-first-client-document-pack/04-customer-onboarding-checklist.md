# Customer Onboarding Checklist

## Sales and fit check

- Confirm the venue type and size are within current product scope.
- Confirm the customer understands the product is an early managed service, not a fully self-serve enterprise platform.
- Confirm who the venue owner / primary contact will be.

## Commercial setup

- Agree pricing and billing model.
- Send customer terms.
- Confirm business name, ABN and billing contact.
- Confirm the public Bepis billing/support page at `/PublicBillingSupport` is
  available to the customer and includes `support@bepis.lol`, terms, privacy,
  refund/dispute, and cancellation information.
- Confirm `/LegalTerms`, `/LegalPrivacy`, `/LegalRefundsDisputes`, and
  `/LegalCancellation` are populated from reviewed deployment configuration and
  no longer show placeholder legal draft values.

## Venue setup

- Create venue.
- Create initial venue owner/admin account.
- Confirm venue timezone and core configuration.
- Confirm role assignments for managers and workers.

## Data setup

- Import or create worker records.
- Confirm whether any worker records will have login access.
- Confirm roster slot names and any local operating conventions.
- Confirm leave and timesheet workflows.

## Privacy and compliance

- Provide privacy policy.
- Provide collection notice wording or instructions for worker notice.
- Confirm export recipients and whether accountant exports will be enabled.
- Record any non-standard customer requests involving personal information.
- Confirm Stripe public business information matches the customer-facing Bepis
  page before taking live payment.

## Operational setup

- Explain support model and support contact path.
- Explain what the founder may access for support and troubleshooting.
- Explain backup/export expectations.
- Explain current product limitations.

## Go-live checks

- Test login for admin user.
- Test role-restricted access.
- Test one roster edit flow.
- Test one timesheet flow.
- Test one leave request flow.
- Test one export flow if enabled.

## Handover

- Send admin instructions.
- Send support contact details.
- Record onboarding completion date.

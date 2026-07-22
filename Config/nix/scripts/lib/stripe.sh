#!/usr/bin/env bash
# Shared Stripe CLI options for local webhook forwarding.

export IHP_ROSTER_STRIPE_API_VERSION="2026-06-24.dahlia"
export IHP_ROSTER_STRIPE_WEBHOOK_EVENTS="checkout.session.completed,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed,customer.subscription.created,customer.subscription.updated,customer.subscription.deleted,invoice.payment_failed"

require_stripe_test_secret_key() {
    local key="$1"
    local caller="${2:-Stripe development tooling}"

    case "$key" in
        sk_test_*|rk_test_*)
            return 0
            ;;
        sk_live_*|rk_live_*)
            echo "$caller refuses live Stripe credentials; use a test-mode key." >&2
            return 64
            ;;
        *)
            echo "$caller requires an sk_test_ or rk_test_ Stripe credential." >&2
            return 64
            ;;
    esac
}

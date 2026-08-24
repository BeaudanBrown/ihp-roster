#!/usr/bin/env bash

stripe_dev_load_and_validate_config() {
    if [ ! -f "$PWD/.env" ]; then
        echo "Stripe development requires a local .env file with STRIPE_SECRET_KEY and STRIPE_PRICE_ID or STRIPE_PRICE_LOOKUP_KEY." >&2
        return 64
    fi

    set -a
    # shellcheck disable=SC1091
    . "$PWD/.env"
    set +a

    # The workspace owns local ports and runtime paths; .env owns only opt-in
    # Stripe configuration.
    bepis_workspace_configure

    if [ -z "${STRIPE_SECRET_KEY:-}" ]; then
        echo "Stripe development requires STRIPE_SECRET_KEY in .env." >&2
        return 64
    fi
    require_stripe_test_secret_key "$STRIPE_SECRET_KEY" "Stripe development"
    if [ "${STRIPE_MODE:-test}" != "test" ]; then
        echo "Stripe development requires STRIPE_MODE=test." >&2
        return 64
    fi
    export STRIPE_MODE="test"
    export STRIPE_BILLING_ENABLED="true"
    export STRIPE_CHECKOUT_ENABLED="${STRIPE_CHECKOUT_ENABLED:-true}"
    export STRIPE_OWNER_NAVIGATION_VISIBLE="${STRIPE_OWNER_NAVIGATION_VISIBLE:-false}"
    if [ -z "${STRIPE_PRICE_ID:-}" ] && [ -z "${STRIPE_PRICE_LOOKUP_KEY:-}" ]; then
        echo "Stripe development requires STRIPE_PRICE_ID or STRIPE_PRICE_LOOKUP_KEY in .env." >&2
        return 64
    fi
    if ! command -v stripe >/dev/null 2>&1; then
        echo "stripe CLI is not available in this shell." >&2
        return 69
    fi
}

stripe_dev_stop_listener() {
    local pid_file="$1"
    if [ ! -f "$pid_file" ]; then
        return 0
    fi

    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$pid_file"
}

stripe_dev_start_listener() {
    local state_dir="$1"
    local app_port="$2"
    local pid_file="$state_dir/stripe-listen.pid"
    local log_file="$state_dir/stripe-listen.log"

    stripe_dev_stop_listener "$pid_file"
    : > "$log_file"
    echo "[stripe-dev] launching stripe listen for pinned contract $IHP_ROSTER_STRIPE_API_VERSION" >>"$log_file"
    setsid nohup stripe listen \
        --api-key "$STRIPE_SECRET_KEY" \
        --skip-update \
        --latest \
        --events "$IHP_ROSTER_STRIPE_WEBHOOK_EVENTS" \
        --forward-to "127.0.0.1:$app_port/StripeWebhook" \
        </dev/null >>"$log_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$pid_file"
    disown "$pid" 2>/dev/null || true

    local webhook_secret=""
    for _ in $(seq 1 30); do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "stripe listen exited before printing a webhook secret; recent log output:" >&2
            tail -n 80 "$log_file" >&2 || true
            rm -f "$pid_file"
            return 1
        fi
        webhook_secret=$(grep -Eo 'whsec_[A-Za-z0-9_]+' "$log_file" | tail -n 1 || true)
        if [ -n "$webhook_secret" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$webhook_secret" ]; then
        echo "Timed out waiting for stripe listen to print a webhook secret." >&2
        echo "Run 'bash ./bin/in-env stripe login' if the Stripe CLI is not authenticated." >&2
        echo "--- recent stripe listen log ---" >&2
        tail -n 80 "$log_file" >&2 || true
        return 1
    fi

    export STRIPE_WEBHOOK_SECRET="$webhook_secret"
    # The listener prints the secret once; retain only a non-secret readiness
    # record after passing it to the application process.
    printf '%s\n' '[stripe-dev] listener ready; secret-bearing startup output discarded' >"$log_file"
}

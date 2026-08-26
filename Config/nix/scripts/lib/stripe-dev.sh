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
    STRIPE_API_KEY="$STRIPE_SECRET_KEY" setsid nohup stripe listen \
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

stripe_dev_delete_tunnel_endpoint() {
    local state_dir="$1"
    local endpoint_file="$state_dir/stripe-webhook-endpoint.id"
    if [ ! -f "$endpoint_file" ]; then
        return 0
    fi

    local endpoint_id
    endpoint_id=$(cat "$endpoint_file")
    if [ -n "$endpoint_id" ]; then
        STRIPE_API_KEY="$STRIPE_SECRET_KEY" stripe webhook_endpoints delete "$endpoint_id" --confirm >/dev/null 2>&1 \
            || echo "Warning: could not delete temporary Stripe webhook endpoint $endpoint_id." >&2
    fi
    rm -f "$endpoint_file"
}

stripe_dev_delete_stale_tunnel_endpoints() {
    local public_base_url="$1"
    local endpoint_url="$public_base_url/StripeWebhook"
    local description="Bepis ddev ephemeral pinned webhook"
    local endpoints_json
    endpoints_json=$(STRIPE_API_KEY="$STRIPE_SECRET_KEY" stripe webhook_endpoints list --limit 100)
    jq -r \
        --arg url "$endpoint_url" \
        --arg description "$description" \
        '.data[] | select(.url == $url and .description == $description) | .id' \
        <<<"$endpoints_json" \
        | while IFS= read -r endpoint_id; do
            if [ -n "$endpoint_id" ]; then
                STRIPE_API_KEY="$STRIPE_SECRET_KEY" stripe webhook_endpoints delete "$endpoint_id" --confirm >/dev/null
            fi
        done
}

stripe_dev_create_tunnel_endpoint() {
    local state_dir="$1"
    local public_base_url="$2"
    local endpoint_url="$public_base_url/StripeWebhook"
    local endpoint_file="$state_dir/stripe-webhook-endpoint.id"
    local description="Bepis ddev ephemeral pinned webhook"
    local -a event_args=()
    local -a event_names=()
    local event_name

    stripe_dev_delete_tunnel_endpoint "$state_dir"
    stripe_dev_delete_stale_tunnel_endpoints "$public_base_url"

    IFS=',' read -ra event_names <<<"$IHP_ROSTER_STRIPE_WEBHOOK_EVENTS"
    for event_name in "${event_names[@]}"; do
        event_args+=(--enabled-events "$event_name")
    done

    local endpoint_json
    endpoint_json=$(
        STRIPE_API_KEY="$STRIPE_SECRET_KEY" stripe webhook_endpoints create \
            --confirm \
            --api-version "$IHP_ROSTER_STRIPE_API_VERSION" \
            --description "$description" \
            --url "$endpoint_url" \
            "${event_args[@]}"
    )

    local endpoint_id endpoint_secret endpoint_version created_url
    endpoint_id=$(jq -r '.id // empty' <<<"$endpoint_json")
    endpoint_secret=$(jq -r '.secret // empty' <<<"$endpoint_json")
    endpoint_version=$(jq -r '.api_version // empty' <<<"$endpoint_json")
    created_url=$(jq -r '.url // empty' <<<"$endpoint_json")
    if [ -z "$endpoint_id" ] || [ -z "$endpoint_secret" ]; then
        echo "Stripe did not return the temporary webhook endpoint ID and signing secret." >&2
        return 1
    fi
    if [ "$endpoint_version" != "$IHP_ROSTER_STRIPE_API_VERSION" ] || [ "$created_url" != "$endpoint_url" ]; then
        STRIPE_API_KEY="$STRIPE_SECRET_KEY" stripe webhook_endpoints delete "$endpoint_id" --confirm >/dev/null 2>&1 || true
        echo "Stripe created the temporary webhook endpoint with an unexpected version or URL." >&2
        return 1
    fi

    umask 077
    printf '%s\n' "$endpoint_id" >"$endpoint_file"
    export STRIPE_WEBHOOK_SECRET="$endpoint_secret"
}

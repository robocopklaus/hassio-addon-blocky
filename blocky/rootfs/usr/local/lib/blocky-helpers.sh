#!/usr/bin/env bash
# ==============================================================================
# Shared helper functions for Blocky add-on scripts
# ==============================================================================

# Build a sed expression that replaces known secret values with "********".
# Reads redis.password and query_log.db_password from the add-on options.
# Usage: some_command 2>&1 | scrub_secrets
scrub_secrets() {
    local -a sed_args=()

    local redis_pw
    if bashio::config.has_value 'redis.password'; then
        redis_pw="$(bashio::config 'redis.password')"
        if [[ -n "${redis_pw}" ]]; then
            sed_args+=(-e "s/${redis_pw}/********/g")
        fi
    fi

    local db_pw
    if bashio::config.has_value 'query_log.db_password'; then
        db_pw="$(bashio::config 'query_log.db_password')"
        if [[ -n "${db_pw}" ]]; then
            sed_args+=(-e "s/${db_pw}/********/g")
        fi
    fi

    if [[ ${#sed_args[@]} -gt 0 ]]; then
        sed "${sed_args[@]}"
    else
        cat
    fi
}

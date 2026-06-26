#!/usr/bin/with-contenv bashio
# ==============================================================================
# Configure Blocky
# ==============================================================================

readonly CONFIG_PATH="/etc/blocky"
readonly ADDON_CONFIG_PATH="/config"

bashio::log.info "Configuring Blocky..."

# Create config directories
if ! mkdir -p "${CONFIG_PATH}"; then
    bashio::log.fatal "Failed to create runtime config directory: ${CONFIG_PATH}"
    exit 1
fi

if ! mkdir -p "${ADDON_CONFIG_PATH}"; then
    bashio::log.fatal "Failed to create persistent config directory: ${ADDON_CONFIG_PATH}"
    exit 1
fi

# Check if custom configuration is enabled
if bashio::config.true 'custom_config'; then
    if [ -f "${ADDON_CONFIG_PATH}/config.yml" ]; then
        # Custom config mode: preserve existing manual configuration
        bashio::log.warning "Custom config enabled: Using existing config.yml"
        bashio::log.warning "UI options are IGNORED"
        bashio::log.info "Edit config.yml in this add-on's Home Assistant /addon_configs/... folder to modify your configuration"
        bashio::log.info "Inside the add-on container, this file is /config/config.yml"
    else
        # Generate initial config for first run
        bashio::log.info "Custom config enabled: Generating initial configuration..."
        if ! tempio \
            -conf /data/options.json \
            -template /usr/share/tempio/blocky.gtpl \
            -out "${ADDON_CONFIG_PATH}/config.yml"; then
            bashio::log.fatal "Failed to generate initial configuration with tempio"
            exit 1
        fi

        if [ ! -f "${ADDON_CONFIG_PATH}/config.yml" ] || [ ! -s "${ADDON_CONFIG_PATH}/config.yml" ]; then
            bashio::log.fatal "Configuration file was not created or is empty"
            exit 1
        fi

        if ! blocky validate --config "${ADDON_CONFIG_PATH}/config.yml"; then
            bashio::log.fatal "Generated initial configuration is invalid"
            rm -f "${ADDON_CONFIG_PATH}/config.yml"
            exit 1
        fi

        bashio::log.info "Initial config created. You can now customize config.yml in this add-on's Home Assistant /addon_configs/... folder"
        bashio::log.info "Inside the add-on container, this file is /config/config.yml"
    fi
else
    # Standard mode: always regenerate configuration from addon options
    bashio::log.info "Generating configuration from addon options..."
    if ! tempio \
        -conf /data/options.json \
        -template /usr/share/tempio/blocky.gtpl \
        -out "${ADDON_CONFIG_PATH}/config.yml"; then
        bashio::log.fatal "Failed to generate configuration with tempio"
        exit 1
    fi

    if [ ! -f "${ADDON_CONFIG_PATH}/config.yml" ] || [ ! -s "${ADDON_CONFIG_PATH}/config.yml" ]; then
        bashio::log.fatal "Configuration file was not created or is empty"
        exit 1
    fi

    if ! blocky validate --config "${ADDON_CONFIG_PATH}/config.yml"; then
        bashio::log.fatal "Generated configuration is invalid"
        exit 1
    fi
fi

# Copy the generated config to the runtime location
if ! cp "${ADDON_CONFIG_PATH}/config.yml" "${CONFIG_PATH}/config.yml"; then
    bashio::log.fatal "Failed to copy configuration to runtime location"
    exit 1
fi

if ! chmod 600 "${ADDON_CONFIG_PATH}/config.yml" "${CONFIG_PATH}/config.yml"; then
    bashio::log.fatal "Failed to set restrictive permissions on configuration files"
    exit 1
fi

# upstreams is a CORE feature (ADR-0002): without a "default" group that has a
# resolver, Blocky starts but cannot resolve DNS, and `blocky validate` does NOT
# catch it. Fail-fast here. This text-parses the rendered config, so it runs in
# Standard Mode only (ADR-0004); a hand-written custom config is the operator's
# own responsibility and Blocky's startup logging surfaces upstream errors there.
if ! bashio::config.true 'custom_config'; then
    # shellcheck source=/dev/null
    source /usr/lib/blocky/guards.sh
    if ! upstreams_default_has_resolver "${CONFIG_PATH}/config.yml"; then
        bashio::log.fatal "No 'default' upstream group with a resolver was found in the generated configuration."
        bashio::log.fatal "Blocky cannot resolve DNS without it. Set upstreams → groups → a 'default' group with at least one resolver in the add-on options."
        exit 1
    fi

    # Prepare on-disk query log storage. CSV/csv-client write daily-rotating
    # files into a target DIRECTORY; sqlite writes a single database FILE whose
    # parent directory must exist. Both must stay under /config/ for persistence.
    #
    # The guards read the effective target straight from the RENDERED config (the
    # single source of truth, see ADR-0002) and encapsulate the type/path parsing,
    # so this block holds only filesystem side effects. The parse is format-coupled
    # and runs in Standard Mode only (ADR-0004): a hand-written custom config may
    # use a YAML shape the parser was never built for, and a fail-fast guard must
    # never abort a correct config — Blocky's own logging surfaces errors there.
    QUERY_LOG_TARGET="$(query_log_target "${CONFIG_PATH}/config.yml")"
    if [ -n "${QUERY_LOG_TARGET}" ]; then
        if ! query_log_target_is_safe "${QUERY_LOG_TARGET}"; then
            bashio::log.fatal "Query log target must be a path under /config/ with no '..': ${QUERY_LOG_TARGET}"
            exit 1
        fi

        QUERY_LOG_DIR="$(query_log_dir "${CONFIG_PATH}/config.yml")"
        bashio::log.info "Creating query log directory: ${QUERY_LOG_DIR}"
        if ! mkdir -p "${QUERY_LOG_DIR}"; then
            bashio::log.fatal "Failed to create query log directory: ${QUERY_LOG_DIR}"
            exit 1
        fi

        # Verify canonical path stays within /config/ (catches symlink attacks).
        # Reuse the same containment rule as the target check so the /config
        # policy lives in exactly one place (realpath output carries no '..').
        CANONICAL_PATH=$(realpath "${QUERY_LOG_DIR}")
        if ! query_log_target_is_safe "${CANONICAL_PATH}"; then
            bashio::log.fatal "Query log directory resolves outside /config/: ${CANONICAL_PATH}"
            exit 1
        fi

        if [ ! -w "${QUERY_LOG_DIR}" ]; then
            bashio::log.fatal "Query log directory is not writable: ${QUERY_LOG_DIR}"
            exit 1
        fi
    fi
fi

# HTTPS/DoH is a side feature (ADR-0002): when enabled without a certificate the
# template drops it rather than open :443 with no cert (which would crash Blocky).
# Warn so the degrade is not silent. DNS resolution is unaffected.
if bashio::config.true 'https.enable' || bashio::config.true 'http3.enable'; then
    if ! bashio::config.has_value 'https.cert_file' || ! bashio::config.has_value 'https.key_file'; then
        bashio::log.warning "HTTPS/DoH/HTTP3 requested but cert_file and key_file are not both set."
        bashio::log.warning "TLS is disabled and port 443 will not be opened. DNS resolution continues normally."
    fi
fi

# client_lookup.single_name_order only has meaning together with an upstream
# (it orders the rDNS lookup results). The template drops it when no upstream is
# set (ADR-0002 degrade); warn so the operator knows their setting was ignored.
# Count the array directly: has_value treats an empty list as "present".
SINGLE_NAME_ORDER_COUNT=$(jq -r '(.client_lookup.single_name_order // []) | length' /data/options.json 2>/dev/null || echo 0)
if [ "${SINGLE_NAME_ORDER_COUNT}" -gt 0 ] && ! bashio::config.has_value 'client_lookup.upstream'; then
    bashio::log.warning "client_lookup.single_name_order is set but client_lookup.upstream is missing; single_name_order is ignored."
fi

# Create the on-disk block list download cache directory when enabled.
# Internal, regenerable state -> lives under /data (add-on-private), see ADR-0001.
if bashio::config.true 'blocking.download_cache'; then
    readonly LIST_CACHE_DIR="/data/cache/lists"
    bashio::log.info "Creating block list download cache directory: ${LIST_CACHE_DIR}"
    if ! mkdir -p "${LIST_CACHE_DIR}"; then
        bashio::log.fatal "Failed to create list download cache directory: ${LIST_CACHE_DIR}"
        exit 1
    fi
fi

bashio::log.info "Configuration complete!"

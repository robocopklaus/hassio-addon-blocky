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

# Prepare on-disk query log storage. CSV/csv-client write daily-rotating files
# into a target DIRECTORY; sqlite writes a single database FILE whose parent
# directory must exist. Both must stay under /config/ for persistence.
QUERY_LOG_TYPE=$(bashio::config 'query_log.type')
QUERY_LOG_PATH=""

case "${QUERY_LOG_TYPE}" in
    csv | csv-client)
        # target is the directory that holds the daily-rotating files
        if bashio::config.has_value 'query_log.target'; then
            QUERY_LOG_PATH=$(bashio::config 'query_log.target')
        else
            QUERY_LOG_PATH="/config/query_logs"
        fi
        ;;
    sqlite)
        # target is the database file; default must match the blocky.gtpl fallback
        if bashio::config.has_value 'query_log.target'; then
            QUERY_LOG_PATH=$(bashio::config 'query_log.target')
        else
            QUERY_LOG_PATH="/config/querylog.db"
        fi
        ;;
esac

if [ -n "${QUERY_LOG_PATH}" ]; then
    # Validate the full target path (the value Blocky writes to) to prevent
    # directory traversal and keep query logs under /config/.
    if [[ "${QUERY_LOG_PATH}" == *".."* ]]; then
        bashio::log.fatal "Query log target contains '..': ${QUERY_LOG_PATH}"
        bashio::log.fatal "Path traversal is not allowed for query logs."
        exit 1
    elif [[ "${QUERY_LOG_PATH}" != /config && "${QUERY_LOG_PATH}" != /config/* ]]; then
        bashio::log.fatal "Query log target must be under /config/: ${QUERY_LOG_PATH}"
        exit 1
    fi

    # sqlite target is a file -> create its parent dir; csv target is the dir itself
    if [[ "${QUERY_LOG_TYPE}" == "sqlite" ]]; then
        QUERY_LOG_DIR=$(dirname "${QUERY_LOG_PATH}")
    else
        QUERY_LOG_DIR="${QUERY_LOG_PATH}"
    fi

    bashio::log.info "Creating query log directory: ${QUERY_LOG_DIR}"
    if ! mkdir -p "${QUERY_LOG_DIR}"; then
        bashio::log.fatal "Failed to create query log directory: ${QUERY_LOG_DIR}"
        exit 1
    fi

    # Verify canonical path stays within /config/ (catches symlink attacks)
    CANONICAL_PATH=$(realpath "${QUERY_LOG_DIR}")
    if [[ "${CANONICAL_PATH}" != /config && "${CANONICAL_PATH}" != /config/* ]]; then
        bashio::log.fatal "Query log directory resolves outside /config/: ${CANONICAL_PATH}"
        exit 1
    fi

    if [ ! -w "${QUERY_LOG_DIR}" ]; then
        bashio::log.fatal "Query log directory is not writable: ${QUERY_LOG_DIR}"
        exit 1
    fi
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

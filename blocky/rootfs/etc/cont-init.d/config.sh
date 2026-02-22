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
        bashio::log.info "Edit /addon_config/<repository>_blocky/config.yml to modify your configuration"
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

        bashio::log.info "Initial config created. You can now customize /addon_config/<repository>_blocky/config.yml"
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

# Create query log directory if CSV logging is enabled
if bashio::config.has_value 'query_log.target'; then
    QUERY_LOG_TARGET=$(bashio::config 'query_log.target')
    QUERY_LOG_TYPE=$(bashio::config 'query_log.type')

    if [[ "${QUERY_LOG_TYPE}" == "csv" ]] || [[ "${QUERY_LOG_TYPE}" == "csv-client" ]]; then
        # Validate target path to prevent directory traversal
        if [[ "${QUERY_LOG_TARGET}" == *".."* ]]; then
            bashio::log.fatal "Query log target contains '..': ${QUERY_LOG_TARGET}"
            bashio::log.fatal "Path traversal is not allowed for CSV query logs."
            exit 1
        elif [[ "${QUERY_LOG_TARGET}" != /config/* ]]; then
            bashio::log.fatal "Query log target must be under /config/: ${QUERY_LOG_TARGET}"
            exit 1
        else
            bashio::log.info "Creating query log directory: ${QUERY_LOG_TARGET}"
            if mkdir -p "${QUERY_LOG_TARGET}"; then
                # Verify canonical path stays within /config/ (catches symlink attacks)
                CANONICAL_PATH=$(realpath "${QUERY_LOG_TARGET}")
                if [[ "${CANONICAL_PATH}" != /config && "${CANONICAL_PATH}" != /config/* ]]; then
                    bashio::log.fatal "Query log directory resolves outside /config/: ${CANONICAL_PATH}"
                    exit 1
                fi
            else
                bashio::log.fatal "Failed to create query log directory: ${QUERY_LOG_TARGET}"
                exit 1
            fi

            if [ ! -w "${QUERY_LOG_TARGET}" ]; then
                bashio::log.fatal "Query log directory is not writable: ${QUERY_LOG_TARGET}"
                exit 1
            fi
        fi
    fi
fi

bashio::log.info "Configuration complete!"

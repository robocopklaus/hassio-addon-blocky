#!/usr/bin/with-contenv bashio
# ==============================================================================
# Configure Blocky
# ==============================================================================

readonly CONFIG_PATH="/etc/blocky"
readonly ADDON_CONFIG_PATH="/config"

bashio::log.info "Configuring Blocky..."

# Create config directories
mkdir -p "${CONFIG_PATH}"
mkdir -p "${ADDON_CONFIG_PATH}"

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

        # Validate the generated configuration
        bashio::log.info "Validating generated configuration..."
        if blocky validate --config "${ADDON_CONFIG_PATH}/config.yml" 2>&1; then
            bashio::log.info "Configuration validation passed"
        else
            bashio::log.warning "Configuration validation reported issues - review your config"
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
fi

# Copy the generated config to the runtime location
if ! cp "${ADDON_CONFIG_PATH}/config.yml" "${CONFIG_PATH}/config.yml"; then
    bashio::log.fatal "Failed to copy configuration to runtime location"
    exit 1
fi

# Create query log directory if CSV logging is enabled
if bashio::config.has_value 'query_log.target'; then
    QUERY_LOG_TARGET=$(bashio::config 'query_log.target')
    QUERY_LOG_TYPE=$(bashio::config 'query_log.type')

    if [[ "${QUERY_LOG_TYPE}" == "csv" ]] || [[ "${QUERY_LOG_TYPE}" == "csv-client" ]]; then
        bashio::log.info "Creating query log directory: ${QUERY_LOG_TARGET}"
        if ! mkdir -p "${QUERY_LOG_TARGET}"; then
            bashio::log.warning "Failed to create query log directory: ${QUERY_LOG_TARGET}"
        fi
    fi
fi

bashio::log.info "Configuration complete!"
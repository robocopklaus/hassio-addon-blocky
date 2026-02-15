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
        bashio::log.warning "All UI configuration options are being IGNORED"
        bashio::log.warning "Any changes made in the UI will have NO effect"
        bashio::log.info "Edit /addon_config/<repository>_blocky/config.yml to modify your configuration"
        bashio::log.info "To return to UI-based configuration, disable 'Custom Configuration Mode' and restart"
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

        bashio::log.info "Initial config created. You can now customize /addon_config/<repository>_blocky/config.yml"
    fi

    # Create a persistent Home Assistant notification to warn the user
    bashio::log.info "Creating persistent notification for custom config mode..."
    if bashio::api.supervisor POST /core/api/services/persistent_notification/create \
        "$(bashio::var.json \
            title "Blocky: Custom Configuration Mode Active" \
            message "The Blocky add-on is running in **custom configuration mode**. All settings configured in the add-on UI are being **ignored**. To make changes, edit the configuration file directly at \`/addon_config/local_blocky/config.yml\`. To return to UI-based configuration, disable **Custom Configuration Mode** in the add-on settings and restart." \
            notification_id "blocky_custom_config_warning" \
        )"; then
        bashio::log.info "Persistent notification created"
    else
        bashio::log.warning "Could not create persistent notification (non-critical)"
    fi
else
    # Standard mode: dismiss any previous custom config notification
    bashio::api.supervisor POST /core/api/services/persistent_notification/dismiss \
        "$(bashio::var.json notification_id "blocky_custom_config_warning")" \
        2>/dev/null || true

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
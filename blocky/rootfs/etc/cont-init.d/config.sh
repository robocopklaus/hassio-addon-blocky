#!/usr/bin/with-contenv bashio
# ==============================================================================
# Configure Blocky
# ==============================================================================

readonly CONFIG_PATH="/etc/blocky"
readonly ADDON_CONFIG_PATH="/config"
readonly OPTIONS_JSON="/data/options.json"
readonly MIGRATED_OPTIONS_JSON="/tmp/migrated_options.json"

bashio::log.info "Configuring Blocky..."

# Create config directories
mkdir -p "${CONFIG_PATH}"
mkdir -p "${ADDON_CONFIG_PATH}"

# ==============================================================================
# Backward Compatibility: Detect and migrate v1.0.0 configuration
# ==============================================================================

migrate_v1_to_v2() {
    bashio::log.warning "════════════════════════════════════════════════════════"
    bashio::log.warning "Detected v1.0.0 configuration format"
    bashio::log.warning "Automatically converting to v2.0.0 format..."
    bashio::log.warning "Please reconfigure via UI when convenient to access new features"
    bashio::log.warning "════════════════════════════════════════════════════════"

    # Read the current options
    local options
    options=$(cat "${OPTIONS_JSON}")

    # Start building the new configuration
    local new_config
    new_config=$(jq -n '{}')

    # Migrate upstreams
    if echo "${options}" | jq -e '.upstream_dns' > /dev/null 2>&1; then
        local upstream_dns
        upstream_dns=$(echo "${options}" | jq '.upstream_dns // []')
        new_config=$(echo "${new_config}" | jq --argjson resolvers "${upstream_dns}" '
            .upstreams = {
                groups: [{name: "default", resolvers: $resolvers}],
                init_strategy: "blocking",
                strategy: "parallel_best",
                timeout: "2s"
            }
        ')
    else
        new_config=$(echo "${new_config}" | jq '.upstreams = {
            groups: [{name: "default", resolvers: ["tcp-tls:one.one.one.one", "tcp-tls:dns.google"]}],
            init_strategy: "blocking",
            strategy: "parallel_best",
            timeout: "2s"
        }')
    fi

    # Migrate bootstrap
    if echo "${options}" | jq -e '.bootstrap_dns' > /dev/null 2>&1; then
        local bootstrap_dns
        bootstrap_dns=$(echo "${options}" | jq '.bootstrap_dns // []')
        new_config=$(echo "${new_config}" | jq --argjson dns "${bootstrap_dns}" '
            .bootstrap = {dns: $dns}
        ')
    else
        new_config=$(echo "${new_config}" | jq '.bootstrap = {dns: ["1.1.1.1", "8.8.8.8"]}')
    fi

    # Migrate deny_lists to blocking.denylists
    if echo "${options}" | jq -e '.deny_lists' > /dev/null 2>&1; then
        local deny_lists
        deny_lists=$(echo "${options}" | jq '[.deny_lists[] | {name: .group, sources: .entries}]')
        new_config=$(echo "${new_config}" | jq --argjson denylists "${deny_lists}" '
            .blocking.denylists = $denylists
        ')
    else
        new_config=$(echo "${new_config}" | jq '.blocking.denylists = [{name: "ads", sources: ["https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"]}]')
    fi

    # Migrate client_groups_block
    if echo "${options}" | jq -e '.client_groups_block' > /dev/null 2>&1; then
        local client_groups
        client_groups=$(echo "${options}" | jq '[.client_groups_block[] | {name: .client, lists: .groups}]')
        new_config=$(echo "${new_config}" | jq --argjson groups "${client_groups}" '
            .blocking.client_groups_block = $groups
        ')
    else
        new_config=$(echo "${new_config}" | jq '.blocking.client_groups_block = [{name: "default", lists: ["ads"]}]')
    fi

    # Add blocking defaults
    new_config=$(echo "${new_config}" | jq '
        .blocking.allowlists = [] |
        .blocking.block_type = "zeroIp" |
        .blocking.block_ttl = "6h"
    ')

    # Migrate conditional_mapping
    if echo "${options}" | jq -e '.conditional_mapping' > /dev/null 2>&1; then
        local conditional_mapping
        conditional_mapping=$(echo "${options}" | jq '.conditional_mapping // []')
        new_config=$(echo "${new_config}" | jq --argjson mapping "${conditional_mapping}" '
            .conditional = {
                rewrite: [],
                mapping: $mapping,
                fallback_upstream: false
            }
        ')
    else
        new_config=$(echo "${new_config}" | jq '.conditional = {rewrite: [], mapping: [], fallback_upstream: false}')
    fi

    # Migrate client_lookup_upstream
    if echo "${options}" | jq -e '.client_lookup_upstream' > /dev/null 2>&1; then
        local client_lookup_upstream
        client_lookup_upstream=$(echo "${options}" | jq -r '.client_lookup_upstream // ""')
        new_config=$(echo "${new_config}" | jq --arg upstream "${client_lookup_upstream}" '
            .client_lookup = {
                upstream: $upstream,
                single_name_order: [],
                clients: []
            }
        ')
    else
        new_config=$(echo "${new_config}" | jq '.client_lookup = {upstream: "", single_name_order: [], clients: []}')
    fi

    # Migrate caching (preserve v1.0.0 values to maintain performance)
    if echo "${options}" | jq -e '.caching' > /dev/null 2>&1; then
        local caching
        caching=$(echo "${options}" | jq '.caching')
        # Preserve existing caching config, add new field cache_time_negative
        new_config=$(echo "${new_config}" | jq --argjson caching "${caching}" '
            .caching = ($caching + {cache_time_negative: ($caching.cache_time_negative // "30m")})
        ')
    else
        # Use v1.0.0 defaults to maintain performance
        new_config=$(echo "${new_config}" | jq '.caching = {
            min_time: "5m",
            max_time: "30m",
            prefetching: true,
            cache_time_negative: "30m"
        }')
    fi

    # Add new v2.0.0 features with defaults
    new_config=$(echo "${new_config}" | jq '
        .filtering = {query_types: []} |
        .fqdn_only = {enable: false} |
        .custom_dns = {
            mapping: [],
            rewrite: [],
            custom_ttl: "1h",
            filter_unmapped_types: true
        } |
        .redis = {
            address: "",
            username: "",
            password: "",
            database: 0,
            required: false,
            connection_attempts: 3,
            connection_cooldown: "1s"
        } |
        .prometheus = {
            enable: false,
            path: "/metrics"
        } |
        .log = {
            level: "info",
            timestamp: true,
            privacy: false
        }
    ')

    # Preserve custom_config flag
    local custom_config
    custom_config=$(echo "${options}" | jq '.custom_config // false')
    new_config=$(echo "${new_config}" | jq --argjson custom_config "${custom_config}" '
        .custom_config = $custom_config
    ')

    # Write migrated configuration
    echo "${new_config}" > "${MIGRATED_OPTIONS_JSON}"

    bashio::log.info "✓ Configuration automatically converted"
    return 0
}

# Detect if we have v1.0.0 format (check for old field names)
if bashio::config.exists 'upstream_dns' || \
   bashio::config.exists 'deny_lists' || \
   bashio::config.exists 'bootstrap_dns' || \
   bashio::config.exists 'client_groups_block'; then
    # Migrate the configuration
    if ! migrate_v1_to_v2; then
        bashio::log.fatal "Failed to migrate v1.0.0 configuration to v2.0.0"
        exit 1
    fi
    # Use migrated config for tempio
    readonly EFFECTIVE_OPTIONS="${MIGRATED_OPTIONS_JSON}"
else
    # Use original config (already v2.0.0 format)
    readonly EFFECTIVE_OPTIONS="${OPTIONS_JSON}"
fi

# ==============================================================================
# Configuration Generation
# ==============================================================================

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
            -conf "${EFFECTIVE_OPTIONS}" \
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
else
    # Standard mode: always regenerate configuration from addon options
    bashio::log.info "Generating configuration from addon options..."
    if ! tempio \
        -conf "${EFFECTIVE_OPTIONS}" \
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

# Create data directory for query logs and cache
mkdir -p /data/blocky

bashio::log.info "Configuration complete!"

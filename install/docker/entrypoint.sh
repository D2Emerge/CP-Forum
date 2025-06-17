#!/bin/bash

set -e

# Function to set default values for environment variables
set_defaults() {
  export CONFIG_DIR="${CONFIG_DIR:-/opt/config}"
  export CONFIG="$CONFIG_DIR/config.json"
  export NODEBB_INIT_VERB="${NODEBB_INIT_VERB:-install}"
  export NODEBB_BUILD_VERB="${NODEBB_BUILD_VERB:-build}"
  export START_BUILD="${START_BUILD:-${FORCE_BUILD_BEFORE_START:-true}}"
  export SETUP="${SETUP:-}"
  export PACKAGE_MANAGER="${PACKAGE_MANAGER:-npm}"
  export OVERRIDE_UPDATE_LOCK="${OVERRIDE_UPDATE_LOCK:-false}"
}

# Function to check if a directory exists and is writable
check_directory() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "Error: Directory $dir does not exist. Creating..."
    mkdir -p "$dir" || {
      echo "Error: Failed to create directory $dir"
      exit 1
    }
  fi
  if [ ! -w "$dir" ]; then
    echo "Warning: No write permission for directory $dir, attempting to fix..."
    chown -R $USER:$USER "$dir" || true # attempt to change ownership, do not exit on failure
    chmod -R 760 "$dir" || true # attempt to change permissions, do not exit on failure
    if [ ! -w "$dir" ]; then
      echo "Error: No write permission for directory $dir. Exiting..."
      exit 1
    fi
  fi
}

# Function to copy or link package.json and lock files based on package manager
copy_or_link_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local package_manager="$3"
  local lock_file

  case "$package_manager" in
    yarn) lock_file="yarn.lock" ;;
    npm) lock_file="package-lock.json" ;;
    pnpm) lock_file="pnpm-lock.yaml" ;;
    *)
      echo "Unknown package manager: $package_manager"
      exit 1
      ;;
  esac

  # Check if source and destination files are the same
  if [ "$(realpath "$src_dir/package.json")" != "$(realpath "$dest_dir/package.json")" ] || [ "$OVERRIDE_UPDATE_LOCK" = true ]; then
    cp "$src_dir/package.json" "$dest_dir/package.json"
  fi

  if [ -f "$src_dir/$lock_file" ] && ([ "$(realpath "$src_dir/$lock_file")" != "$(realpath "$dest_dir/$lock_file")" ] || [ "$OVERRIDE_UPDATE_LOCK" = true ]); then
    cp "$src_dir/$lock_file" "$dest_dir/$lock_file"
  fi

  # Remove unnecessary lock files in src_dir
  rm -f "$src_dir/"{yarn.lock,package-lock.json,pnpm-lock.yaml}

  # Symbolically link the copied files in src_dir to dest_dir
  ln -fs "$dest_dir/package.json" "$src_dir/package.json"
  if [ -f "$dest_dir/$lock_file" ]; then
    ln -fs "$dest_dir/$lock_file" "$src_dir/$lock_file"
  fi
}

# Function to install dependencies
install_dependencies() {
  case "$PACKAGE_MANAGER" in
    yarn) yarn install || {
      echo "Failed to install dependencies with yarn"
      exit 1
    } ;;
    npm) npm install || {
      echo "Failed to install dependencies with npm"
      exit 1
    } ;;
    pnpm) pnpm install || {
      echo "Failed to install dependencies with pnpm"
      exit 1
    } ;;
    *)
      echo "Unknown package manager: $PACKAGE_MANAGER"
      exit 1
      ;;
  esac
}

# Function to create DocumentDB optimized configuration
create_documentdb_config() {
  local config="$1"
  
  # Environment variables with defaults
  local site_url="${SITE_URL:-https://forum.codeproject.com}"
  local secret="${NODEBB_SECRET:-$(date +%s | sha256sum | base64 | head -c 32)}"
  local db_port="${NODEBB_DB_PORT:-27017}"
  local app_port="${PORT:-4567}"
  local auth_source="${NODEBB_DB_AUTH_SOURCE:-admin}"
  local session_secret="${SESSION_SECRET:-$(date +%s | sha256sum | base64 | head -c 32)}"
  
  echo "Creating DocumentDB optimized configuration..."
  
  cat > "$config" << CONFIG_EOF
{
  "url": "$site_url",
  "secret": "$secret",
  "database": "mongo",
  "mongo": {
    "host": "$NODEBB_DB_HOST",
    "port": $db_port,
    "database": "$NODEBB_DB_NAME",
    "username": "$NODEBB_DB_USER",
    "password": "$NODEBB_DB_PASSWORD",
    "options": {
      "authSource": "$auth_source",
      "ssl": ${NODEBB_DB_SSL:-true},
      "tlsInsecure": true,
      "sslCA": null,
      "retryWrites": false,
      "readPreference": "primary",
      "maxPoolSize": 10,
      "minPoolSize": 2,
      "maxIdleTimeMS": 30000,
      "serverSelectionTimeoutMS": 5000,
      "socketTimeoutMS": 45000,
      "connectTimeoutMS": 10000,
      "heartbeatFrequencyMS": 10000,
      "w": "majority",
      "journal": true,
      "readConcern": {"level": "local"},
      "writeConcern": {
        "w": "majority",
        "j": true,
        "wtimeout": 10000
      }
    }
  },
  "port": $app_port,
  "bind_address": "0.0.0.0",
  "session_secret": "$session_secret",
  "sessionStore": {
    "name": "database"
  },
  "cluster": {
    "port": $app_port
  },
  "upload_path": "/usr/src/app/public/uploads",
  "maximum_upload_size": 10485760,
  "socket.io": {
    "transports": ["polling", "websocket"],
    "origins": "$site_url:*"
  },
  "sessionKey": "nodebb.sid",
  "cookieDomain": "",
  "secureCookie": true,
  "cors": {
    "origin": true,
    "credentials": true
  }
}
CONFIG_EOF

  echo "✓ DocumentDB configuration created with optimized settings"
  echo "  - SSL enabled with tlsInsecure=true (DocumentDB requirement)"
  echo "  - retryWrites disabled (DocumentDB limitation)"
  echo "  - Optimized connection pool settings"
  echo "  - Primary read preference for DocumentDB"
  echo "  - Simplified options for NodeBB v4.4.3 compatibility"
  
  # Copy to working directory for NodeBB compatibility
  cp "$config" /usr/src/app/config.json
  echo "✓ Copied config.json to /usr/src/app/"
}

# Function to start setup session
start_setup_session() {
  local config="$1"
  echo "Starting setup session"
  exec /usr/src/app/nodebb setup --config="$config"
}

# Handle building and upgrading NodeBB
build_forum() {
  local config="$1"
  local start_build="$2"
  local package_hash=$(md5sum install/package.json | head -c 32)
  if [ "$package_hash" = "$(cat $CONFIG_DIR/install_hash.md5 2>/dev/null || true)" ]; then
      echo "package.json was updated. Upgrading..."
      /usr/src/app/nodebb upgrade --config="$config" || {
          echo "Failed to upgrade NodeBB. Exiting..."
          exit 1
        }
  elif [ "$start_build" = true ]; then
    echo "Build before start is enabled. Building..."
    /usr/src/app/nodebb "${NODEBB_BUILD_VERB}" --config="$config" || {
        echo "Failed to build NodeBB. Exiting..."
        exit 1
      }
  else
    echo "No changes in package.json. Skipping build..."
    return
  fi
  echo -n $package_hash > $CONFIG_DIR/install_hash.md5
  
  # Reset plugins if this is NodeBB 4.4.3 to fix potential jQuery issues
  reset_plugins_if_needed "$config"
}

# Function to reset plugins if needed (fixes jQuery issues in NodeBB 4.4.3)
reset_plugins_if_needed() {
  local config="$1"
  
  # Check NodeBB version
  local nodebb_version=$(node -e "console.log(require('./package.json').version)" 2>/dev/null || echo "unknown")
  
  if [[ "$nodebb_version" == "4.4.3" ]] || [[ "$nodebb_version" == "4.4"* ]]; then
    echo "🔧 NodeBB v$nodebb_version detected - checking for plugin conflicts..."
    
    if [ -f "./nodebb" ]; then
      echo "Running plugin reset to ensure clean state (addresses jQuery issues)..."
      echo "y" | /usr/src/app/nodebb reset -p --config="$config" 2>/dev/null || true
      echo "✓ Plugin reset completed"
    fi
  fi
}

# Function to start forum
start_forum() {
  local config="$1"
  local start_build="$2"

  build_forum "$config" "$start_build"

  echo "🚀 Starting NodeBB with DocumentDB optimizations..."
  
  # Use direct node execution for better DocumentDB compatibility
  exec node app.js --config="$config"
}

# Function to start installation session
start_installation_session() {
  local nodebb_init_verb="$1"
  local config="$2"

  echo "Config file not found at $config"
  echo "Starting installation session"
  exec /usr/src/app/nodebb "$nodebb_init_verb" --config="$config"
}

# Function for debugging and logging
debug_log() {
  local message="$1"
  echo "DEBUG: $message"
}

# Main function
main() {
  set_defaults
  check_directory "$CONFIG_DIR"
  copy_or_link_files /usr/src/app "$CONFIG_DIR" "$PACKAGE_MANAGER"
  install_dependencies

  debug_log "PACKAGE_MANAGER: $PACKAGE_MANAGER"
  debug_log "CONFIG location: $CONFIG"
  debug_log "START_BUILD: $START_BUILD"

  if [ -n "$SETUP" ]; then
    start_setup_session "$CONFIG"
  fi

  # Always create DocumentDB optimized config
  create_documentdb_config "$CONFIG"

  if [ -f "$CONFIG" ]; then
    start_forum "$CONFIG" "$START_BUILD"
  else
    start_installation_session "$NODEBB_INIT_VERB" "$CONFIG"
  fi
}

# Execute main function
main "$@"
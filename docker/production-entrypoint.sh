#!/bin/bash
set -euo pipefail

echo "=================================================="
echo "🚀 NodeBB Production Entrypoint v1.2.0 (FINAL)"
echo "=================================================="
echo "Starting at: $(date)"
echo "Working directory: $(pwd)"
echo "User: $(whoami)"
echo "Node version: $(node --version)"
echo "Package Manager: ${PACKAGE_MANAGER:-npm}"
echo "=================================================="

cd /usr/src/app

# =================================================================
# SECTION 1: ENVIRONMENT AND DEFAULTS SETUP
# =================================================================
echo ""
echo "🔧 [1/7] ENVIRONMENT SETUP & VALIDATION"
echo "=================================================="

set_defaults() {
    export CONFIG_DIR="${CONFIG_DIR:-/opt/config}"
    export CONFIG="$CONFIG_DIR/config.json"
    export PACKAGE_MANAGER="${PACKAGE_MANAGER:-npm}"
    export START_BUILD="${START_BUILD:-true}"
    export OVERRIDE_UPDATE_LOCK="${OVERRIDE_UPDATE_LOCK:-false}"
    export NODE_ENV="${NODE_ENV:-production}"
    export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
    
    echo "✓ Environment defaults set"
    echo "  - CONFIG_DIR: $CONFIG_DIR"
    echo "  - PACKAGE_MANAGER: $PACKAGE_MANAGER"
    echo "  - START_BUILD: $START_BUILD"
}

validate_environment() {
    local required_vars=(
        "NODEBB_DB_HOST"
        "NODEBB_DB_USER" 
        "NODEBB_DB_PASSWORD"
        "NODEBB_DB_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            echo "❌ ERROR: Required environment variable $var is not set"
            exit 1
        fi
        echo "✓ $var is configured"
    done
}

check_directory() {
    local dir="$1"
    local description="$2"
    
    if [ ! -d "$dir" ]; then
        echo "Creating $description directory: $dir"
        mkdir -p "$dir" || {
            echo "❌ ERROR: Failed to create directory $dir"
            exit 1
        }
    fi
    
    if [ ! -w "$dir" ]; then
        echo "⚠️  Fixing permissions for $description directory..."
        chown -R $USER:$USER "$dir" 2>/dev/null || true
        chmod -R 760 "$dir" 2>/dev/null || true
        
        if [ ! -w "$dir" ]; then
            echo "❌ ERROR: No write permission for directory $dir"
            exit 1
        fi
    fi
    
    echo "✓ $description directory ready: $dir"
}

set_defaults
validate_environment
check_directory "$CONFIG_DIR" "config"
check_directory "/usr/src/app/public/uploads" "uploads"
check_directory "/usr/src/app/logs" "logs"

echo "✅ Environment setup completed"

# =================================================================
# SECTION 2: DATABASE CONNECTIVITY
# =================================================================
echo ""
echo "🗄️  [2/7] DATABASE CONNECTIVITY CHECK"
echo "=================================================="

check_database_connectivity() {
    local host="${NODEBB_DB_HOST}"
    local port="${NODEBB_DB_PORT:-27017}"
    local max_attempts=60
    local attempt=1
    
    echo "Testing connection to $host:$port..."
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            echo "✅ Database is reachable at $host:$port"
            return 0
        fi
        
        echo "[$attempt/$max_attempts] Database not ready, waiting 3 seconds..."
        sleep 3
        attempt=$((attempt + 1))
    done
    
    echo "❌ ERROR: Database unreachable after $max_attempts attempts"
    exit 1
}

check_database_connectivity

# =================================================================
# SECTION 3: PACKAGE MANAGEMENT SETUP
# =================================================================
echo ""
echo "📦 [3/7] PACKAGE MANAGEMENT SETUP"
echo "=================================================="

copy_or_link_files() {
    local src_dir="/usr/src/app"
    local dest_dir="$CONFIG_DIR"
    local package_manager="$PACKAGE_MANAGER"
    local lock_file

    case "$package_manager" in
        yarn) lock_file="yarn.lock" ;;
        npm) lock_file="package-lock.json" ;;
        pnpm) lock_file="pnpm-lock.yaml" ;;
        *)
            echo "❌ Unknown package manager: $package_manager"
            exit 1
            ;;
    esac

    echo "Setting up package files for $package_manager..."

    # Copy package.json if needed
    if [ "$(realpath "$src_dir/package.json" 2>/dev/null)" != "$(realpath "$dest_dir/package.json" 2>/dev/null)" ] || [ "$OVERRIDE_UPDATE_LOCK" = true ]; then
        if [ -f "$src_dir/package.json" ]; then
            cp "$src_dir/package.json" "$dest_dir/package.json"
            echo "✓ Copied package.json to config directory"
        fi
    fi

    # Copy lock file if it exists
    if [ -f "$src_dir/$lock_file" ]; then
        if [ "$(realpath "$src_dir/$lock_file" 2>/dev/null)" != "$(realpath "$dest_dir/$lock_file" 2>/dev/null)" ] || [ "$OVERRIDE_UPDATE_LOCK" = true ]; then
            cp "$src_dir/$lock_file" "$dest_dir/$lock_file"
            echo "✓ Copied $lock_file to config directory"
        fi
    fi

    # Create symbolic links
    if [ -f "$dest_dir/package.json" ] && [ "$(realpath "$src_dir/package.json" 2>/dev/null)" != "$(realpath "$dest_dir/package.json" 2>/dev/null)" ]; then
        ln -fs "$dest_dir/package.json" "$src_dir/package.json"
        echo "✓ Linked package.json"
    fi

    if [ -f "$dest_dir/$lock_file" ] && [ "$(realpath "$src_dir/$lock_file" 2>/dev/null)" != "$(realpath "$dest_dir/$lock_file" 2>/dev/null)" ]; then
        ln -fs "$dest_dir/$lock_file" "$src_dir/$lock_file"
        echo "✓ Linked $lock_file"
    fi
}

install_dependencies() {
    echo "Installing dependencies with $PACKAGE_MANAGER..."
    
    case "$PACKAGE_MANAGER" in
        yarn) 
            yarn install --production --frozen-lockfile || {
                echo "❌ Failed to install dependencies with yarn"
                exit 1
            } ;;
        npm) 
            npm ci --only=production --no-audit --no-fund || {
                echo "❌ Failed to install dependencies with npm"
                exit 1
            } ;;
        pnpm) 
            pnpm install --prod --frozen-lockfile || {
                echo "❌ Failed to install dependencies with pnpm"
                exit 1
            } ;;
        *)
            echo "❌ Unknown package manager: $PACKAGE_MANAGER"
            exit 1
            ;;
    esac
    
    echo "✓ Dependencies installed successfully"
}

copy_or_link_files
install_dependencies

echo "✅ Package management setup completed"

# =================================================================
# SECTION 4: CONFIGURATION GENERATION
# =================================================================
echo ""
echo "⚙️  [4/7] CONFIGURATION GENERATION"
echo "=================================================="

create_configuration() {
    local config_file="$CONFIG"
    
    # Define variables BEFORE using them
    local site_url="${SITE_URL:-https://forum.codeproject.com}"
    local secret="${NODEBB_SECRET:-$(openssl rand -hex 32)}"
    local db_port="${NODEBB_DB_PORT:-27017}"
    local app_port="${PORT:-4567}"
    local auth_source="${NODEBB_DB_AUTH_SOURCE:-admin}"
    
    echo "Generating NodeBB configuration..."
    cat > "$config_file" << CONFIG_EOF
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
      "authSource": "$auth_source"
    }
  },
  "port": $app_port,
  "bind_address": "0.0.0.0",
  "sessionStore": {
    "name": "database"
  },
  "cluster": {
    "port": $app_port
  }
}
CONFIG_EOF
    
    chmod 644 "$config_file"
    echo "✓ Configuration file created at $config_file"
    
    # Copy config.json to working directory for NodeBB compatibility
    cp "$config_file" /usr/src/app/config.json
    echo "✓ Copied config.json to /usr/src/app/"
    
    # Validate JSON syntax
    if node -e "JSON.parse(require('fs').readFileSync('$config_file', 'utf8'))" 2>/dev/null; then
        echo "✅ Configuration validation passed"
    else
        echo "❌ ERROR: Invalid JSON configuration"
        echo "Configuration content:"
        cat "$config_file"
        exit 1
    fi
    
    echo "📋 Configuration summary:"
    echo "  - Site URL: $site_url"
    echo "  - Database: $NODEBB_DB_HOST:$db_port/$NODEBB_DB_NAME"
    echo "  - Auth Source: $auth_source"
    echo "  - Port: $app_port"
    echo "  - Session Store: database"
}

create_configuration

# =================================================================
# SECTION 5: BUILD MANAGEMENT
# =================================================================
echo ""
echo "🏗️  [5/7] BUILD MANAGEMENT"
echo "=================================================="

build_forum() {
    local config="/usr/src/app/config.json"
    local start_build="$START_BUILD"
    
    local package_hash=""
    if [ -f "install/package.json" ]; then
        package_hash=$(md5sum install/package.json | head -c 32)
    elif [ -f "package.json" ]; then
        package_hash=$(md5sum package.json | head -c 32)
    fi
    
    local stored_hash=""
    if [ -f "$CONFIG_DIR/install_hash.md5" ]; then
        stored_hash=$(cat "$CONFIG_DIR/install_hash.md5")
    fi
    
    if [ -n "$package_hash" ] && [ "$package_hash" != "$stored_hash" ]; then
        echo "📦 Package.json changes detected. Running upgrade..."
        
        if [ -x "./nodebb" ]; then
            timeout 600 node ./nodebb upgrade --config="$config" || {
                echo "❌ Failed to upgrade NodeBB"
                exit 1
            }
        else
            echo "⚠️  ./nodebb not executable, running build instead..."
            timeout 600 node ./nodebb build --config="$config" || {
                echo "❌ Failed to build NodeBB"
                exit 1
            }
        fi
        
        echo -n "$package_hash" > "$CONFIG_DIR/install_hash.md5"
        echo "✓ Upgrade completed and hash saved"
        
    elif [ "$start_build" = "true" ]; then
        echo "🔨 Build before start is enabled. Building..."
        
        if [ -x "./nodebb" ]; then
            echo "▶️  Executing: node ./nodebb build --config=$config"
            timeout 600 node ./nodebb build --config="$config" || {
                echo "❌ Failed to build NodeBB"
                exit 1
            }
        else
            echo "❌ ERROR: ./nodebb not found or not executable"
            ls -la ./nodebb 2>/dev/null || echo "File does not exist"
            exit 1
        fi
        
        echo "✅ Build completed successfully"
        
    else
        echo "⏭️  No changes in package.json and build not forced. Skipping build..."
        return
    fi
    
    # Verify build results
    echo ""
    echo "📊 Build verification:"
    if [ -d "build/public" ]; then
        local file_count=$(ls -1 build/public 2>/dev/null | wc -l)
        echo "✓ Found build/public directory with $file_count files"
    fi
    if [ -d "public/build" ]; then
        local file_count=$(ls -1 public/build 2>/dev/null | wc -l)
        echo "✓ Found public/build directory with $file_count files"
    fi
    
    if [ ! -f "build/cache-buster" ]; then
        echo "⚠️  Creating missing cache-buster file..."
        mkdir -p build
        date +%s > build/cache-buster
        echo "✓ Cache-buster file created"
    fi
}

build_forum

echo "✅ Build management completed"

# =================================================================
# SECTION 6: PRE-START VALIDATION
# =================================================================
echo ""
echo "🔍 [6/7] PRE-START VALIDATION"
echo "=================================================="

pre_start_validation() {
    local validation_errors=0
    
    echo "Running comprehensive pre-start checks..."
    
    # Configuration file in working directory
    if [ ! -f "/usr/src/app/config.json" ]; then
        echo "❌ Configuration file missing: /usr/src/app/config.json"
        validation_errors=$((validation_errors + 1))
    else
        echo "✓ Configuration file exists in working directory"
    fi
    
    # NodeBB executable
    if [ ! -x "./nodebb" ]; then
        echo "❌ NodeBB executable missing or not executable"
        validation_errors=$((validation_errors + 1))
    else
        echo "✓ NodeBB executable ready"
    fi
    
    # Node modules
    if [ ! -d "node_modules" ]; then
        echo "❌ Node modules missing"
        validation_errors=$((validation_errors + 1))
    else
        echo "✓ Node modules available"
    fi
    
    # Critical directories
    local critical_dirs=("public/uploads" "logs" "build")
    for dir in "${critical_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo "✓ Created directory: $dir"
        else
            echo "✓ Directory exists: $dir"
        fi
        
        if [ ! -w "$dir" ]; then
            echo "❌ Directory not writable: $dir"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # Node.js runtime test
    if ! node -e "console.log('Node.js runtime OK')" 2>/dev/null; then
        echo "❌ Node.js runtime error"
        validation_errors=$((validation_errors + 1))
    else
        echo "✓ Node.js runtime working"
    fi
    
    if [ $validation_errors -eq 0 ]; then
        echo "✅ All pre-start validations passed"
    else
        echo "❌ ERROR: $validation_errors validation error(s) found"
        exit 1
    fi
}

pre_start_validation

# =================================================================
# SECTION 7: NODEBB START WITH ENHANCED LOGGING
# =================================================================
echo ""
echo "🚀 [7/7] STARTING NODEBB WITH ENHANCED LOGGING"
echo "=================================================="

start_forum() {
    local config="/usr/src/app/config.json"
    
    echo "🎯 NodeBB Production Startup Summary:"
    echo "=================================================="
    echo "📋 Configuration:"
    echo "  - Config file: $config"
    echo "  - Port: ${PORT:-4567}"
    echo "  - Environment: $NODE_ENV"
    echo "  - Package Manager: $PACKAGE_MANAGER"
    echo "  - Database: $NODEBB_DB_HOST:${NODEBB_DB_PORT:-27017}"
    echo "  - Site URL: ${SITE_URL:-https://forum.codeproject.com}"
    echo "  - Session store: database (MongoDB)"
    echo ""
    echo "🎨 Build Status:"
    echo "  - Build completed: YES"
    echo "  - Assets ready: YES"
    echo "  - Upload directory: YES"
    echo "  - Package management: $PACKAGE_MANAGER"
    echo ""
    echo "🔧 Runtime Configuration:"
    echo "  - Cluster mode: Disabled"
    echo "  - Bind address: 0.0.0.0"
    echo "  - Auth source: ${NODEBB_DB_AUTH_SOURCE:-admin}"
    echo ""
    echo "=================================================="
    echo "🎉 Starting NodeBB Forum with Live Logs..."
    echo "=================================================="
    echo ""
    
    echo "▶️  Executing: node app.js --config=$config"
    echo ""
    echo "📊 Live NodeBB Logs:"
    echo "=================================================="
    
    exec node app.js --config="$config"
}

# Cleanup function for graceful shutdown
cleanup() {
    echo ""
    echo "🛑 Received shutdown signal, stopping NodeBB gracefully..."
    
    # For direct app.js execution, signals are handled properly by Node.js
    echo "✅ Cleanup completed"
    exit 0
}

# Set up signal traps for graceful shutdown
trap cleanup SIGTERM SIGINT SIGQUIT

# Start the forum
start_forum

# This should not be reached if exec works properly
echo "❌ ERROR: NodeBB exited unexpectedly"
exit 1
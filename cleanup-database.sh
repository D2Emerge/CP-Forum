#!/bin/bash
set -euo pipefail

echo "=================================================="
echo "🧹 NodeBB Database Cleanup Script"
echo "=================================================="
echo "⚠️  WARNING: This will completely wipe NodeBB database!"
echo "⚠️  This action cannot be undone!"
echo "=================================================="

# Configuration from environment
DB_HOST="${NODEBB_DB_HOST:-}"
DB_PORT="${NODEBB_DB_PORT:-27017}"
DB_USER="${NODEBB_DB_USER:-}"
DB_PASSWORD="${NODEBB_DB_PASSWORD:-}"
DB_NAME="${NODEBB_DB_NAME:-}"
DB_SSL="${NODEBB_DB_SSL:-true}"

# Validate environment
if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_NAME" ]; then
    echo "❌ ERROR: Required database environment variables not set"
    echo "Required: NODEBB_DB_HOST, NODEBB_DB_USER, NODEBB_DB_PASSWORD, NODEBB_DB_NAME"
    exit 1
fi

echo "Database configuration:"
echo "  Host: $DB_HOST:$DB_PORT"
echo "  Database: $DB_NAME"
echo "  User: $DB_USER"
echo "  SSL: $DB_SSL"
echo ""

# Confirm action
read -p "Are you sure you want to DROP the entire '$DB_NAME' database? (type 'yes' to confirm): " -r
if [ "$REPLY" != "yes" ]; then
    echo "❌ Operation cancelled"
    exit 1
fi

echo ""
echo "🗄️  Connecting to DocumentDB..."

# Construct connection string
if [ "$DB_SSL" = "true" ]; then
    SSL_PARAMS="--ssl --sslCAFile /opt/rds-ca-2019-root.pem --sslAllowInvalidHostnames"
else
    SSL_PARAMS=""
fi

# Test connection first
echo "Testing database connection..."
if ! mongosh "mongodb://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?authSource=admin" $SSL_PARAMS --eval "db.runCommand('ping')" --quiet; then
    echo "❌ ERROR: Cannot connect to database"
    exit 1
fi

echo "✅ Database connection successful"
echo ""

# Drop database
echo "🗑️  Dropping database '$DB_NAME'..."
mongosh "mongodb://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?authSource=admin" $SSL_PARAMS --eval "
    print('Dropping database: $DB_NAME');
    db.dropDatabase();
    print('Database dropped successfully');
" --quiet

echo "✅ Database '$DB_NAME' has been completely removed"
echo ""
echo "📋 Next steps:"
echo "  1. Deploy NodeBB with clean setup entrypoint"
echo "  2. NodeBB will run initial setup automatically"
echo "  3. Fresh forum will be created with default settings"
echo ""
echo "🎯 The next NodeBB deployment will:"
echo "  - Create fresh database structure"
echo "  - Set up admin user from environment variables"
echo "  - Install default plugins only"
echo "  - Use built-in jQuery (no custom modifications)"
echo "=================================================="
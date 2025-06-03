# NodeBB Scripts

This directory contains various utility scripts for NodeBB, including the JSON import tool.

## JSON Import Script

The `import-json.js` script is a powerful tool for importing JSON data into NodeBB's database with support for environment variable substitution and automatic value generation.

### Features

- Environment variable substitution
- Automatic timestamp generation
- Multiple object import from single file
- Sensitive data masking in dry-run mode
- Support for different import modes (upsert, insert, replace)

### Basic Usage

```bash
node scripts/import-json.js --file=<path> --collection=<name> [options]
```

### Example Command

```bash
node scripts/import-json.js --file=scripts/config/sso/template.json --collection=objects --env=local
```

### Required Parameters

- `--file`: Path to the JSON file to import
- `--collection`: MongoDB collection name

### Optional Parameters

- `--env`: Environment suffix (local, stag, prod) - loads `.env.{env}` file
- `--mode`: Import mode (default: upsert)
  - `upsert`: Update existing documents or insert new ones
  - `insert`: Only insert new documents
  - `replace`: Replace existing documents
- `--key`: Field name for unique identifier (default: _key)
- `--dry-run`: Preview import without actually modifying data

### Environment Variable Substitution

The script supports two formats for environment variables:

1. `${VAR_NAME}` format:
```json
{
  "clientId": "${SSO_CLIENT_ID}",
  "secret": "${SSO_CLIENT_SECRET}"
}
```

2. `$VAR_NAME` format:
```json
{
  "clientId": "$SSO_CLIENT_ID",
  "secret": "$SSO_CLIENT_SECRET"
}
```

### Auto-Generation

The script can automatically generate timestamps using the `${TIMESTAMP}` placeholder:

```json
{
  "score": ${TIMESTAMP},
  "lastUpdated": ${TIMESTAMP}
}
```

### Environment Files

The script looks for environment files in the following locations (in order):
1. `.env.{env}`
2. `.env`
3. `scripts/.env.{env}`
4. `scripts/.env`
5. `scripts/env-{env}.txt`
6. `scripts/env.txt`

### Dry Run Mode

Use the `--dry-run` flag to preview the import without making any changes to the database. This is useful for testing and validation:

```bash
node scripts/import-json.js --file=config.json --collection=objects --env=prod --dry-run
```

### Special Handling

The script includes special handling for certain record types:
- Index records (e.g., `oauth2-multiple:strategies`) are handled differently to maintain proper indexing
- Sensitive data (passwords, secrets, tokens) is automatically masked in dry-run mode

### Error Handling

- The script validates JSON syntax before import
- Missing environment variables are logged with warnings
- Database connection errors are handled gracefully
- Failed imports are reported with detailed error messages

## Available Scripts

### JSON Import Script (`import-json.js`)

The `import-json.js` script allows you to import JSON data directly into your NodeBB MongoDB database.

### List Collections Script (`list-collections.js`)

The `list-collections.js` script shows all collections in your NodeBB database along with document counts.

```bash
node scripts/list-collections.js
```

This is useful for:
- Understanding your database structure
- Finding collection names for imports
- Getting a quick overview of your data

```bash
node scripts/list-collections.js
```

### Quick Start Guide

1. **Check existing collections**:
   ```bash
   node scripts/list-collections.js
   ```
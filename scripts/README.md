# NodeBB Database Scripts

This directory contains utility scripts for managing your NodeBB MongoDB database.

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

## JSON Import Script

The `import-json.js` script allows you to import JSON data directly into your NodeBB MongoDB database.

### Prerequisites

- NodeBB must be properly configured with MongoDB
- Your `config.json` file must have valid MongoDB connection settings
- Node.js and npm dependencies must be installed

### Usage

```bash
node scripts/import-json.js --file=<path> --collection=<name> [options]
```

### Required Parameters

- `--file`: Path to the JSON file to import
- `--collection`: MongoDB collection name where data will be imported

### Optional Parameters

- `--mode`: Import mode (default: `insert`)
  - `insert`: Insert new documents (fails if duplicate keys exist)
  - `upsert`: Insert new documents or update existing ones based on a unique key
  - `replace`: Replace all existing documents in the collection with the new data
- `--key`: Field name to use as unique identifier for upsert mode (default: `_id`)
- `--dry-run`: Preview the import without actually modifying the database

### Examples

#### Basic Insert
```bash
# Import users from a JSON file
node scripts/import-json.js --file=users.json --collection=users
```

#### Upsert Mode with Custom Key
```bash
# Upsert users using email as the unique identifier
node scripts/import-json.js --file=users.json --collection=users --mode=upsert --key=email
```

#### Replace Collection Data
```bash
# Replace all data in the collection
node scripts/import-json.js --file=new-data.json --collection=mycollection --mode=replace
```

#### Dry Run (Preview)
```bash
# Preview what would be imported without actually importing
node scripts/import-json.js --file=data.json --collection=test --dry-run
```

### JSON File Format

Your JSON file should contain either:

1. **An array of objects** (recommended):
```json
[
    {
        "_id": "user1",
        "name": "John Doe",
        "email": "john@example.com"
    },
    {
        "_id": "user2", 
        "name": "Jane Smith",
        "email": "jane@example.com"
    }
]
```

2. **A single object**:
```json
{
    "_id": "user1",
    "name": "John Doe",
    "email": "john@example.com"
}
```

### Import Modes Explained

#### Insert Mode (Default)
- Adds new documents to the collection
- Fails if documents with duplicate `_id` already exist
- Use when you're sure the data is completely new

#### Upsert Mode
- Updates existing documents or inserts new ones
- Uses the specified key field to determine if a document exists
- Safer for updating existing data
- Example: `--mode=upsert --key=email`

#### Replace Mode
- **WARNING**: Deletes ALL existing documents in the collection first
- Then inserts the new data
- Use with extreme caution as this is destructive
- Good for completely refreshing a collection

### Error Handling

The script includes comprehensive error handling:

- Validates command line arguments
- Checks if files exist
- Validates JSON format
- Provides detailed error messages
- Safely closes database connections

### Sample Data

A sample JSON file is provided at `scripts/sample-data.json` to demonstrate the expected format.

### Security Considerations

- Always backup your database before running import scripts
- Test with `--dry-run` first
- Be especially careful with `--mode=replace` as it's destructive
- Ensure your JSON data doesn't contain sensitive information if sharing

## Quick Start Guide

1. **Check existing collections**:
   ```bash
   node scripts/list-collections.js
   ```

2. **Test with sample data**:
   ```bash
   node scripts/import-json.js --file=scripts/sample-data.json --collection=test_data --dry-run
   ```

3. **Import your data**:
   ```bash
   node scripts/import-json.js --file=your-data.json --collection=your_collection
   ```

### Troubleshooting

#### Connection Issues
```
Error: Database connection failed
```
- Check your `config.json` MongoDB settings
- Ensure MongoDB is running
- Verify network connectivity

#### Permission Issues
```
Error: Authentication failed
```
- Check MongoDB username/password in config
- Verify database permissions

#### JSON Format Issues
```
Error: Invalid JSON in file
```
- Validate your JSON using a JSON validator
- Check for syntax errors (missing commas, brackets, quotes)

#### Collection Issues
```
Error: Collection not found
```
- MongoDB will create the collection automatically
- This error usually indicates a database connection problem

### Getting Help

Run the script with `--help` to see usage information:
```bash
node scripts/import-json.js --help
``` 
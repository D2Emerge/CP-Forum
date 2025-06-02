#!/usr/bin/env node

"use strict";

/**
 * JSON Import Script for NodeBB MongoDB Database
 *
 * This script allows you to import JSON data into your NodeBB MongoDB database.
 *
 * Usage:
 * node scripts/import-json.js --file=data.json --collection=mycollection
 *
 * Options:
 * --file: Path to the JSON file to import (required)
 * --collection: MongoDB collection name to import to (required)
 * --mode: Import mode - 'insert' (default), 'upsert', or 'replace'
 * --key: Field name to use as unique identifier for upsert mode (default: '_id')
 * --dry-run: Preview what would be imported without actually importing
 */

const path = require("path");
const fs = require("fs");
const winston = require("winston");
const nconf = require("nconf");

// Setup NodeBB configuration - handle both direct execution and require
const rootDir = path.resolve(__dirname, "..");
process.chdir(rootDir);

nconf.argv().env({
	separator: "__",
});

const prestart = require("../src/prestart");

// Alternate configuration file support
const configFile = path.resolve(
	__dirname,
	"..",
	nconf.any(["config", "CONFIG"]) || "config.json"
);
prestart.loadConfig(configFile);
prestart.setupWinston();

const db = require("../src/database");

async function validateArgs() {
	const args = nconf.get();

	if (!args.file) {
		throw new Error(
			"--file parameter is required. Specify the path to your JSON file."
		);
	}

	if (!args.collection) {
		throw new Error(
			"--collection parameter is required. Specify the MongoDB collection name."
		);
	}

	// Resolve file path relative to current working directory
	const filePath = path.resolve(args.file);
	if (!fs.existsSync(filePath)) {
		throw new Error(`File not found: ${filePath}`);
	}

	const validModes = ["insert", "upsert", "replace"];
	const mode = args.mode || "insert";
	if (!validModes.includes(mode)) {
		throw new Error(
			`Invalid mode: ${mode}. Valid modes are: ${validModes.join(", ")}`
		);
	}

	return {
		file: filePath,
		collection: args.collection,
		mode,
		key: args.key || "_id",
		dryRun: !!args["dry-run"],
	};
}

async function loadJsonData(filePath) {
	winston.info(`Loading JSON data from: ${filePath}`);

	const data = fs.readFileSync(filePath, "utf8");
	let jsonData;

	try {
		jsonData = JSON.parse(data);
	} catch (err) {
		throw new Error(`Invalid JSON in file ${filePath}: ${err.message}`);
	}

	// Ensure data is an array
	if (!Array.isArray(jsonData)) {
		jsonData = [jsonData];
	}

	winston.info(`Loaded ${jsonData.length} record(s) from JSON file`);
	return jsonData;
}

async function importData(collection, data, options) {
	const { mode, key, dryRun } = options;

	winston.info(`Import mode: ${mode}`);
	winston.info(`Target collection: ${collection}`);

	if (dryRun) {
		winston.info("DRY RUN MODE - No data will be actually imported");
		winston.info("Preview of data to be imported:");
		console.log(JSON.stringify(data.slice(0, 3), null, 2));
		if (data.length > 3) {
			winston.info(`... and ${data.length - 3} more record(s)`);
		}
		return;
	}

	const mongoCollection = db.client.collection(collection);
	let result;

	try {
		switch (mode) {
			case "insert":
				winston.info("Inserting data...");
				if (data.length === 1) {
					result = await mongoCollection.insertOne(data[0]);
					winston.info(`Successfully inserted 1 document`);
				} else {
					result = await mongoCollection.insertMany(data);
					winston.info(
						`Successfully inserted ${result.insertedCount} document(s)`
					);
				}
				break;

			case "upsert":
				winston.info(`Upserting data using key: ${key}`);
				let upsertCount = 0;

				for (const doc of data) {
					if (!doc[key]) {
						winston.warn(`Document missing key '${key}', skipping:`, doc);
						continue;
					}

					await mongoCollection.replaceOne({ [key]: doc[key] }, doc, {
						upsert: true,
					});
					upsertCount++;
				}

				winston.info(`Successfully upserted ${upsertCount} document(s)`);
				break;

			case "replace":
				winston.info("Replacing collection data...");

				// First, clear existing data
				const deleteResult = await mongoCollection.deleteMany({});
				winston.info(
					`Deleted ${deleteResult.deletedCount} existing document(s)`
				);

				// Then insert new data
				if (data.length === 1) {
					result = await mongoCollection.insertOne(data[0]);
					winston.info(`Successfully inserted 1 document`);
				} else {
					result = await mongoCollection.insertMany(data);
					winston.info(
						`Successfully inserted ${result.insertedCount} document(s)`
					);
				}
				break;
		}

		winston.info("Import completed successfully!");
	} catch (err) {
		winston.error("Error during import:", err.message);
		throw err;
	}
}

async function main() {
	try {
		winston.info("Starting JSON import process...");

		// Validate command line arguments
		const options = await validateArgs();

		// Initialize database connection
		winston.info("Connecting to database...");
		await db.init();
		winston.info("Database connected successfully");

		// Load JSON data
		const data = await loadJsonData(options.file);

		// Import data
		await importData(options.collection, data, options);

		winston.info("JSON import process completed!");
	} catch (err) {
		winston.error(`Import failed: ${err.message}`);
		process.exit(1);
	} finally {
		// Close database connection
		if (db.client) {
			await db.close();
		}
		process.exit(0);
	}
}

// Show usage information
function showUsage() {
	console.log("\nNodeBB JSON Import Script");
	console.log("=========================");
	console.log("\nUsage:");
	console.log(
		"  node scripts/import-json.js --file=<path> --collection=<name> [options]"
	);
	console.log("\nRequired Parameters:");
	console.log("  --file         Path to the JSON file to import");
	console.log("  --collection   MongoDB collection name");
	console.log("\nOptional Parameters:");
	console.log(
		"  --mode         Import mode: insert (default), upsert, or replace"
	);
	console.log(
		"  --key          Field name for unique identifier in upsert mode (default: _id)"
	);
	console.log(
		"  --dry-run      Preview import without actually modifying data"
	);
	console.log("\nExamples:");
	console.log(
		"  node scripts/import-json.js --file=users.json --collection=users"
	);
	console.log(
		"  node scripts/import-json.js --file=data.json --collection=mycollection --mode=upsert --key=email"
	);
	console.log(
		"  node scripts/import-json.js --file=data.json --collection=test --dry-run"
	);
	console.log("");
}

// Check if help is requested or no arguments provided
if (
	process.argv.includes("--help") ||
	process.argv.includes("-h") ||
	process.argv.length <= 2
) {
	showUsage();
	process.exit(0);
}

// Run the main function
main();

#!/usr/bin/env node

"use strict";

/**
 * Enhanced JSON Import Script with Auto-Generation Features
 *
 * This script imports JSON data with environment variable substitution
 * and automatic generation of timestamps for score fields.
 *
 * Usage:
 * node scripts/import-json-enhanced.js --file=data.json --collection=mycollection --env=local
 *
 * Features:
 * - Environment variable substitution
 * - Automatic timestamp generation for ${TIMESTAMP}
 * - Multiple object import from single file
 * - Sensitive data masking in dry-run
 */

const path = require("path");
const fs = require("fs");
const winston = require("winston");
const nconf = require("nconf");

// Setup NodeBB configuration
const rootDir = path.resolve(__dirname, "..");
process.chdir(rootDir);

nconf.argv().env({
	separator: "__",
});

const prestart = require("../src/prestart");

// Load configuration
const configFile = path.resolve(
	__dirname,
	"..",
	nconf.any(["config", "CONFIG"]) || "config.json"
);
prestart.loadConfig(configFile);
prestart.setupWinston();

const db = require("../src/database");

function loadEnvFile(envSuffix) {
	const envFiles = [
		`.env.${envSuffix}`,
		".env",
		`scripts/.env.${envSuffix}`,
		"scripts/.env",
		`scripts/env-${envSuffix}.txt`,
		"scripts/env.txt",
	].filter(Boolean);
	const envVars = {};

	for (const envFile of envFiles) {
		const envPath = path.resolve(envFile);
		if (fs.existsSync(envPath)) {
			winston.info(`Loading environment variables from: ${envFile}`);
			const envContent = fs.readFileSync(envPath, "utf8");

			// Parse .env file
			const lines = envContent.split("\n");
			for (const line of lines) {
				const trimmedLine = line.trim();
				if (trimmedLine && !trimmedLine.startsWith("#")) {
					const [key, ...valueParts] = trimmedLine.split("=");
					if (key && valueParts.length > 0) {
						let value = valueParts.join("=").trim();

						// Remove quotes if present
						if (
							(value.startsWith('"') && value.endsWith('"')) ||
							(value.startsWith("'") && value.endsWith("'"))
						) {
							value = value.slice(1, -1);
						}

						envVars[key.trim()] = value;
					}
				}
			}
			break; // Use the first found file
		} else {
			winston.debug(`Environment file not found: ${envFile}`);
		}
	}

	if (Object.keys(envVars).length === 0 && envSuffix) {
		winston.warn(`No environment file found for suffix: ${envSuffix}`);
	}

	return envVars;
}

function generateTimestamp() {
	return Date.now().toString();
}

function processAutoGeneration(jsonString) {
	// Replace ${TIMESTAMP} with current timestamp
	return jsonString.replace(/\$\{TIMESTAMP\}/g, () => {
		const timestamp = generateTimestamp();
		winston.info(`Generated timestamp: ${timestamp}`);
		return Number(timestamp);
	});
}

function substituteEnvironmentVariables(jsonString, envVars) {
	let result = jsonString;

	// First handle auto-generation
	result = processAutoGeneration(result);

	// Handle ${VAR_NAME} pattern
	result = result.replace(/\$\{([^}]+)\}/g, (match, varName) => {
		if (varName === "TIMESTAMP") {
			// Already handled above
			return match;
		}

		if (envVars.hasOwnProperty(varName)) {
			winston.info(`Substituting ${match} with environment variable`);
			return envVars[varName];
		} else {
			winston.warn(
				`Environment variable ${varName} not found, keeping placeholder`
			);
			return match;
		}
	});

	// Handle $VAR_NAME pattern (word boundaries)
	result = result.replace(/\$([A-Z_][A-Z0-9_]*)\b/g, (match, varName) => {
		if (varName === "TIMESTAMP") {
			return generateTimestamp();
		}

		if (envVars.hasOwnProperty(varName)) {
			winston.info(`Substituting ${match} with environment variable`);
			return envVars[varName];
		} else {
			winston.warn(
				`Environment variable ${varName} not found, keeping placeholder`
			);
			return match;
		}
	});

	return result;
}

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

	const filePath = path.resolve(args.file);
	if (!fs.existsSync(filePath)) {
		throw new Error(`File not found: ${filePath}`);
	}

	const validModes = ["insert", "upsert", "replace"];
	const mode = args.mode || "upsert"; // Default to upsert for enhanced script
	if (!validModes.includes(mode)) {
		throw new Error(
			`Invalid mode: ${mode}. Valid modes are: ${validModes.join(", ")}`
		);
	}

	return {
		file: filePath,
		collection: args.collection,
		mode,
		key: args.key || "_key", // Default to _key for NodeBB objects
		dryRun: !!args["dry-run"],
		env: args.env || null,
	};
}

async function loadJsonDataWithEnv(filePath, envSuffix) {
	winston.info(`Loading JSON data from: ${filePath}`);

	// Load environment variables if env suffix is provided
	let envVars = {};
	if (envSuffix) {
		envVars = loadEnvFile(envSuffix);
		winston.info(
			`Loaded ${Object.keys(envVars).length} environment variable(s)`
		);
	}

	// Read JSON file
	let data = fs.readFileSync(filePath, "utf8");

	// Substitute environment variables and auto-generate values
	if (envSuffix || data.includes("${TIMESTAMP}")) {
		winston.info(
			"Performing environment variable substitution and auto-generation..."
		);
		data = substituteEnvironmentVariables(data, envVars);
	}

	let jsonData;
	try {
		jsonData = JSON.parse(data);
	} catch (err) {
		throw new Error(
			`Invalid JSON in file ${filePath} after processing: ${err.message}`
		);
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
	winston.info(`Processing ${data.length} object(s)`);

	if (dryRun) {
		winston.info("DRY RUN MODE - No data will be actually imported");
		winston.info("Preview of data to be imported:");

		// Mask sensitive fields for security
		const maskedData = data.map((doc) => {
			const masked = { ...doc };
			if (masked.secret) masked.secret = "***MASKED***";
			if (masked.password) masked.password = "***MASKED***";
			if (masked.token) masked.token = "***MASKED***";
			return masked;
		});

		console.log(JSON.stringify(maskedData, null, 2));
		return;
	}

	const mongoCollection = db.client.collection(collection);

	try {
		let totalProcessed = 0;

		for (const doc of data) {
			if (!doc[key]) {
				winston.warn(`Document missing key '${key}', skipping:`, {
					_key: doc._key || "unknown",
				});
				continue;
			}

			winston.info(`Processing document with ${key}: ${doc[key]}`);

			// Special handling for index records (oauth2-multiple:strategies)
			if (doc._key === "oauth2-multiple:strategies" && doc.value) {
				// For index records, we want to insert a new document instead of updating existing ones
				// First check if this specific combination already exists
				const existingDoc = await mongoCollection.findOne({
					_key: doc._key,
					value: doc.value,
				});

				if (existingDoc) {
					winston.info(
						`Updating existing index record with value: ${doc.value}`
					);
					await mongoCollection.replaceOne(
						{ _key: doc._key, value: doc.value },
						doc
					);
				} else {
					winston.info(`Creating new index record with value: ${doc.value}`);
					await mongoCollection.insertOne(doc);
				}
			} else {
				// For strategy configuration records, use normal upsert
				await mongoCollection.replaceOne({ [key]: doc[key] }, doc, {
					upsert: true,
				});
			}
			totalProcessed++;
		}

		winston.info(`Successfully processed ${totalProcessed} document(s)`);
		winston.info("Import completed successfully!");
	} catch (err) {
		winston.error("Error during import:", err.message);
		throw err;
	}
}

async function main() {
	try {
		winston.info("Starting enhanced JSON import with auto-generation...");

		// Validate command line arguments
		const options = await validateArgs();

		// Initialize database connection
		winston.info("Connecting to database...");
		await db.init();
		winston.info("Database connected successfully");

		// Load JSON data with environment variable substitution
		const data = await loadJsonDataWithEnv(options.file, options.env);

		// Import data
		await importData(options.collection, data, options);

		winston.info("Enhanced JSON import process completed!");
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
	console.log("\nNodeBB Enhanced JSON Import Script");
	console.log("==================================");
	console.log("\nFeatures:");
	console.log("  • Environment variable substitution");
	console.log("  • Automatic timestamp generation for ${TIMESTAMP}");
	console.log("  • Multiple object import from single file");
	console.log("  • Smart defaults for NodeBB (upsert mode, _key field)");
	console.log("\nUsage:");
	console.log(
		"  node scripts/import-json-enhanced.js --file=<path> --collection=<name> [options]"
	);
	console.log("\nRequired Parameters:");
	console.log("  --file         Path to the JSON file to import");
	console.log("  --collection   MongoDB collection name");
	console.log("\nOptional Parameters:");
	console.log(
		"  --env          Environment suffix (local, stag, prod) - loads .env.{env} file"
	);
	console.log(
		"  --mode         Import mode: upsert (default), insert, or replace"
	);
	console.log(
		"  --key          Field name for unique identifier (default: _key)"
	);
	console.log(
		"  --dry-run      Preview import without actually modifying data"
	);
	console.log("\nAuto-Generation:");
	console.log(
		"  ${TIMESTAMP}   Generates current Unix timestamp in milliseconds"
	);
	console.log("\nEnvironment Variable Substitution:");
	console.log("  ${VAR_NAME}    Replaced with environment variable value");
	console.log("  $VAR_NAME      Alternative format for environment variables");
	console.log("\nExamples:");
	console.log(
		"  node scripts/import-json-enhanced.js --file=sso.template.json --collection=objects --env=local"
	);
	console.log(
		"  node scripts/import-json-enhanced.js --file=config.json --collection=objects --env=prod --dry-run"
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

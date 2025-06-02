#!/usr/bin/env node

"use strict";

/**
 * List Collections Script for NodeBB MongoDB Database
 *
 * This script lists all collections in your NodeBB MongoDB database.
 * Useful for understanding your database structure before importing data.
 */

const path = require("path");
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

async function listCollections() {
	try {
		winston.info("Connecting to database...");
		await db.init();
		winston.info("Database connected successfully");

		winston.info("Fetching collections...");
		const collections = await db.client.listCollections().toArray();

		console.log("\n==========================================");
		console.log("Collections in NodeBB MongoDB Database");
		console.log("==========================================\n");

		if (collections.length === 0) {
			console.log("No collections found in the database.\n");
		} else {
			console.log(`Found ${collections.length} collection(s):\n`);

			for (const collection of collections) {
				// Get basic stats for each collection
				try {
					const stats = await db.client
						.collection(collection.name)
						.countDocuments();
					console.log(`• ${collection.name} (${stats} documents)`);
				} catch (err) {
					console.log(`• ${collection.name} (unable to count documents)`);
				}
			}
			console.log("");
		}

		console.log("You can import data to any of these collections using:");
		console.log(
			"node scripts/import-json.js --file=your-data.json --collection=COLLECTION_NAME\n"
		);
	} catch (err) {
		winston.error(`Failed to list collections: ${err.message}`);
		process.exit(1);
	} finally {
		if (db.client) {
			await db.close();
		}
		process.exit(0);
	}
}

listCollections();

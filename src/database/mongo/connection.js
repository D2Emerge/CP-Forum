"use strict";

const nconf = require("nconf");
const winston = require("winston");
const _ = require("lodash");

const connection = module.exports;

connection.getConnectionString = function (mongo) {
	mongo = mongo || nconf.get("mongo");
	let usernamePassword = "";
	const uri = mongo.uri || "";
	if (mongo.username && mongo.password) {
		usernamePassword = `${mongo.username}:${encodeURIComponent(
			mongo.password
		)}@`;
	} else if (
		!uri.includes("@") ||
		!uri.slice(uri.indexOf("://") + 3, uri.indexOf("@"))
	) {
		winston.warn("You have no mongo username/password setup!");
	}

	if (!mongo.host) {
		mongo.host = "127.0.0.1";
	}
	if (!mongo.port) {
		mongo.port = 27017;
	}
	const dbName = mongo.database;
	if (dbName === undefined || dbName === "") {
		winston.warn('You have no database name, using "nodebb"');
		mongo.database = "nodebb";
	}

	const hosts = mongo.host.split(",");
	const ports = mongo.port.toString().split(",");
	const servers = [];

	for (let i = 0; i < hosts.length; i += 1) {
		servers.push(`${hosts[i]}:${ports[i]}`);
	}

	const params = [];
	if (mongo.ssl === "true" || mongo.ssl === true) {
		params.push("ssl=true");
		params.push("tlsAllowInvalidHostnames=true");
		params.push("tlsAllowInvalidCertificates=true");
	}
	params.push("retryWrites=false");
	params.push("readPreference=secondaryPreferred");
	params.push("authMechanism=SCRAM-SHA-1");
	params.push("authSource=admin");

	const queryString = params.length > 0 ? `?${params.join("&")}` : "";

	const composedUri = `mongodb://${usernamePassword}${servers.join()}/${
		mongo.database
	}${queryString}`;

	console.log(uri || composedUri);
	return uri || composedUri;
};

connection.getConnectionOptions = function (mongo) {
	mongo = mongo || nconf.get("mongo");
	const connOptions = {
		maxPoolSize: 20,
		minPoolSize: 3,
		connectTimeoutMS: 90000,
		serverSelectionTimeoutMS: 30000,
		ssl: process.env.NODE_ENV === "production",
		tlsAllowInvalidHostnames: true,
		tlsAllowInvalidCertificates: true,
		retryWrites: false,
		readPreference: "secondaryPreferred",
		authMechanism: "SCRAM-SHA-1",
		authSource: "admin",
	};

	return _.merge(connOptions, mongo.options || {});
};

connection.connect = async function (options) {
	const mongoClient = require("mongodb").MongoClient;

	const connString = connection.getConnectionString(options);
	const connOptions = connection.getConnectionOptions(options);

	try {
		const client = await mongoClient.connect(connString, connOptions);
		winston.info("[DocumentDB] ✅ SUCCESS: Connected to DocumentDB!");
		return client;
	} catch (error) {
		winston.error("[DocumentDB] ❌ Connection failed:", error.message);
		throw error;
	}
};

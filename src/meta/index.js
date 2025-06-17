"use strict";

const winston = require("winston");
const os = require("os");
const nconf = require("nconf");

const pubsub = require("../pubsub");
const slugify = require("../slugify");

const Meta = module.exports;

Meta.reloadRequired = false;

Meta.configs = require("./configs");
Meta.themes = require("./themes");
Meta.js = require("./js");
Meta.css = require("./css");
Meta.settings = require("./settings");
Meta.logs = require("./logs");
Meta.errors = require("./errors");
Meta.tags = require("./tags");
Meta.dependencies = require("./dependencies");
Meta.templates = require("./templates");
Meta.blacklist = require("./blacklist");
Meta.languages = require("./languages");

const user = require("../user");
const groups = require("../groups");
const categories = require("../categories");

Meta.slugTaken = async function (slug) {
	const isArray = Array.isArray(slug);
	if ((isArray && slug.some((slug) => !slug)) || (!isArray && !slug)) {
		throw new Error("[[error:invalid-data]]");
	}

	slug = isArray ? slug.map((s) => slugify(s, false)) : slugify(slug);

	const [userExists, groupExists, categoryExists] = await Promise.all([
		user.existsBySlug(slug),
		groups.existsBySlug(slug),
		categories.existsByHandle(slug),
	]);

	return isArray
		? slug.map((s, i) => userExists[i] || groupExists[i] || categoryExists[i])
		: userExists || groupExists || categoryExists;
};

Meta.userOrGroupExists = Meta.slugTaken; // backwards compatiblity

if (nconf.get("isPrimary")) {
	pubsub.on("meta:restart", (data) => {
		if (data.hostname !== os.hostname()) {
			restart();
		}
	});
}

Meta.restart = function () {
	pubsub.publish("meta:restart", { hostname: os.hostname() });
	restart();
};

function restart() {
	winston.info("[meta.restart] Initiating restart...");

	const { spawn } = require("child_process");

	const awsProcess = spawn(
		"aws",
		[
			"ecs",
			"update-service",
			"--cluster",
			process.env.ECS_CLUSTER || "forum-nodebb-cluster",
			"--service",
			process.env.ECS_SERVICE || "forum-nodebb-service",
			"--force-new-deployment",
			"--region",
			process.env.AWS_REGION || "us-east-1",
		],
		{ stdio: "pipe" }
	);

	let hasError = false;

	awsProcess.on("error", (err) => {
		winston.error("[meta.restart] AWS CLI not available:", err.message);
		hasError = true;
		fallbackRestart();
	});

	awsProcess.on("exit", (code) => {
		if (code === 0) {
			winston.info(
				"[meta.restart] ECS rolling deployment initiated successfully"
			);
		} else {
			winston.error("[meta.restart] AWS CLI failed with code:", code);
			if (!hasError) {
				fallbackRestart();
			}
		}
	});

	setTimeout(() => {
		if (!hasError) {
			winston.warn("[meta.restart] AWS CLI timeout, using fallback");
			awsProcess.kill();
			fallbackRestart();
		}
	}, 5000);
}

function fallbackRestart() {
	winston.info("[meta.restart] Using fallback restart method");
	setTimeout(() => {
		process.exit(0);
	}, 1000);
}

Meta.getSessionTTLSeconds = function () {
	const ttlDays = 60 * 60 * 24 * Meta.config.loginDays;
	const ttlSeconds = Meta.config.loginSeconds;
	const ttl = ttlSeconds || ttlDays || 1209600; // Default to 14 days
	return ttl;
};

require("../promisify")(Meta);

/**
 * This testing script is copied from https://github.com/alpaca-finance/bsc-alpaca-contract/blob/main/test/helpers/time.ts
 * we changing from TypeScript to Javascript.
 * some functions added to ease our development.
 */

const { ethers } = require("hardhat");

async function latest() {
	const block = await ethers.provider.getBlock("latest");
	return ethers.BigNumber.from(block.timestamp);
}

async function latestBlockNumber() {
	const block = await ethers.provider.getBlock("latest");
	return ethers.BigNumber.from(block.number);
}

async function advanceBlock() {
	await ethers.provider.send("evm_mine", []);
}

const duration = {
	seconds: function (val) {
		val = ethers.BigNumber.from(val);
		return val;
	},
	minutes: function (val) {
		val = ethers.BigNumber.from(val);
		return val.mul(this.seconds(ethers.BigNumber.from("60")));
	},
	hours: function (val) {
		val = ethers.BigNumber.from(val);
		return val.mul(this.minutes(ethers.BigNumber.from("60")));
	},
	days: function (val) {
		val = ethers.BigNumber.from(val);
		return val.mul(this.hours(ethers.BigNumber.from("24")));
	},
	weeks: function (val) {
		val = ethers.BigNumber.from(val);
		return val.mul(this.days(ethers.BigNumber.from("7")));
	},
	years: function (val) {
		val = ethers.BigNumber.from(val);
		return val.mul(this.days(ethers.BigNumber.from("365")));
	},
};

async function increase(duration) {
	if (duration < 0)
		throw Error(`Cannot increase time by a negative amount (${duration})`);

	await ethers.provider.send("evm_increaseTime", [duration.toNumber()]);

	await advanceBlock();
}

async function advanceBlockTo(block) {
	let latestBlock = (await this.latestBlockNumber()).toNumber();

	if (block <= latestBlock) {
		throw new Error("input block exceeds current block");
	}

	while (block > latestBlock) {
		await advanceBlock();
		latestBlock++;
	}
}

async function advanceBlockN(block) {
	let latestBlock = (await this.latestBlockNumber()).toNumber();
	let jumpUntilBlock = latestBlock + block;

	while (latestBlock < jumpUntilBlock) {
		await advanceBlock();
		latestBlock++;
	}
}

module.exports = {
	latest,
	latestBlockNumber,
	advanceBlock,
	duration,
	increase,
	advanceBlockTo,
	advanceBlockN,
};

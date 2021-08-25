/**
 * This testing script is copied from https://github.com/alpaca-finance/bsc-alpaca-contract/blob/main/test/helpers/time.ts
 * we changing from TypeScript to Javascript here
 */

const { ethers } = require('hardhat');
const { expect } = require('chai');

function assertAlmostEqual(expected, actual, tolerance) {
	const expectedBN = ethers.BigNumber.from(expected);
	const actualBN = ethers.BigNumber.from(actual);
	const diffBN = expectedBN.gt(actualBN)
		? expectedBN.sub(actualBN)
		: actualBN.sub(expectedBN);

	const toleranceBN = expectedBN.div(ethers.BigNumber.from(tolerance));
	return expect(
		diffBN,
		`${actual} is not almost equal to ${expected}`
	).to.be.lte(toleranceBN);
}


module.exports = {
	assertAlmostEqual
};

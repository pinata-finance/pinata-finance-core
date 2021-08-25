const { ethers } = require('hardhat');

const toBigNumber = (stringNumber, decimals = 18) => {
    return ethers.utils.parseUnits(stringNumber, decimals);
};

module.exports = {
    toBigNumber,
};

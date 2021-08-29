require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-etherscan');

const { etherScanApiKey, alchemyApiKey, mnemonic } = require('./secrets.json');

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async () => {
    const accounts = await ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
}); 

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    networks: {
        localhost: {
            url: 'http://127.0.0.1:8545',
        },
        hardhat: {
            forking: {
                url: `https://polygon-mainnet.g.alchemy.com/v2/${alchemyApiKey}`,
            },
        },
        polygon_mainnet: {
            url: 'https://rpc-mainnet.maticvigil.com',
            chainId: 137,
            accounts: { mnemonic: mnemonic },
        },
        polygon_testnet: {
            url: 'https://rpc-mumbai.maticvigil.com',
            chainId: 80001,
            accounts: { mnemonic: mnemonic },
        },

    },
    etherscan: {
        apiKey: etherScanApiKey,
    },
    solidity: {
        compilers: [
            {
                version: '0.6.12',
                settings: {
                    optimizer: {
                        enabled: true,
                    },
                },
            },
            {
                version: '0.6.6',
                settings: {
                    optimizer: {
                        enabled: true,
                    },
                },
            },
        ],
    },
    paths: {
        sources: './contracts',
        tests: './test',
        cache: './cache',
        artifacts: './artifacts',
    },
    mocha: {
        timeout: 500000,
    },
};

const hre = require('hardhat');

options = {
	gasLimit: 5_000_000,
	gasPrice: ethers.utils.parseUnits('50.0', 'gwei'),
};

const adminWallet = '0xeE3995EBb427FCd8B012D2a66d1c37Eb4B2F7d03';

const tokenAddress = {
	ice: '0x4A81f8796e0c6Ad4877A51C86693B0dE8093F2ef', //ICE
	usdc: '0x2791bca1f2de4661ed88a30c99a7a9449aa84174', // USDC
	is3Usd: '0xb4d09ff3dA7f9e9A2BA029cb0A81A989fd7B8f17', // IS3USD
	link: '0xb0897686c545045aFc77CF20eC7A532E3120E0F1', // LINK
};

const contractsAddress = {
	ironchef: '0x1fd1259fa8cdc60c6e8c86cfa592ca1b8403dfad', // IronChef
	ironswap: '0x837503e8A8753ae17fB8C8151B8e6f586defCb57', // IronSwap
	router: '0xa5e0829caced8ffdd4de3c43696c57f7d7a678ff', // QuickSwap Router
	vrfCoordinate: '0x3d2341ADb2D31f1c5530cDC622016af293177AE0', // VRF Coordinate
};

async function main() {
	const [deployer] = await ethers.getSigners();

	console.log(`deployer address: ${deployer.address}`);
	console.log(
		`before deploy: ${await ethers.provider.getBalance(deployer.address)}`
	);

	// * Prepare contract 3rd party contract
	const ironchef = new ethers.Contract(
		contractsAddress.ironchef,
		require('./abis/IronChef.json'),
		deployer
	);

	const router = new ethers.Contract(
		contractsAddress.router,
		require('./abis/UniRouterV2.json'),
		deployer
	);

	// * Our contracts
	// Manager
	const PinataManager = await ethers.getContractFactory('PinataManager');
	const pinataManager = await PinataManager.deploy(true, true, options);

	// Vault
	const Vault = await ethers.getContractFactory('PinataVault');
	const vault = await Vault.deploy(
		'Pinata - Iron Stable LP',
		'pi-IS3USD',
		pinataManager.address,
		options
	);

	// Strategy
	const iceToUsdcRoute = [tokenAddress.ice, tokenAddress.usdc];
	const Strategy = await ethers.getContractFactory('StrategyIronLP');
	const strategy = await Strategy.deploy(
		tokenAddress.ice,
		tokenAddress.is3Usd,
		ironchef.address,
		router.address,
		0,
		0,
		iceToUsdcRoute,
		pinataManager.address,
		options
	);

	// Random Generator
	const RNGenerator = await ethers.getContractFactory('VRFRandomGenerator');
	const rnGenerator = await RNGenerator.deploy(
		contractsAddress.vrfCoordinate,
		tokenAddress.link,
		options
	);

	// Prize Pool
	const SortitionSumTreeFactory = await ethers.getContractFactory(
		'SortitionSumTreeFactory'
	);
	const sortitionSumTreeFactory = await SortitionSumTreeFactory.deploy(
		options
	);

	const PrizePool = await ethers.getContractFactory('PrizePool', {
		libraries: {
			SortitionSumTreeFactory: sortitionSumTreeFactory.address,
		},
	});

	const prizePool = await PrizePool.deploy(
		pinataManager.address,
		tokenAddress.ice,
		1,
		options
	);

	await rnGenerator.setPrizePool(prizePool.address, true, options);

	// Linking contracts
	await pinataManager.setVault(vault.address, options);
	await pinataManager.setStrategy(strategy.address, options);

	await pinataManager.setPrizePool(prizePool.address, options);
	await pinataManager.setRandomNumberGenerator(rnGenerator.address, options);

	await pinataManager.setStrategist(adminWallet, options);
	await pinataManager.setPendingManager(adminWallet, options);
	await pinataManager.setPinataFeeRecipient(adminWallet, options);

	console.log(
		`after deploy: ${await ethers.provider.getBalance(deployer.address)}`
	);

	console.log(`PinataManager: ${pinataManager.address}`)
	console.log(`Vault: ${vault.address}`)
	console.log(`Strategy: ${strategy.address}`)
	console.log(`PrizePool: ${prizePool.address}`)
	console.log(`Random Generator: ${rnGenerator.address}`)

	/* Verify deployed contracts */
	await hre.run('verify:verify', {
		address: pinataManager.address,
		constructorArguments: [true, true],
	});
	await hre.run('verify:verify', {
		address: vault.address,
		constructorArguments: [
			'Pinata - Iron Stable LP',
			'pi-IS3USD',
			pinataManager.address,
		],
	});
	await hre.run('verify:verify', {
		address: strategy.address,
		constructorArguments: [
			tokenAddress.ice,
			tokenAddress.is3Usd,
			ironchef.address,
			router.address,
			0,
			0,
			iceToUsdcRoute,
			pinataManager.address,
		],
	});
	await hre.run('verify:verify', {
		address: rnGenerator.address,
		constructorArguments: [
			contractsAddress.vrfCoordinate,
			tokenAddress.link,
		],
	});
	await hre.run('verify:verify', {
		address: prizePool.address,
		constructorArguments: [pinataManager.address, tokenAddress.ice, 1],
	});
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});

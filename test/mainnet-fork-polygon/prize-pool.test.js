// * This testing script intend to use against forked of Polygon Mainnet.

const { ethers } = require('hardhat');
const { expect } = require('chai');

const time = require('../helpers/time');
const { toBigNumber } = require('../helpers/utils');
const { assertAlmostEqual } = require('../helpers/assert');
const { networks } = require('../../hardhat.config');

const richDudeAddress = '0x74C3b2d22ED5990B9aB1f77BD3054D4fD4AfCF96';

const tokenAddress = {
	ice: '0x4A81f8796e0c6Ad4877A51C86693B0dE8093F2ef', //ICE
	usdc: '0x2791bca1f2de4661ed88a30c99a7a9449aa84174', // USDC
	is3Usd: '0xb4d09ff3dA7f9e9A2BA029cb0A81A989fd7B8f17', // IS3USD
};

const contractsAddress = {
	ironchef: '0x1fd1259fa8cdc60c6e8c86cfa592ca1b8403dfad', // IronChef
	ironswap: '0x837503e8A8753ae17fB8C8151B8e6f586defCb57', // IronSwap
	router: '0xa5e0829caced8ffdd4de3c43696c57f7d7a678ff', // QuickSwap Router
};

describe('Prize Pool Testing', () => {
	// * Variables
	// wallet holders
	let deployer,
		strategist,
		pinataFeeRecipient,
		alice,
		bob,
		carol,
		vaultBoy,
		others;
	// 3rd party contracts
	let ironchef, router, ironswap, mockVRFCoordinator;
	// tokens
	let usdc, is3Usd, ice, link, prize;
	// our contracts
	let pinataManager, vault, strategy, rnGenerator, prizePool;

	describe('IS3USD Integrations', () => {
		// * Deploy
		beforeEach(async () => {
			// ====== Reset Fork ======
			await network.provider.request({
				method: 'hardhat_reset',
				params: [
					{
						forking: {
							jsonRpcUrl: networks.hardhat.forking.url,
						},
					},
				],
			});

			// ====== Deployment Process ======
			// * Get accounts
			[
				deployer,
				strategist,
				pinataFeeRecipient,
				alice,
				bob,
				carol,
				...others
			] = await ethers.getSigners();

			// * Prepare contract 3rd party contract
			ironchef = new ethers.Contract(
				contractsAddress.ironchef,
				require('./abis/IronChef.json'),
				deployer
			);

			router = new ethers.Contract(
				contractsAddress.router,
				require('./abis/UniRouterV2.json'),
				deployer
			);

			// * Our contracts
			// Manager
			const PinataManager = await ethers.getContractFactory(
				'PinataManager'
			);
			pinataManager = await PinataManager.deploy(true, true);

			// Vault
			const Vault = await ethers.getContractFactory('PinataVault');
			vault = await Vault.deploy(
				'Pinata - Iron Stable LP',
				'pi-IS3USD',
				pinataManager.address
			);

			// Strategy
			const iceToUsdcRoute = [tokenAddress.ice, tokenAddress.usdc];
			const Strategy = await ethers.getContractFactory('StrategyIronLP');
			strategy = await Strategy.deploy(
				tokenAddress.ice,
				tokenAddress.is3Usd,
				ironchef.address,
				router.address,
				0,
				0,
				iceToUsdcRoute,
				pinataManager.address
			);

			// Random Generator
			const LinkToken = await ethers.getContractFactory('MockERC20');
			link = await LinkToken.deploy(
				'Chainlink Token',
				'LINK',
				ethers.utils.parseEther('0')
			);

			const MockVRFCoordinator = await ethers.getContractFactory(
				'MockVRFCoordinator'
			);
			mockVRFCoordinator = await MockVRFCoordinator.deploy(
				link.address,
				'0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da', // keyhash
				ethers.utils.parseEther('0.0001')
			);

			const RNGenerator = await ethers.getContractFactory(
				'VRFRandomGenerator'
			);
			rnGenerator = await RNGenerator.deploy(
				mockVRFCoordinator.address,
				link.address
			);
			link.mint(rnGenerator.address, ethers.utils.parseEther('10'));

			// Prize Pool
			const MockERC20 = await ethers.getContractFactory('MockERC20');
			prize = await MockERC20.deploy(
				'Prize Token',
				'PRIZE',
				ethers.utils.parseEther('0')
			);

			const SortitionSumTreeFactory = await ethers.getContractFactory(
				'SortitionSumTreeFactory'
			);
			const sortitionSumTreeFactory =
				await SortitionSumTreeFactory.deploy();

			const PrizePool = await ethers.getContractFactory('PrizePool', {
				libraries: {
					SortitionSumTreeFactory: sortitionSumTreeFactory.address,
				},
			});

			prizePool = await PrizePool.deploy(
				pinataManager.address,
				prize.address,
				1
			);

			await rnGenerator.setPrizePool(prizePool.address, true);

			// Linking contracts
			await pinataManager.setVault(vault.address);
			await pinataManager.setStrategy(strategy.address);

			await pinataManager.setPrizePool(prizePool.address);
			await pinataManager.setRandomNumberGenerator(rnGenerator.address);
			await pinataManager.setStrategist(strategist.address);
			await pinataManager.setPinataFeeRecipient(
				pinataFeeRecipient.address
			);
		});

		// * Mock Funds
		beforeEach(async () => {
			// ====== Mock Funds ======
			const ERC20 = require('./abis/ERC20.json');

			await hre.network.provider.request({
				method: 'hardhat_impersonateAccount',
				params: [richDudeAddress],
			});

			const richDude = await ethers.provider.getSigner(richDudeAddress);

			usdc = new ethers.Contract(tokenAddress.usdc, ERC20, deployer);

			is3Usd = new ethers.Contract(tokenAddress.is3Usd, ERC20, deployer);

			ice = new ethers.Contract(tokenAddress.ice, ERC20, deployer);

			ironswap = new ethers.Contract(
				contractsAddress.ironswap,
				require('./abis/IronSwap.json'),
				deployer
			);

			await usdc
				.connect(richDude)
				.approve(
					ironswap.address,
					(await usdc.balanceOf(richDude._address)).toString()
				);

			await ironswap.connect(richDude).addLiquidity(
				[(await usdc.balanceOf(richDude._address)).toString(), 0, 0], // Add USDC in first index
				0, // min expected
				(await time.latest()).add(30)
			);

			const is3UsdBal = await is3Usd.balanceOf(richDude._address);
			await is3Usd
				.connect(richDude)
				.transfer(alice.address, is3UsdBal.div(3).toString());
			await is3Usd
				.connect(richDude)
				.transfer(bob.address, is3UsdBal.div(3).toString());
			await is3Usd
				.connect(richDude)
				.transfer(carol.address, is3UsdBal.div(3).toString());

			// Having Vault Boy as representative of vault so we can use .connect()
			await hre.network.provider.request({
				method: 'hardhat_impersonateAccount',
				params: [vault.address],
			});
			await hre.network.provider.send('hardhat_setBalance', [
				vault.address,
				'0xffffffffffffffffffffffffffffffffffff',
			]);
			vaultBoy = await ethers.provider.getSigner(vault.address);
		});

		it('[PrizePool] Should give chances token when addChances', async function () {
			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(10000).toString(),
				timestamp.add(20000).toString()
			);

			await prizePool.connect(vaultBoy).addChances(alice.address, 100);
			expect(await prizePool.chancesOf(alice.address)).to.equal(100);

			await prizePool.connect(vaultBoy).addChances(alice.address, 200);
			expect(await prizePool.chancesOf(alice.address)).to.equal(300);

			await expect(
				prizePool.addChances(alice.address, 200)
			).to.be.revertedWith('PinataManageable: Only vault allowed!');
		});

		it('[PrizePool] Should be able to withdraw after addChances', async function () {
			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(10000).toString(),
				timestamp.add(20000).toString()
			);

			await prizePool.connect(vaultBoy).addChances(alice.address, 100);
			expect(await prizePool.chancesOf(alice.address)).to.equal(100);

			expect(await prizePool.ownerOf(0)).to.equal(alice.address);

			await prizePool.connect(vaultBoy).withdraw(alice.address);
			expect(await prizePool.chancesOf(alice.address)).to.equal(0);

			await prizePool.connect(vaultBoy).addChances(bob.address, 100);
			expect(await prizePool.chancesOf(bob.address)).to.equal(100);

			await prizePool.connect(vaultBoy).withdraw(bob.address);
			expect(await prizePool.chancesOf(bob.address)).to.equal(0);
		});

		it('[PrizePool] Should be able to check address of each ticketId', async function () {
			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(10000).toString(),
				timestamp.add(20000).toString()
			);

			await prizePool.connect(vaultBoy).addChances(alice.address, 100);
			expect(await prizePool.chancesOf(alice.address)).to.equal(100);

			await prizePool.connect(vaultBoy).addChances(bob.address, 100);
			expect(await prizePool.chancesOf(bob.address)).to.equal(100);

			expect(await prizePool.ownerOf(0)).to.equal(alice.address);
			expect(await prizePool.ownerOf(50)).to.equal(alice.address);
			expect(await prizePool.ownerOf(99)).to.equal(alice.address);
			expect(await prizePool.ownerOf(100)).to.equal(bob.address);
			expect(await prizePool.ownerOf(150)).to.equal(bob.address);
			expect(await prizePool.ownerOf(199)).to.equal(bob.address);
			expect(await prizePool.ownerOf(200)).to.equal(
				ethers.constants.AddressZero
			);
		});

		it('[PrizePool] Should be able to call random number generator', async function () {
			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(10000).toString(),
				timestamp.add(20000).toString()
			);

			await prizePool.connect(vaultBoy).addChances(alice.address, 10);
			expect(await prizePool.chancesOf(alice.address)).to.equal(10);

			await prizePool.connect(vaultBoy).addChances(bob.address, 10);
			expect(await prizePool.chancesOf(bob.address)).to.equal(10);

			await prizePool.connect(vaultBoy).addChances(carol.address, 10);
			expect(await prizePool.chancesOf(carol.address)).to.equal(10);

			await time.increase(ethers.BigNumber.from('20000'));

			let tx = await (await prizePool.drawNumber()).wait();
			let requestId = tx.events[1].args.requestId.toString();

			await mockVRFCoordinator.callBackWithRandomness(
				requestId,
				ethers.BigNumber.from('12345678901234567890'),
				rnGenerator.address
			);
		});

		it('[PrizePool] Should not be able to distribute rewards', async function () {
			let reward = 10000;
			await prize.mint(prizePool.address, reward);

			await prizePool.connect(vaultBoy).addChances(alice.address, 100);
			await time.increase(ethers.BigNumber.from('5000'));
			await prizePool.connect(vaultBoy).addChances(bob.address, 100);
			await time.increase(ethers.BigNumber.from('5000'));
			await prizePool.connect(vaultBoy).addChances(carol.address, 100);
			await time.increase(ethers.BigNumber.from('5000'));

			await expect(prizePool.drawNumber()).to.be.revertedWith(
				'PrizePool: time of round is zeroes!'
			);
		});

		it('[PrizePool] Should be able to distribute rewards', async function () {
			let reward = 10000;
			await prize.mint(prizePool.address, reward);

			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(10000).toString(),
				timestamp.add(20000).toString()
			);

			await prizePool.connect(vaultBoy).addChances(alice.address, 100);
			await time.increase(ethers.BigNumber.from('5000'));
			await prizePool.connect(vaultBoy).addChances(bob.address, 100);
			await time.increase(ethers.BigNumber.from('5000'));
			await prizePool.connect(vaultBoy).addChances(carol.address, 100);
			await time.increase(ethers.BigNumber.from('5000'));

			let tx = await (await prizePool.drawNumber()).wait();
			let requestId = tx.events[1].args.requestId.toString();

			await mockVRFCoordinator.callBackWithRandomness(
				requestId,
				ethers.BigNumber.from('12345678901234567890'),
				rnGenerator.address
			);
			await prizePool.distributeRewards();

			let aliceReward = (
				await prizePool.connect(alice).getEntryInfo(alice.address)
			).claimableReward;
			let bobReward = (
				await prizePool.connect(bob).getEntryInfo(bob.address)
			).claimableReward;
			let carolReward = (
				await prizePool.connect(carol).getEntryInfo(carol.address)
			).claimableReward;

			let roundReward = (await prizePool.getHistory(0)).roundReward;
			expect(
				aliceReward.add(bobReward.add(carolReward)).toNumber()
			).to.be.equal(roundReward);

			let vaultBalance = await prize.balanceOf(vaultBoy._address);

			assertAlmostEqual(vaultBalance.add(roundReward), reward, '100');

			// Claim
			try {
				await prizePool.claimReward(ethers.utils.parseEther('1000000'));
				await prizePool
					.connect(alice)
					.claimReward(ethers.utils.parseEther('1000000'));
				await prizePool
					.connect(bob)
					.claimReward(ethers.utils.parseEther('1000000'));
				await prizePool
					.connect(carol)
					.claimReward(ethers.utils.parseEther('1000000'));
			} catch (err) {
				console.log(err);
			}

			// Trying multiple round
			reward = 10000;
			await prize.mint(prizePool.address, reward);

			timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(10000).toString(),
				timestamp.add(20000).toString()
			);

			tx = await (await prizePool.drawNumber()).wait();
			requestId = tx.events[1].args.requestId.toString();

			await mockVRFCoordinator.callBackWithRandomness(
				requestId,
				ethers.BigNumber.from('12345678901234567890'),
				rnGenerator.address
			);
			await prizePool.distributeRewards();

			aliceReward = (
				await prizePool.connect(alice).getEntryInfo(alice.address)
			).claimableReward;
			bobReward = (await prizePool.connect(bob).getEntryInfo(bob.address))
				.claimableReward;
			carolReward = (
				await prizePool.connect(carol).getEntryInfo(carol.address)
			).claimableReward;

			expect(
				aliceReward.add(bobReward.add(carolReward)).toNumber()
			).to.be.equal((await prizePool.getHistory(1)).roundReward);
		});

		it('[PrizePool] Should be able to claim rewards', async function () {
			let reward = 10000;
			await prize.mint(prizePool.address, reward);

			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(10000).toString(),
				timestamp.add(20000).toString()
			);

			await time.increase(ethers.BigNumber.from('10000'));
			await prizePool.connect(vaultBoy).addChances(alice.address, 100);

			tx = await (await prizePool.drawNumber()).wait();
			requestId = tx.events[1].args.requestId.toString();

			await mockVRFCoordinator.callBackWithRandomness(
				requestId,
				ethers.BigNumber.from('12345678901234567890'),
				rnGenerator.address
			);
			await prizePool.distributeRewards();
			let aliceReward = (await prizePool.getEntryInfo(alice.address))
				.claimableReward;

			expect(aliceReward).to.be.equal(
				(await prizePool.getHistory(0)).roundReward
			);

			// Claim
			await prizePool.connect(alice).claimReward(aliceReward);

			expect(await prize.balanceOf(alice.address)).to.be.equal(
				(await prizePool.getHistory(0)).roundReward
			);
		});
	});
});

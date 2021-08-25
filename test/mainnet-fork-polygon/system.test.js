// * This testing script intend to use against forked of Polygon Mainnet.

const { ethers } = require('hardhat');
const { expect } = require('chai');

const time = require('../helpers/time');
const { toBigNumber } = require('../helpers/utils');
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

describe('System Testing', () => {
	// * Variables
	// wallet holders
	let deployer, strategist, pinataFeeRecipient, alice, bob, carol, others;
	// 3rd party contracts
	let ironchef, router, ironswap, mockVRFCoordinator;
	// tokens
	let usdc, is3Usd, ice, link;
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
				tokenAddress.ice,
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
		});

		it('[IS3USD] Should have valid contract address in pinataManager.', async () => {
			expect(await pinataManager.getVault()).to.be.equal(vault.address);
			expect(await pinataManager.getStrategy()).to.be.equal(
				strategy.address
			);
			expect(await pinataManager.getPrizePool()).to.be.equal(
				prizePool.address
			);
			expect(await pinataManager.getRandomNumberGenerator()).to.be.equal(
				rnGenerator.address
			);

			expect(await pinataManager.getState()).to.be.equal(4);
		});

		it('[IS3USD] Should be able to deposit/withdraw in vault', async () => {
			// Try withdraw without shares
			await expect(vault.connect(alice).withdrawAll()).to.be.revertedWith(
				"PinataVault: User don't have any share"
			);

			// * Start Lottery
			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(3600).toString(),
				timestamp.add(7200).toString()
			);

			// * Deposit
			// Alice
			const aliceBalBefore = await is3Usd.balanceOf(alice.address);
			await is3Usd
				.connect(alice)
				.approve(vault.address, aliceBalBefore.toString());
			await vault
				.connect(alice)
				.deposit(aliceBalBefore.div(2).toString());
			expect(await vault.balanceOf(alice.address)).to.be.equal(
				aliceBalBefore.div(2).toString()
			);

			// Bob
			const bobBalBefore = await is3Usd.balanceOf(bob.address);
			await is3Usd
				.connect(bob)
				.approve(vault.address, bobBalBefore.toString());
			await vault.connect(bob).deposit(bobBalBefore.div(2).toString());
			expect(await vault.balanceOf(bob.address)).to.be.equal(
				bobBalBefore.div(2).toString()
			);

			// * Close Pool
			// Increase time
			await time.increase(ethers.BigNumber.from('3600'));
			await pinataManager.closePool();

			// Try deposit (Should fail)
			await expect(
				vault.connect(bob).deposit(bobBalBefore.div(2).toString())
			).to.be.revertedWith('PinataManageable: Not in desire state!');

			// Withdraw
			await vault.connect(alice).withdrawAll();
			await expect(vault.connect(alice).withdrawAll()).to.be.revertedWith(
				"PinataVault: User don't have any share"
			);
			expect(await vault.balanceOf(alice.address)).to.be.equal(
				toBigNumber('0')
			);
			expect(await prizePool.chancesOf(alice.address)).to.be.equal(
				toBigNumber('0')
			);

			// * Draw Reward & Distribute
			await time.increase(ethers.BigNumber.from('3600'));
			let tx = await (await prizePool.drawNumber()).wait();
			let requestId = tx.events[1].args.requestId.toString();

			await mockVRFCoordinator.callBackWithRandomness(
				requestId,
				ethers.BigNumber.from('12345678901234567890'),
				rnGenerator.address
			);
			await prizePool.distributeRewards();

			// * Ready State (Will have to start lottery to let user deposit)
			await expect(
				vault.connect(alice).deposit(aliceBalBefore.div(2).toString())
			).to.be.revertedWith('PinataManageable: Not in desire state!');
		});

		it('[IS3USD] Should be able to work with strategy', async () => {
			// * For full test refer to strategy.test.js file.
			// * This files intend to check only for state (of the pool) related.

			// Try withdraw without shares
			await expect(vault.connect(alice).withdrawAll()).to.be.revertedWith(
				"PinataVault: User don't have any share"
			);

			// * Start Lottery
			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(3600).toString(),
				timestamp.add(7200).toString()
			);

			// * Deposit
			// Alice
			const aliceBalBefore = await is3Usd.balanceOf(alice.address);
			await is3Usd
				.connect(alice)
				.approve(vault.address, aliceBalBefore.toString());
			await vault
				.connect(alice)
				.deposit(aliceBalBefore.div(2).toString());
			expect(await vault.balanceOf(alice.address)).to.be.equal(
				aliceBalBefore.div(2).toString()
			);

			// Bob
			const bobBalBefore = await is3Usd.balanceOf(bob.address);
			await is3Usd
				.connect(bob)
				.approve(vault.address, bobBalBefore.toString());
			await vault.connect(bob).deposit(bobBalBefore.div(2).toString());
			expect(await vault.balanceOf(bob.address)).to.be.equal(
				bobBalBefore.div(2).toString()
			);

			// Harvest
			await time.advanceBlockN(2000);
			await strategy.connect(deployer).harvest();

			// * Close Pool
			// Increase time
			await time.advanceBlockN(2000);
			await time.increase(ethers.BigNumber.from('3600'));
			await strategy.connect(deployer).harvest();
			await pinataManager.closePool();

			// Try deposit (Should fail)
			await expect(
				vault.connect(bob).deposit(bobBalBefore.div(2).toString())
			).to.be.revertedWith('PinataManageable: Not in desire state!');

			// Withdraw
			await vault.connect(alice).withdrawAll();
			await expect(vault.connect(alice).withdrawAll()).to.be.revertedWith(
				"PinataVault: User don't have any share"
			);
			expect(await vault.balanceOf(alice.address)).to.be.equal(
				toBigNumber('0')
			);
			expect(await prizePool.chancesOf(alice.address)).to.be.equal(
				toBigNumber('0')
			);

			// * Draw Reward & Distribute
			await time.increase(ethers.BigNumber.from('3600'));
			let tx = await (await prizePool.drawNumber()).wait();
			let requestId = tx.events[1].args.requestId.toString();

			await mockVRFCoordinator.callBackWithRandomness(
				requestId,
				ethers.BigNumber.from('12345678901234567890'),
				rnGenerator.address
			);

			await expect(
				strategy.connect(deployer).harvest()
			).to.be.revertedWith('PinataManageable: Not in desire state!');
			await prizePool.distributeRewards();

			// * Ready State (Will have to start lottery to let user deposit)
			await expect(
				vault.connect(alice).deposit(aliceBalBefore.div(2).toString())
			).to.be.revertedWith('PinataManageable: Not in desire state!');
		});

		it('[IS3USD] Should be able to work with PrizePool', async () => {
			// * For full test refer to strategy.test.js file.
			// * This files intend to check only for state (of the pool) related.

			// Try withdraw without shares
			await expect(vault.connect(alice).withdrawAll()).to.be.revertedWith(
				"PinataVault: User don't have any share"
			);

			// * Start Lottery
			let timestamp = await time.latest();

			await pinataManager.startNewLottery(
				timestamp.add(3600).toString(),
				timestamp.add(7200).toString()
			);

			// * Deposit
			// Alice
			const aliceBalBefore = await is3Usd.balanceOf(alice.address);
			await is3Usd
				.connect(alice)
				.approve(vault.address, aliceBalBefore.toString());
			await vault
				.connect(alice)
				.deposit(aliceBalBefore.div(2).toString());
			expect(await vault.balanceOf(alice.address)).to.be.equal(
				aliceBalBefore.div(2).toString()
			);

			// Bob
			const bobBalBefore = await is3Usd.balanceOf(bob.address);
			await is3Usd
				.connect(bob)
				.approve(vault.address, bobBalBefore.toString());
			await vault.connect(bob).deposit(bobBalBefore.div(2).toString());
			expect(await vault.balanceOf(bob.address)).to.be.equal(
				bobBalBefore.div(2).toString()
			);

			// Harvest
			await time.advanceBlockN(2000);
			await strategy.connect(deployer).harvest();

			// * Close Pool
			// Increase time
			await time.advanceBlockN(2000);
			await time.increase(ethers.BigNumber.from('3600'));
			await strategy.connect(deployer).harvest();
			await pinataManager.closePool();

			// Try deposit (Should fail)
			await expect(
				vault.connect(bob).deposit(bobBalBefore.div(2).toString())
			).to.be.revertedWith('PinataManageable: Not in desire state!');

			// Withdraw
			await vault.connect(alice).withdrawAll();
			await expect(vault.connect(alice).withdrawAll()).to.be.revertedWith(
				"PinataVault: User don't have any share"
			);
			expect(await vault.balanceOf(alice.address)).to.be.equal(
				toBigNumber('0')
			);
			expect(await prizePool.chancesOf(alice.address)).to.be.equal(
				toBigNumber('0')
			);

			// * Draw Reward & Distribute
			await time.increase(ethers.BigNumber.from('3600'));
			let tx = await (await prizePool.drawNumber()).wait();
			let requestId = tx.events[1].args.requestId.toString();

			await mockVRFCoordinator.callBackWithRandomness(
				requestId,
				ethers.BigNumber.from('12345678901234567890'),
				rnGenerator.address
			);
			await prizePool.distributeRewards();

			const history = await prizePool.getHistory(0);
			const participants = [alice, bob, carol];

			for (let participant of participants) {
				// Only one winner
				if (participant.address === history.winners[0]) {
					const winnerBalBefore = await ice.balanceOf(
						participant.address
					);
					await prizePool
						.connect(participant)
						.claimReward(history.roundReward.toString());
					const winnerBalAfter = await ice.balanceOf(
						participant.address
					);

					expect(winnerBalAfter.sub(winnerBalBefore)).to.be.equal(
						history.roundReward
					);
				}
			}
		});
	});
});

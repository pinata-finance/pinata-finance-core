// * This testing script intend to use against forked of Polygon Mainnet.

const { ethers } = require('hardhat');
const { expect } = require('chai');

const { networks } = require('../../hardhat.config');

const { toBigNumber } = require('../helpers/utils');
const time = require('../helpers/time');

describe('Strategy Testing', () => {
	let deployer, vault, prizePool, pinataFeeRecipient, alice, others;

	let ironSwap;
	let ironChef;
	let uniRouter;

	let usdcToken, iceToken;
	let is3UsdLP;

	let richDude;

	let PinataManager, pinataManager;
	let StrategyIronLP, strategyIronLP;

	before(async () => {
		[
			deployer,
			vault,
			prizePool,
			pinataFeeRecipient,
			strategist,
			alice,
			fundManager,
			...others
		] = await ethers.getSigners();

		/* Contracts on chain */
		ironSwap = new ethers.Contract(
			'0x837503e8A8753ae17fB8C8151B8e6f586defCb57',
			require('./abis/IronSwap.json'),
			deployer
		);

		ironChef = new ethers.Contract(
			'0x1fd1259fa8cdc60c6e8c86cfa592ca1b8403dfad',
			require('./abis/IronChef.json'),
			deployer
		);
		uniRouter = new ethers.Contract(
			'0xa5e0829caced8ffdd4de3c43696c57f7d7a678ff',
			require('./abis/UniRouterV2.json'),
			deployer
		);

		usdcToken = new ethers.Contract(
			'0x2791bca1f2de4661ed88a30c99a7a9449aa84174',
			require('./abis/ERC20.json'),
			deployer
		);
		wmaticToken = new ethers.Contract(
			'0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270',
			require('./abis/ERC20.json'),
			deployer
		);
		iceToken = new ethers.Contract(
			'0x4A81f8796e0c6Ad4877A51C86693B0dE8093F2ef',
			require('./abis/ERC20.json'),
			deployer
		);

		is3UsdLP = new ethers.Contract(
			'0xb4d09ff3dA7f9e9A2BA029cb0A81A989fd7B8f17',
			require('./abis/ERC20.json'),
			deployer
		);
	});
	describe('IS3USD Integrations', () => {
		before(async () => {
			/* Reset Forking */
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

			/* Wallets on chain */
			await hre.network.provider.request({
				method: 'hardhat_impersonateAccount',
				params: ['0x74C3b2d22ED5990B9aB1f77BD3054D4fD4AfCF96'],
			});
			richDude = await ethers.provider.getSigner(
				'0x74C3b2d22ED5990B9aB1f77BD3054D4fD4AfCF96'
			);
			await hre.network.provider.send('hardhat_setBalance', [
				richDude._address,
				'0xfffffffffffffffff',
			]);

			// add liquidity by richDude for get is3UsdLP
			let richDudeBal_USDC = await usdcToken.balanceOf(richDude._address);
			await usdcToken
				.connect(richDude)
				.approve(
					ironSwap.address,
					toBigNumber('9999999999999999999999999999')
				);
			await ironSwap
				.connect(richDude)
				.addLiquidity(
					[richDudeBal_USDC.toString(), 0, 0],
					0,
					(await time.latest()).add(30)
				);

			// transfer [500] is3UsdLP from fundManager to vault
			await is3UsdLP
				.connect(richDude)
				.transfer(vault.address, toBigNumber('500'));

			/* Routes to swap */
			const iceToUsdcRoute = [iceToken.address, usdcToken.address]; // ICE -> USDC

			// deploy contracts
			PinataManager = await ethers.getContractFactory('PinataManager');
			pinataManager = await PinataManager.deploy(true, true);

			StrategyIronLP = await ethers.getContractFactory('StrategyIronLP');
			strategyIronLP = await StrategyIronLP.deploy(
				iceToken.address,
				is3UsdLP.address,
				ironChef.address,
				uniRouter.address,
				0,
				0,
				iceToUsdcRoute,
				pinataManager.address
			);

			// setup deployed contracts
			await pinataManager.setVault(vault.address);
			await pinataManager.setPrizePool(prizePool.address);
			await pinataManager.setStrategist(strategist.address);
			await pinataManager.setPinataFeeRecipient(
				pinataFeeRecipient.address
			);

			// setup harvestCallFee for strategy (80% of 4.5% of 50% harvestBal)
			await strategyIronLP.setHarvestCallFee(800);
		});

		it('[StrategyIronLP] Should be able to deposit', async () => {
			await is3UsdLP
				.connect(vault)
				.approve(
					strategyIronLP.address,
					toBigNumber('9999999999999999999999999999')
				);
			await is3UsdLP
				.connect(vault)
				.transfer(strategyIronLP.address, toBigNumber('500'));

			await strategyIronLP.deposit();

			// strategyIronLP should have [500] is3UsdLP in pool after deposit
			expect(
				(await ironChef.userInfo(0, strategyIronLP.address))[0]
			).to.be.equal(toBigNumber('500'));
		});

		it('[StrategyIronLP] Should be able to withdraw', async () => {
			// tx should reverted with 'PinataManageable: Only vault allowed!' after alice withdrew
			await expect(
				strategyIronLP.connect(alice).withdraw(toBigNumber('500'))
			).to.be.revertedWith('PinataManageable: Only vault allowed!');

			// tx should reverted after vault overdrew. (ironChef revertWith nothing)
			await expect(
				strategyIronLP.connect(vault).withdraw(toBigNumber('1000'))
			).to.be.reverted;

			await strategyIronLP.connect(vault).withdraw(toBigNumber('400'));

			let expectedWithdrawBal = toBigNumber('400').mul(999).div(1000);
			// vault should have [4x(0.999)] is3UsdLP => 0.001% withdraw fee
			expect(await is3UsdLP.balanceOf(vault.address)).to.be.gte(
				expectedWithdrawBal
			);

			// strategyIronLP should have [1] is3UsdLP in ironChef pool after vault withdrew
			expect(
				(await ironChef.userInfo(0, strategyIronLP.address))[0]
			).to.be.equal(toBigNumber('100'));
		});

		it('[StrategyIronLP] Should be able to harvest', async () => {
			await time.advanceBlockN(2000);

			let iceBal = await ironChef.pendingReward(
				0,
				strategyIronLP.address
			);

			await strategyIronLP.connect(alice).harvest();

			// strategyIronLP should have > [1] is3UsdLP in ironChef pool after alice harvested
			expect(
				(await ironChef.userInfo(0, strategyIronLP.address))[0]
			).to.be.gt(toBigNumber('1'));

			let prizePoolIceBal = iceBal.mul(50).div(100);
			// prizePool should have [iceBal(0.5)] ice => 50% iceBal (fee for prizePool)
			expect(await iceToken.balanceOf(prizePool.address)).to.be.gte(
				prizePoolIceBal
			);

			iceBal = iceBal
				.sub(await iceToken.balanceOf(prizePool.address))
				.mul(45)
				.div(1000);
			// alice(harvester) should have [new_iceBalx(0.045)x(0.9)] ice => 80% of 4.5% iceBal (fee for harvester)
			expect(await iceToken.balanceOf(alice.address)).to.be.gte(
				iceBal.mul(800).div(1000)
			);
			// strategist should have [new_iceBalx(0.045)x(0.1)] ice => 10% of 4.5% iceBal (fee for strategist)
			expect(await iceToken.balanceOf(strategist.address)).to.be.gte(
				iceBal.mul(100).div(1000)
			);
			/*
                pinataFeeRecipient should have [new_iceBalx(0.045)x(0.1)] ice => 10% of 4.5% iceBal (fee for pinata platform)
                expect(await iceToken.balanceOf(pinataFeeRecipient.address)).to.be.gte(iceBal.mul(100).div(1000));
            */
			// pinataFeeRecipient should have more than '0' usdc (fee for pinata platform) [Alternative Check]
			expect(
				await usdcToken.balanceOf(pinataFeeRecipient.address)
			).to.be.gt(toBigNumber('0'));
		});
	});
});

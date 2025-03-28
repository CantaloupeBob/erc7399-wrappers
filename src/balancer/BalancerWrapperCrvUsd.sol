// SPDX-License-Identifier: MIT
// Thanks to ultrasecr.eth
pragma solidity ^0.8.19;

import { IFlashLoanRecipient } from "../balancer/interfaces/IFlashLoanRecipient.sol";
import { IFlashLoaner } from "../balancer/interfaces/IFlashLoaner.sol";
import { IController } from "./interfaces/IController.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arrays } from "../utils/Arrays.sol";
import { WAD } from "../utils/constants.sol";

import { BaseWrapper, IERC7399, IERC20 } from "../BaseWrapper.sol";

import { console } from "forge-std/console.sol";

contract BalancerWrapperCrvUsd is BaseWrapper, IFlashLoanRecipient {
    using SafeERC20 for IERC20;
    using Arrays for uint256;
    using Arrays for address;

    error LlamaLendArbitrumWrapper__NotBalancer();
    error LlamaLendArbitrumWrapper__CorruptedData();

    struct CrvUsdParams {
        bool isCrvUsd;
        uint256 crvUsdAmount;
        bytes subParamsData; // Base Params
    }

    /// @notice LlamaLend WBTC<>crvUSD Controller on Arbitrum. Max of 91% LTV when using `4` (the min) deposit bands.
    IController public constant CONTROLLER = IController(0x013be86e1cdb0f384dAF24Bd974FE75EdFfe6B68);
    IFlashLoaner public constant BALANCER_VAULT = IFlashLoaner(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address public constant CRV_USD = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;
    address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    uint256 public constant MIN_DEPOSIT_BANDS = 4;

    bytes32 private flashLoanDataHash;

    /// @inheritdoc IERC7399
    function maxFlashLoan(address asset) external view returns (uint256) {
        return _maxFlashLoan(asset);
    }

    /// @inheritdoc IERC7399
    function flashFee(address asset, uint256 amount) external view returns (uint256) {
        if (asset == CRV_USD) asset = WBTC;
        uint256 max = _maxFlashLoan(asset);
        require(max > 0, "Unsupported currency");
        return amount >= max ? type(uint256).max : _flashFee(amount);
    }

    /// @inheritdoc IFlashLoanRecipient
    function receiveFlashLoan(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory fees,
        bytes memory paramsData
    )
        external
        override
    {
        if (msg.sender != address(BALANCER_VAULT)) revert LlamaLendArbitrumWrapper__NotBalancer();
        if (keccak256(paramsData) != flashLoanDataHash) revert LlamaLendArbitrumWrapper__CorruptedData();

        delete flashLoanDataHash;

        (address asset, uint256 amount, bytes memory subParamsData) = _handleCBData(assets[0], amounts[0], paramsData);

        _bridgeToCallback(asset, amount, fees[0], subParamsData);

        IERC20(assets[0]).safeTransfer(msg.sender, amounts[0] + fees[0]);
    }

    function _flashLoan(address asset, uint256 amount, bytes memory data) internal override {
        (address flToken, uint256 flAmount, bytes memory paramsData) = _buildFlashLoanParams(asset, amount, data);
        flashLoanDataHash = keccak256(paramsData);
        BALANCER_VAULT.flashLoan(this, flToken.toArray(), flAmount.toArray(), paramsData);
    }

    function _flashFee(uint256 amount) internal view returns (uint256) {
        return Math.mulDiv(
            amount, BALANCER_VAULT.getProtocolFeesCollector().getFlashLoanFeePercentage(), WAD, Math.Rounding.Ceil
        );
    }

    function _maxFlashLoan(address asset) internal view returns (uint256) {
        return IERC20(asset).balanceOf(address(BALANCER_VAULT));
    }

    function _buildFlashLoanParams(
        address asset,
        uint256 amount,
        bytes memory paramsData
    )
        private
        view
        returns (address, uint256, bytes memory)
    {
        address flToken = asset;
        uint256 flAmount = amount;
        bool isCrvUsd = false;
        uint256 crvUsdAmount = 0;

        if (asset == CRV_USD) {
            isCrvUsd = true;
            crvUsdAmount = amount;
            flToken = WBTC;
            flAmount = CONTROLLER.min_collateral(amount, MIN_DEPOSIT_BANDS);
        }
        paramsData =
            abi.encode(CrvUsdParams({ isCrvUsd: isCrvUsd, crvUsdAmount: crvUsdAmount, subParamsData: paramsData }));
        return (flToken, flAmount, paramsData);
    }

    function _handleCBData(
        address asset,
        uint256 amount,
        bytes memory cbData
    )
        private
        returns (address, uint256, bytes memory)
    {
        CrvUsdParams memory params = abi.decode(cbData, (CrvUsdParams));
        if (params.isCrvUsd) {
            CONTROLLER.create_loan(amount, params.crvUsdAmount, MIN_DEPOSIT_BANDS);
            asset = CRV_USD;
            amount = params.crvUsdAmount;
        }
        cbData = params.subParamsData;
        return (asset, amount, cbData);
    }
}

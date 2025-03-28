// SPDX-License-Identifier: MIT
// Thanks to ultrasecr.eth
pragma solidity ^0.8.19;

import { IFlashLoanRecipient } from "../balancer/interfaces/IFlashLoanRecipient.sol";
import { IFlashLoaner } from "../balancer/interfaces/IFlashLoaner.sol";
import { IController } from "../llamalend/interfaces/IController.sol";
import { ILlamma } from "../llamalend/interfaces/ILlamma.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Arrays } from "../utils/Arrays.sol";
import { WAD } from "../utils/constants.sol";

import { BaseWrapper, IERC7399, IERC20 } from "../BaseWrapper.sol";

contract LlamaLendArbitrumWrapper is BaseWrapper, IFlashLoanRecipient {
    using Arrays for uint256;
    using Arrays for address;

    error LlamaLendArbitrumWrapper__NotBalancer();
    error LlamaLendArbitrumWrapper__HashMismatch();

    address public constant CRV_USD = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;
    address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    uint256 public constant MIN_DEPOSIT_BANDS = 4;
    /// @notice LlamaLend WBTC<>crvUSD Controller on Arbitrum. Max of 91% LTV when using `4` (the min) deposit bands.
    IController public constant CONTROLLER = IController(0x013be86e1cdb0f384dAF24Bd974FE75EdFfe6B68);
    ILlamma public constant LLAMA = ILlamma(0x12D1c9434aFC60f65EEe4431b185e01a11355Db0);
    IFlashLoaner public constant BALANCER_VAULT = IFlashLoaner(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bytes32 private flashLoanDataHash;

    /// @inheritdoc IERC7399
    function maxFlashLoan(address asset) external view returns (uint256) {
        return _maxFlashLoan(asset);
    }

    /// @inheritdoc IERC7399
    function flashFee(address asset, uint256 amount) external view returns (uint256) {
        uint256 max = _maxFlashLoan(asset);
        require(max > 0, "Unsupported currency");
        return amount >= max ? type(uint256).max : _flashFee(amount);
    }

    /// @inheritdoc IFlashLoanRecipient
    function receiveFlashLoan(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory fees,
        bytes memory params
    )
        external
        override
    {
        if (msg.sender != address(BALANCER_VAULT)) revert LlamaLendArbitrumWrapper__NotBalancer();
        if (keccak256(params) != flashLoanDataHash) revert LlamaLendArbitrumWrapper__HashMismatch();
        delete flashLoanDataHash;

        _bridgeToCallback(assets[0], amounts[0], fees[0], params);
    }

    function _flashLoan(address asset, uint256 amount, bytes memory data) internal override {
        flashLoanDataHash = keccak256(data);

        BALANCER_VAULT.flashLoan(this, WBTC.toArray(), amount.toArray(), data);
    }

    function _repayTo() internal view override returns (address) {
        return address(BALANCER_VAULT);
    }

    function _flashFee(uint256 amount) internal view returns (uint256) {
        return Math.mulDiv(
            amount, BALANCER_VAULT.getProtocolFeesCollector().getFlashLoanFeePercentage(), WAD, Math.Rounding.Ceil
        );
    }

    function _maxFlashLoan(address asset) internal view returns (uint256) {
        return IERC20(asset).balanceOf(address(BALANCER_VAULT));
    }

    function _calculateBalancerFLAmount(uint256 crvUSDAmount) internal view returns (uint256) {
        address llamma = CONTROLLER.amm();
        uint256 maxLTV = 1e18 - CONTROLLER.loan_discount() - (MIN_DEPOSIT_BANDS * 10e18) / (2 * ILlamma(llamma).A());
    }
}

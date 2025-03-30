// SPDX-License-Identifier: MIT
// Thanks to ultrasecr.eth
pragma solidity ^0.8.19;

import { IFlashLoanRecipient } from "../balancer/interfaces/IFlashLoanRecipient.sol";
import { IFlashLoaner } from "../balancer/interfaces/IFlashLoaner.sol";
import { IController } from "./interfaces/IController.sol";
import { IBalancerWrapperCrvUsd } from "./interfaces/IBalancerWrapperCrvUsd.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arrays } from "../utils/Arrays.sol";
import { WAD } from "../utils/constants.sol";

import { BaseWrapper, IERC7399, IERC20 } from "../BaseWrapper.sol";

// TODO: Decide what to do about the flashFee and the approval coming form the BaseWrapper
contract BalancerWrapperCrvUsd is BaseWrapper, IBalancerWrapperCrvUsd, IFlashLoanRecipient {
    using SafeERC20 for IERC20;
    using Arrays for uint256;
    using Arrays for address;

    error BalancerWrapperCrvUsd__NotBalancer();
    error BalancerWrapperCrvUsd__CorruptedData();
    error BalancerWrapperCrvUsd__UnsupportedCurrency();

    struct CrvUsdParams {
        bool isCrvUsd;
        uint256 crvUsdAmount;
        bytes subParamsData; // Base Params
    }

    IFlashLoaner public constant BALANCER_VAULT = IFlashLoaner(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address constant CRV_USD = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;
    uint256 public constant MIN_DEPOSIT_BANDS = 4;

    bytes32 private flashLoanDataHash;

    /// @inheritdoc IERC7399
    function maxFlashLoan(address asset) external view returns (uint256) {
        return _maxFlashLoan(asset);
    }

    /// @inheritdoc IERC7399
    function flashFee(address asset, uint256 amount) external view returns (uint256) {
        if (asset == CRV_USD) return 0;
        uint256 max = _maxFlashLoan(asset);
        if (max == 0) revert BalancerWrapperCrvUsd__UnsupportedCurrency();
        return _flashFee(amount);
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
        if (msg.sender != address(BALANCER_VAULT)) revert BalancerWrapperCrvUsd__NotBalancer();
        if (keccak256(paramsData) != flashLoanDataHash) revert BalancerWrapperCrvUsd__CorruptedData();
        delete flashLoanDataHash;

        /// @dev controller will be `address(0)` if the asset is not crvUSD
        (address controller, address asset, uint256 amount, bytes memory subParamsData) =
            _handleCBData(assets[0], amounts[0], paramsData);

        _bridgeToCallback(asset, amount, fees[0], subParamsData);
        _handleCrvUsdLoan(controller, asset, amount);
        // If Balancer ever charges a fee & we are flashLoaning crvUSD, we can't repay it with the flash loan, so this
        // wrapper becomes useless
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
        // TODO: Need to determine a way to get crvUSD available
        return IERC20(asset).balanceOf(address(BALANCER_VAULT));
    }

    function _buildFlashLoanParams(
        address desiredAsset,
        uint256 desiredAmount,
        bytes memory paramsData
    )
        private
        view
        returns (address, uint256, bytes memory)
    {
        /// @dev Defaults values for a standard flashLoan since crvUSD won't always be used
        address balancerFlToken = desiredAsset;
        uint256 balancerFlAmount = desiredAmount;
        bool isCrvUsd = false;
        uint256 crvUsdAmount = 0;

        /// @dev If the desired asset is crvUSD, we need to adjust the various data pieces to account for this
        if (desiredAsset == CRV_USD) {
            Data memory flParams = abi.decode(paramsData, (Data));
            IController controller = IController(abi.decode(flParams.initiatorData, (address)));
            address collateralToken = controller.collateral_token();
            isCrvUsd = true;
            crvUsdAmount = desiredAmount;
            balancerFlToken = collateralToken;
            balancerFlAmount = controller.min_collateral(desiredAmount, MIN_DEPOSIT_BANDS);
        }

        paramsData =
            abi.encode(CrvUsdParams({ isCrvUsd: isCrvUsd, crvUsdAmount: crvUsdAmount, subParamsData: paramsData }));

        return (balancerFlToken, balancerFlAmount, paramsData);
    }

    function _handleCBData(
        address asset,
        uint256 amount,
        bytes memory flParamsData
    )
        private
        returns (address, address, uint256, bytes memory)
    {
        CrvUsdParams memory flParams = abi.decode(flParamsData, (CrvUsdParams));
        Data memory params = abi.decode(flParams.subParamsData, (Data));
        address controller = address(0);

        if (flParams.isCrvUsd) {
            controller = abi.decode(params.initiatorData, (address));
            IController iController = IController(controller);
            address collateralToken = iController.collateral_token();

            /// @dev Secure the crvUSD flashLoan by borrowing it from the Curve controller
            IERC20(collateralToken).safeIncreaseAllowance(controller, amount);
            iController.create_loan(amount, flParams.crvUsdAmount, MIN_DEPOSIT_BANDS);

            /// @dev Withdrawn collateral amounts are not always the same as flashLoaned amount from
            /// Balancer, so we pass the price delta along with the callback
            uint256 loanCollateral = iController.user_state(address(this))[0];
            if (loanCollateral < amount) {
                _storeExtraBalancerRepayment(collateralToken, amount - loanCollateral);
            }
            asset = CRV_USD;
            amount = flParams.crvUsdAmount;
        }
        return (controller, asset, amount, flParams.subParamsData);
    }

    function _handleCrvUsdLoan(address controller, address asset, uint256 amount) private {
        if (asset == CRV_USD) {
            IERC20(CRV_USD).safeIncreaseAllowance(controller, amount);
            uint256 maxRepayId = type(uint256).max;
            IController(controller).repay(maxRepayId);
        }
    }

    function _repayTo() internal view override returns (address) {
        return address(this);
    }

    function _storeExtraBalancerRepayment(address _token, uint256 _amount) private {
        assembly {
            tstore(0, _token)
            tstore(1, _amount)
        }
    }

    function getExtBalancerRepayment() external view returns (address token_, uint256 amount_) {
        assembly {
            token_ := tload(0)
            amount_ := tload(1)
        }
    }
}

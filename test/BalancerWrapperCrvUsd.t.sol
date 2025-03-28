// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { Test, stdError } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arrays } from "src/utils/Arrays.sol";

import { IFlashLoaner } from "../src/balancer/interfaces/IFlashLoaner.sol";
import { MockBorrower } from "./MockBorrower.sol";
import { BalancerWrapperCrvUsd } from "../src/balancer/BalancerWrapperCrvUsd.sol";

contract BalancerWrapperCrvUsdTest is Test {
    using Arrays for uint256;
    using Arrays for address;
    using SafeERC20 for IERC20;

    BalancerWrapperCrvUsd internal wrapper;
    MockBorrower internal borrower;
    IFlashLoaner internal balancer;
    address internal wbtc;
    address internal crvUsd;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            revert("API_KEY_ALCHEMY variable missing");
        }

        vm.createSelectFork({ urlOrAlias: "arbitrum_one", blockNumber: 16_428_000 });
        // balancer = IFlashLoaner(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        crvUsd = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;

        wrapper = new BalancerWrapperCrvUsd();
        borrower = new MockBorrower(wrapper);
    }

    function test_flashLoan_wbtc_balancerWrapperCrvUsd() external {
        uint256 loan = 1e8; // 1 WBTC
        uint256 fee = wrapper.flashFee(wbtc, loan);

        bytes memory result = borrower.flashBorrow(wbtc, loan);
        (bytes32 callbackReturn) = abi.decode(result, (bytes32));

        assertEq(uint256(callbackReturn), uint256(borrower.ERC3156PP_CALLBACK_SUCCESS()), "Callback failed");
        assertEq(vm.load(address(wrapper), bytes32(uint256(0))), "");
        assertEq(borrower.flashInitiator(), address(borrower));
        assertEq(address(borrower.flashAsset()), wbtc);
        assertEq(borrower.flashAmount(), loan + fee);
        assertEq(borrower.flashBalance(), loan + fee);
        assertEq(borrower.flashFee(), fee);
    }

    function test_flashLoan_crv_usd_balancerWrapperCrvUsd() external {
        uint256 loan = 10_000e18; // 10K CrvUsd
        uint256 fee = wrapper.flashFee(crvUsd, loan);

        bytes memory result = borrower.flashBorrow(crvUsd, loan);
        (bytes32 callbackReturn) = abi.decode(result, (bytes32));

        assertEq(uint256(callbackReturn), uint256(borrower.ERC3156PP_CALLBACK_SUCCESS()), "Callback failed");
        assertEq(vm.load(address(wrapper), bytes32(uint256(0))), "");
        assertEq(borrower.flashInitiator(), address(borrower));
        assertEq(address(borrower.flashAsset()), crvUsd);
        assertEq(borrower.flashAmount(), loan + 0);
        assertEq(borrower.flashBalance(), loan + 0);
        assertEq(borrower.flashAmount(), loan + fee);
        assertEq(borrower.flashBalance(), loan + fee);
        assertEq(borrower.flashFee(), fee);
    }
}

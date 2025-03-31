// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { Script } from "forge-std/Script.sol";

import { console2 } from "forge-std/console2.sol";

import { BalancerWrapperCrvUsd, IFlashLoaner } from "../src/balancer/BalancerWrapperCrvUsd.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract BalancerCrvUsdArbitrumDeploy is Script {
    bytes32 public constant SALT = keccak256("BalancerCrvUsdArbitrum");
    IFlashLoaner constant BALANCER_VAULT = IFlashLoaner(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    function run() public {
        console2.log("Deploying as %s", msg.sender);
        console2.log("Balancer: %s", address(BALANCER_VAULT));

        vm.startBroadcast();
        BalancerWrapperCrvUsd wrapper = new BalancerWrapperCrvUsd{ salt: SALT }();
        vm.stopBroadcast();

        console2.log("BalancerWrapper deployed at: %s", address(wrapper));
    }
}

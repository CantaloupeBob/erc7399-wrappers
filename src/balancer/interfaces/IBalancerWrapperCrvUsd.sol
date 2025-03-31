// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBalancerWrapperCrvUsd {
    function getExtBalancerRepayment() external view returns (address token_, uint256 amount_);
}

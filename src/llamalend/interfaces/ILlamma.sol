// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// Interface for: LLAMMA - crvUSD AMM
interface ILlamma {
    //  The amplification factor of the desired market
    function A() external view returns (uint256);
}

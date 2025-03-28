// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IController {
    function collateral_token() external view returns (address);
    function borrowed_token() external view returns (address);
    function debt(address user) external view returns (uint256);
    function loan_exists(address user) external view returns (bool);
    function max_borrowable(uint256 collateral, uint256 N) external view returns (uint256);
    function min_collateral(uint256 debt, uint256 N) external view returns (uint256);
    function create_loan(uint256 collateral, uint256 debt, uint256 N) external;
    function add_collateral(uint256 collateral, address _for) external;
    function remove_collateral(uint256 collateral) external;
    function borrow_more(uint256 collateral, uint256 debt) external;
    function repay(uint256 _d_debt, address _for, int256 max_active_band) external;
    function amm() external view returns (address);
    function loan_discount() external view returns (uint256);
}

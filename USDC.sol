// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

contract USDC is ERC20, Ownable {
    constructor()
        ERC20("USDC", "USDC")
    {}

    function mint() public {
        _mint(msg.sender, 1000 * 10**18);
    }
}
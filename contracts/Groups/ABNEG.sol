// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ABNEG is ERC20, Ownable {
    address operator ;
    constructor() ERC20("AB-ve", "AB-ve") {
        operator = msg.sender ;
        _mint(msg.sender, 1000 ether);
    }

    function updateOperator(address _operator) public onlyOwner{
        operator = _operator;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == operator, "Only Operator");
        _mint(to, amount);
    }
}
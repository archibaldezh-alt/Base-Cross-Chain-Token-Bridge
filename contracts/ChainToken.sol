// base-crosschain-token-bridge/contracts/ChainToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ChainToken is ERC20 {
    constructor() ERC20("Chain Token", "CHAIN") {
        _mint(msg.sender, 10000000 * 10**18); // 10 million tokens
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
    
    function getChainInfo() external view returns (uint256 totalSupply, uint256 ownerBalance) {
        return (totalSupply(), balanceOf(owner()));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


  - validator threshold signatures
  - nonce replay protection
  - pausability by owner 
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BaseTokenBridge is Ownable, Pausable, ReentrancyGuard { 
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    IERC20 public immutable token;
    uint256 public immutable thisChainId;

    mapping(address => bool) public isValidator;
    uint256 public validatorCount;
    uint256 public threshold;

    mapping(uint256 => bool) public usedNonce;

    event Locked(address indexed from, address indexed to, uint256 amount, uint256 toChainId, uint256 nonce);
    event Released(address indexed to, uint256 amount, uint256 fromChainId, uint256 nonce);

    constructor(address _token, uint256 _thisChainId, address[] memory validators, uint256 _threshold)
        Ownable(msg.sender)
    {
        require(_token != address(0), "token=0");
        require(validators.length > 0, "no validators");
        require(_threshold > 0 && _threshold <= validators.length, "bad threshold");

        token = IERC20(_token);
        thisChainId = _thisChainId;
        threshold = _threshold;

        for (uint256 i = 0; i < validators.length; i++) {
            address v = validators[i];
            require(v != address(0), "validator=0");
            require(!isValidator[v], "dup");
            isValidator[v] = true;
            validatorCount++;
        }
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function lock(uint256 amount, uint256 toChainId, address to, uint256 nonce) external whenNotPaused nonReentrant {
        require(amount > 0, "amount=0");
        require(to != address(0), "to=0");
        require(toChainId != thisChainId, "same chain");
        require(!usedNonce[nonce], "nonce used");
        usedNonce[nonce] = true;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, to, amount, toChainId, nonce);
    }

    function release(
        address to,
        uint256 amount,
        uint256 fromChainId,
        uint256 nonce,
        bytes[] calldata signatures
    ) external whenNotPaused nonReentrant {
        require(to != address(0), "to=0");
        require(amount > 0, "amount=0");
        require(fromChainId != thisChainId, "bad from");
        require(!usedNonce[nonce], "nonce used");
        require(signatures.length >= threshold, "not enough sigs");

        bytes32 msgHash = keccak256(abi.encodePacked("RELEASE", to, amount, fromChainId, thisChainId, nonce))
            .toEthSignedMessageHash();

        _verifyThreshold(msgHash, signatures);

        usedNonce[nonce] = true;
        token.safeTransfer(to, amount);
        emit Released(to, amount, fromChainId, nonce);
    }

    function _verifyThreshold(bytes32 msgHash, bytes[] calldata signatures) internal view {
        address[] memory seen = new address[](signatures.length);
        uint256 valid;

        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = msgHash.recover(signatures[i]);
            if (!isValidator[signer]) continue;

            bool dup;
            for (uint256 j = 0; j < valid; j++) if (seen[j] == signer) { dup = true; break; }
            if (dup) continue;

            seen[valid] = signer;
            valid++;
            if (valid >= threshold) return;
        }

        revert("threshold not met");
    }
}

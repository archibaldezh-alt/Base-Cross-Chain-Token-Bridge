// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract CrossChainTokenBridge is Ownable, Pausable {
    using SafeERC20 for IERC20;
 
    IERC20 public token;
    uint256 public thisChainId;

    mapping(address => bool) public isValidator;
    uint256 public validatorCount;
    uint256 public threshold;

    mapping(bytes32 => bool) public usedMessages;

    event Locked(address indexed user, uint256 amount, uint256 indexed toChainId, uint256 nonce);
    event Released(address indexed to, uint256 amount, uint256 indexed fromChainId, uint256 nonce);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event ThresholdUpdated(uint256 newThreshold);
    event ForeignTokenRescued(address indexed token, address indexed to, uint256 amount);

    constructor(
        address _token,
        uint256 _thisChainId,
        address[] memory validators,
        uint256 _threshold
    ) Ownable(msg.sender) {
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
            emit ValidatorAdded(v);
        }
    }

    function lock(uint256 amount, uint256 toChainId, uint256 nonce) external whenNotPaused {
        require(amount > 0, "amount=0");
        require(toChainId != thisChainId, "same chain");

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, toChainId, nonce);
    }

    function release(
        address to,
        uint256 amount,
        uint256 fromChainId,
        uint256 nonce
    ) external whenNotPaused {
        require(isValidator[msg.sender], "not validator");
        require(to != address(0), "to=0");
        require(fromChainId != thisChainId, "bad chain");

        bytes32 messageId = keccak256(abi.encodePacked(fromChainId, nonce));
        require(!usedMessages[messageId], "already processed");

        usedMessages[messageId] = true;
        token.safeTransfer(to, amount);

        emit Released(to, amount, fromChainId, nonce);
    }

    function addValidator(address v) external onlyOwner {
        require(v != address(0), "validator=0");
        require(!isValidator[v], "exists");

        isValidator[v] = true;
        validatorCount++;
        emit ValidatorAdded(v);
    }

    function removeValidator(address v) external onlyOwner {
        require(isValidator[v], "not validator");
        require(validatorCount > 1, "last validator");

        isValidator[v] = false;
        validatorCount--;

        if (threshold > validatorCount) {
            threshold = validatorCount;
            emit ThresholdUpdated(threshold);
        }

        emit ValidatorRemoved(v);
    }

    function setThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= validatorCount, "bad threshold");
        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    function rescueForeignToken(address foreignToken, address to, uint256 amount) external onlyOwner {
        require(foreignToken != address(token), "bridge token blocked");
        require(to != address(0), "to=0");

        IERC20(foreignToken).safeTransfer(to, amount);
        emit ForeignTokenRescued(foreignToken, to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

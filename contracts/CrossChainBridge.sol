// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CrossChainTokenBridge is Ownable {
    mapping(address => bool) public isValidator;
    uint256 public validatorCount;
    uint256 public threshold;

    event ValidatorAdded(address validator, uint256 validatorCount);
    event ValidatorRemoved(address validator, uint256 validatorCount);
    event ThresholdUpdated(uint256 threshold);

    constructor(address[] memory validators, uint256 _threshold) Ownable(msg.sender) {
        require(validators.length > 0, "no validators");
        for (uint256 i = 0; i < validators.length; i++) {
            _addValidator(validators[i]);
        }
        require(_threshold > 0 && _threshold <= validatorCount, "bad threshold");
        threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }

    function setThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0 && _threshold <= validatorCount, "bad threshold");
        threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }

    function addValidator(address v) external onlyOwner {
        _addValidator(v);
    }

    function removeValidator(address v) external onlyOwner {
        require(isValidator[v], "not validator");
        require(validatorCount > 1, "last validator");
        isValidator[v] = false;
        validatorCount -= 1;

        if (threshold > validatorCount) {
            threshold = validatorCount;
            emit ThresholdUpdated(threshold);
        }

        emit ValidatorRemoved(v, validatorCount);
    }

    function _addValidator(address v) internal {
        require(v != address(0), "v=0");
        require(!isValidator[v], "dup");
        isValidator[v] = true;
        validatorCount += 1;
        emit ValidatorAdded(v, validatorCount);
    }

    // Основная bridge-логика у тебя уже есть, оставь как сейчас.
}

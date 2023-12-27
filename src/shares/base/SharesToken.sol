// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ERC20VotesUpgradeable} from "./ERC20VotesUpgradeable.sol";
import {Ownable1Or2StepUpgradeable} from "src/utils/Ownable1Or2StepUpgradeable.sol";
import {ISharesToken} from "../interfaces/ISharesToken.sol";
import {IERC20Snapshots} from "../interfaces/IERC20Snapshots.sol";
import {ISharesManager} from "src/sharesManager/interfaces/ISharesManager.sol";

abstract contract SharesToken is Ownable1Or2StepUpgradeable, ERC20VotesUpgradeable, ISharesToken {

    /// @custom:storage-location erc7201:SharesToken.Storage
    struct SharesTokenStorage {
        uint256 _maxSupply;
        ISharesManager _sharesManager;
    }

    // keccak256(abi.encode(uint256(keccak256("SharesToken.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant SHARES_TOKEN_STORAGE = 0x2bfe2ff30f11b7563932d40077aad82efd0d579cb39b513d651b54e229f07300;

    function _getSharesTokenStorage() private pure returns (SharesTokenStorage storage $) {
        assembly {
            $.slot := SHARES_TOKEN_STORAGE
        }
    }

    modifier onlyOwnerOrSharesManager() {
        _checkOwnerOrSharesManager();
        _;
    }

    function _checkOwnerOrSharesManager() {
        if (msg.sender != address(_getSharesTokenStorage()._sharesManager) && msg.sender != owner()) {
            revert UnauthorizedForSharesTokenOperation();
        }
    }

    function __SharesToken_init_unchained(bytes memory sharesTokenInitParams) internal virtual onlyInitializing {
        (
            address sharesManager_
        ) = abi.decode(sharesTokenInitParams, (address));

        _setSharesManager(sharesManager_);
    }

    /// @inheritdoc IERC20Snapshots
    function createSnapshot() external virtual override onlyOwner returns (uint256 newSnapshotId) {
        newSnapshotId = _createSnapshot();
    }

    /// @inheritdoc ISharesToken
    function sharesManager() public view virtual override returns (ISharesManager _sharesManager) {
        _sharesManager = _getSharesTokenStorage()._sharesManager;
    }

    /// @inheritdoc ISharesToken
    function setSharesManager(address newSharesManager) external virtual override onlyOwner {
        _setSharesManager(newSharesManager);
    }

    function _setSharesManager(address newSharesManager) internal virtual {
        SharesTokenStorage storage $ = _getSharesTokenStorage();
        emit SharesManagerUpdate(address($._sharesManager), newSharesManager);
        $._sharesManager = ISharesManager(newSharesManager);
    }

    /// @inheritdoc ISharesToken
    function mint(address account, uint256 amount) external virtual override onlyOwnerOrSharesManager {
        _mint(account, amount);
    }

    /// @inheritdoc ISharesToken
    function maxSupply()
        public
        view
        virtual
        override(ERC20SnapshotsUpgradeable, ISharesToken)
        returns (uint256 _maxSupply)
    {
        _maxSupply = _getSharesManagerStorage()._maxSupply;
    }

    /// @inheritdoc ISharesToken
    function setMaxSupply(uint256 newMaxSupply) external virtual onlyOwner {
        _setMaxSupply(newMaxSupply);
    }

    /**
     * @dev Internal function to update the max supply. We DO allow the max supply to be set below the current
     * totalSupply(), because this would allow a DAO to keep funding active but continue to reject deposits ABOVE the
     * max supply threshold of tokens minted.
     */
    function _setMaxSupply(uint256 newMaxSupply) internal virtual {
        // Max supply is limited by ERC20Snapshots
        uint256 maxSupplyLimit = super.maxSupply();
        if (newMaxSupply > maxSupplyLimit) {
            revert MaxSupplyTooLarge(maxSupplyLimit);
        }

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit MaxSupplyChange($._maxSupply, newMaxSupply);
        $._maxSupply = newMaxSupply;
    }
}
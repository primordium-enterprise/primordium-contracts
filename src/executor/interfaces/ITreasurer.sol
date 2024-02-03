// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "./ITreasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {IDistributionCreator} from "./IDistributionCreator.sol";

interface ITreasurer is ITreasury {
    struct TreasurerInit {
        address token;
        address sharesOnboarder;
        address balanceSharesManager;
        bytes[] balanceSharesManagerCalldatas;
        address distributor;
        uint256 distributionClaimPeriod;
    }

    event SharesOnboarderUpdate(address oldSharesOnboarder, address newSharesOnboarder);
    event BalanceSharesManagerUpdate(address oldBalanceSharesManager, address newBalanceSharesManager);
    event BalanceSharesInitialized(address balanceSharesManager, uint256 totalDeposits, uint256 depositsAllocated);
    event BalanceShareAllocated(
        address indexed balanceSharesManager, uint256 indexed balanceShareId, IERC20 asset, uint256 amountAllocated
    );

    error DistributorInvalidTokenAddress(address executorToken, address distributorToken);
    error DistributorInvalidOwner(address expectedOwner, address currentOwner);
    error BalanceSharesInitializationCallFailed(uint256 index, bytes data);
    error OnlyToken();
    error OnlySharesOnboarder();
    error DepositSharesAlreadyInitialized();
    error ETHTransferFailed();
    error FailedToTransferBaseAsset(address to, uint256 amount);
    error InsufficientBaseAssetFunds(uint256 balanceTransferAmount, uint256 currentBalance);
    error InvalidBaseAssetOperation(address target, uint256 value, bytes data);
    error InvalidDepositAmount();

    /**
     * @notice Returns the address of the ERC20 token used for vote shares.
     */
    function token() external view returns (address _token);

    /**
     * @notice Returns the address of the shares onboarder contract, which is responsible for managing deposits for vot
     * shares.
     */
    function sharesOnboarder() external view returns (ISharesOnboarder _sharesOnboarder);

    /**
     * @notice Sets the address of the shares onboarder contract.
     * @dev Only callable by the executor itself.
     */
    function setSharesOnboarder(address newSharesOnboarder) external;

    /**
     * @notice Returns the address of the contract used for distributions.
     */
    function distributor() external view returns (IDistributionCreator _distributor);

    /**
     * @notice Creates a distribution on the distributor contract for the given amount.
     * @dev If there are existing balance share accounts for distributions, the BPS share will be subtracted from the
     * amount and allocated to the balance shares manager contract before initializing the distribution.
     */
    function createDistribution(IERC20 asset, uint256 amount) external;

    /**
     * @dev A public accessor function that reverts if the provided address does not support the ERC165 interfaceId
     * of the {IDistributionCreator}
     */
    function authorizeDistributorImplementation(address newImplementation) external view;

    /**
     * @notice Returns the address of the contract used for balance shares management, or address(0) if no balance
     * shares are currently being used.
     */
    function balanceSharesManager() external view returns (address _balanceSharesManager);

    /**
     * Sets the address for the balance shares manager contract.
     * @dev Only callable by the executor itself.
     * @param newBalanceSharesManager The address of the new balance shares manager contract, which must implement the
     * {IBalanceShareAllocations} interface.
     */
    function setBalanceSharesManager(address newBalanceSharesManager) external;

    /**
     * @notice Returns true if balance shares are enabled for this contract.
     */
    function balanceSharesEnabled() external view returns (bool isBalanceSharesEnabled);

    /**
     * @notice Enables the accounting for balance shares. Once enabled, it cannot be disabled except by setting the
     * balance shares manager address to address(0).
     * @dev This function is only callable by the executor itself, or by an enabled module during that module's
     * execution of an executor operation.
     * @param applyDepositSharesRetroactively If set to true, this will retroactively apply deposit share accounting to
     * the total amount of deposits registered so far.
     */
    function enableBalanceShares(bool applyDepositSharesRetroactively) external;
}

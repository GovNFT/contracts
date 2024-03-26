// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IGovNFT is IERC721Enumerable, IERC4906 {
    /// @dev Lock Information of an NFT:
    ///      `totalLocked` Total amount being vested in NFT
    ///      `initialDeposit` Amount initially locked, prior to splits
    ///      `totalClaimed` Total amount claimed from Lock
    ///      `unclaimedBeforeSplit` Amount left unclaimed before split
    ///      `splitCount` Number of splits performed on NFT
    ///      `cliffLength` Duration of Locks' cliff period
    ///      `start` Vesting period start
    ///      `end` Vesting period end
    ///      `token` Address of the token being vested
    ///      `vault` Address of the vault storing tokens
    ///      `minter` Address of the minter of the NFT
    struct Lock {
        uint256 totalLocked;
        uint256 initialDeposit;
        uint256 totalClaimed;
        uint256 unclaimedBeforeSplit;
        address token;
        uint40 splitCount;
        uint40 cliffLength;
        uint40 start;
        uint40 end;
        address vault;
        address minter;
    }

    /// @dev Parameters necessary to perform a Split:
    ///      `beneficiary` Address of the user to receive tokens vested from split
    ///      `start` Time at which token distribution starts
    ///      `end` Time at which everything should be vested
    ///      `cliff` Duration after which the first portion vests
    ///      `amount` Amount of tokens to be vested in the new Lock
    ///      `description` Description of the new lock
    struct SplitParams {
        address beneficiary;
        uint40 start;
        uint40 end;
        uint40 cliff;
        uint256 amount;
        string description;
    }

    /// Events
    event Create(
        uint256 indexed tokenId,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        string description
    );
    event Sweep(uint256 indexed tokenId, address indexed token, address indexed recipient, uint256 amount);
    event Claim(uint256 indexed tokenId, address indexed recipient, uint256 claimed);
    event Delegate(uint256 indexed tokenId, address indexed delegate);
    event Split(
        uint256 indexed from,
        uint256 indexed to,
        address indexed recipient,
        uint256 splitAmount1,
        uint256 splitAmount2,
        uint40 startTime,
        uint40 endTime,
        string description
    );

    /// Errors
    error InsufficientAmount();
    error InvalidParameters();
    error TokenNotFound();
    error InvalidStart();
    error InvalidCliff();
    error InvalidSweep();
    error AmountTooBig();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidEnd();

    /// @notice Current count of minted NFTs
    /// @return The number of minted NFTs
    function tokenId() external view returns (uint256);

    /// @notice Address of art proxy used for on-chain art generation
    function artProxy() external view returns (address);

    /// @notice Address of the factory that deployed this contract
    function factory() external view returns (address);

    /// @notice Returns the Lock information for a given token ID
    /// @param _tokenId Token Id from which the info will be fetched
    /// @return Lock Information for the given token ID
    function locks(uint256 _tokenId) external view returns (Lock memory);

    /// @notice Views if Airdrops in the Lock token can be Swept prior to Lock expiry
    function earlySweepLockToken() external view returns (bool);

    /// @notice Get the number of unclaimed, vested tokens for a given token ID
    /// @param _tokenId Lock Token Id to be used
    /// @return The amount of claimable tokens for the given token ID
    function unclaimed(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the number of vested tokens for a given token ID
    /// @param _tokenId Lock Token Id to be used
    /// @return The amount of vested tokens for the given token ID
    function totalVested(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the number of locked tokens for a given token ID
    /// @param _tokenId Lock Token Id to be used
    /// @return The amount of locked tokens of a token ID
    function locked(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the Split NFT ID from the Split Lock list of `_tokenId` at the given `_index`
    /// @param _tokenId Lock Token Id from which to fetch the Split list
    /// @param _index Index in Split Lock list to be accessed
    /// @return The ID of the Split NFT at the given index
    function splitTokensByIndex(uint256 _tokenId, uint256 _index) external view returns (uint256);

    /// @notice Create a new Lock given their start and end timestamps
    /// @param _token Address of the ERC20 token being distributed
    /// @param _recipient Address to vest tokens for
    /// @param _amount Amount of tokens being vested for `recipient`
    /// @param _startTime Time at which token distribution starts
    /// @param _endTime Time at which everything should be vested
    /// @param _cliffLength Duration after which the first portion vests
    /// @param _description Description of the lock
    /// @return The token ID of the created Lock
    function createLock(
        address _token,
        address _recipient,
        uint256 _amount,
        uint40 _startTime,
        uint40 _endTime,
        uint40 _cliffLength,
        string memory _description
    ) external returns (uint256);

    /// @notice Claim tokens which have vested in the amount specified
    /// @dev    Callable by the locks's recipient or its approved operators
    /// @param _tokenId Lock Token Id from where tokens should be claimed
    /// @param _beneficiary Address to transfer claimed tokens to
    /// @param _amount Amount of tokens to claim
    function claim(uint256 _tokenId, address _beneficiary, uint256 _amount) external;

    ///  @notice Delegates voting power of a given Lock to `delegatee`
    ///  @param _tokenId Lock Token Id to be used
    ///  @param _delegatee Address to delegate voting power to
    function delegate(uint256 _tokenId, address _delegatee) external;

    /// @notice Withdraw all `token`s from the Lock. Can be used to sweep airdropped tokens
    /// @dev    Can only Sweep Lock prior to Lock expiry if `earlySweepLockToken`
    /// @param _tokenId Lock Token Id to be used
    /// @param _token Address of the `token` to sweep
    /// @param _recipient Address to receive the tokens
    function sweep(uint256 _tokenId, address _token, address _recipient) external;

    /// @notice Withdraw `amount` of `token` from the Lock. Can be used to sweep airdropped tokens
    /// @dev    Can only Sweep Lock prior to Lock expiry if `earlySweepLockToken`
    /// @param _tokenId Lock Token Id to be used
    /// @param _token Address of the `token` to sweep
    /// @param _recipient Address to receive the tokens
    /// @param _amount Amount of tokens to sweep
    function sweep(uint256 _tokenId, address _token, address _recipient, uint256 _amount) external;
}

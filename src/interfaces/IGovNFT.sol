// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IGovNFT is IERC721Enumerable {
    struct Lock {
        uint256 totalLocked;
        uint256 initialDeposit;
        uint256 totalClaimed;
        uint256 unclaimedBeforeSplit;
        uint256 splitCount;
        uint256 cliffLength;
        uint256 start;
        uint256 end;
        address token;
        address vault;
        address minter;
    }

    /// Events
    event Create(uint256 indexed tokenId, address indexed recipient, address indexed token, uint256 amount);
    event Sweep(uint256 indexed tokenId, address indexed token, address indexed receiver, uint256 amount);
    event Claim(uint256 indexed tokenId, address indexed recipient, uint256 claimed);
    event Delegate(uint256 indexed tokenId, address indexed delegate);
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId,
        address _recipient,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _startTime,
        uint256 _endTime
    );

    /// Errors
    error EndBeforeOrEqualStart();
    error InsufficientAmount();
    error VestingStartTooOld();
    error SplitOutOfBounds();
    error InvalidCliff();
    error AmountTooBig();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidEnd();

    /// @notice Current count of minted NFTs
    /// @return The number of minted NFTs
    function tokenId() external view returns (uint256);

    /// @notice Get the number of unclaimed, vested tokens for a given token ID
    /// @param _tokenId Lock Token Id to be used
    /// @return The amount of claimable tokens for the given token ID
    function unclaimed(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the number of locked tokens for a given token ID
    /// @param _tokenId Lock Token Id to be used
    /// @return The amount of locked tokens of a token ID
    function locked(uint256 _tokenId) external view returns (uint256);

    /// @notice Returns the Lock information for a given token ID
    /// @param _tokenId Token Id from which the info will be fetched
    /// @return totalLocked Total amount being vested in NFT
    /// @return initialDeposit Amount initially locked, prior to splits
    /// @return totalClaimed Total amount claimed from Lock
    /// @return unclaimedBeforeSplit Amount left unclaimed before split
    /// @return splitCount Number of splits performed on NFT
    /// @return cliffLength Duration of Locks' cliff period
    /// @return start Vesting period start
    /// @return end Vesting period end
    /// @return token Address of the token being vested
    /// @return vault Address of the vault storing tokens
    /// @return minter Address of the minter of the NFT
    function locks(
        uint256 _tokenId
    )
        external
        view
        returns (
            uint256 totalLocked,
            uint256 initialDeposit,
            uint256 totalClaimed,
            uint256 unclaimedBeforeSplit,
            uint256 splitCount,
            uint256 cliffLength,
            uint256 start,
            uint256 end,
            address token,
            address vault,
            address minter
        );

    /// @notice Create a new Lock given their start and end timestamps
    /// @param _token Address of the ERC20 token being distributed
    /// @param _recipient Address to vest tokens for
    /// @param _amount Amount of tokens being vested for `recipient`
    /// @param _startTime Epoch time at which token distribution starts
    /// @param _endTime Time at which everything should be vested
    /// @param _cliffLength Duration after which the first portion vests
    /// @return The token ID of the created Lock
    function createLock(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cliffLength
    ) external returns (uint256);

    /// @notice Claim tokens which have vested in the amount specified
    /// @dev    Callable by the locks's recipient or its approved operators
    /// @param _tokenId Lock Token Id from where tokens should be claimed
    /// @param _beneficiary Address to transfer claimed tokens to
    /// @param _amount Amount of tokens to claim
    function claim(uint256 _tokenId, address _beneficiary, uint256 _amount) external;

    /// @notice Splitting creates a new NFT from a given Parent NFT
    /// - The Parent NFT will have `locked(from) - _amount` tokens to be vested
    /// - And the Split NFT will vest `_amount` tokens
    /// - The second NFT will also use the new recipient, cliff and start and end timestamps
    /// @dev     Callable by owner and approved operators
    ///          Unclaimed tokens vested on the old `_from` NFT are still claimable after split
    ///          `_start` cannot be lower than old start or block.timestamp
    ///          `_end` cannot be lower than the old end
    ///          `_cliff` has to end at the same time or after the old cliff
    /// @param _beneficiary Address of the user to receive tokens vested from split
    /// @param _from Lock Token Id that will be split
    /// @param _amount Amount of tokens to be vested in the new Lock
    /// @param _start Epoch time at which token distribution starts
    /// @param _end Time at which everything should be vested
    /// @param _cliff Duration after which the first portion vests
    /// @return _tokenId Return tokenId of new Split Lock with `_amount`.
    function split(
        address _beneficiary,
        uint256 _from,
        uint256 _amount,
        uint256 _start,
        uint256 _end,
        uint256 _cliff
    ) external returns (uint256 _tokenId);

    ///  @notice Delegates voting power of a given Lock to `delegatee`
    ///  @param _tokenId Lock Token Id to be used
    ///  @param delegatee Address to delegate voting power to
    function delegate(uint256 _tokenId, address delegatee) external;

    /// @notice Withdraw all `token`s from the Lock. Can be used to sweep airdropped tokens
    /// @param _tokenId Lock Token Id to be used
    /// @param token Address of the `token` to sweep
    /// @param recipient Address to receive the tokens
    function sweep(uint256 _tokenId, address token, address recipient) external;

    /// @notice Withdraw `amount` of `token` from the Lock. Can be used to sweep airdropped tokens
    /// @param _tokenId Lock Token Id to be used
    /// @param token Address of the `token` to sweep
    /// @param recipient Address to receive the tokens
    /// @param amount Amount of tokens to sweep
    function sweep(uint256 _tokenId, address token, address recipient, uint256 amount) external;
}

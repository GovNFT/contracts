// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface IVestingEscrow {
    struct LockedGrant {
        uint256 totalLocked;
        uint256 cliffLength;
        uint256 start;
        uint256 end;
    }

    /** Events **/
    event Fund(uint256 indexed tokenId, address indexed recipient, address indexed token, uint256 amount);
    event Claim(uint256 indexed tokenId, address indexed recipient, uint256 claimed);
    event RugPull(uint256 indexed tokenId, address recipient, uint256 rugged);
    event AcceptAdmin(uint256 indexed tokenId, address admin);
    event SetAdmin(uint256 indexed tokenId, address admin);

    /** Errors **/
    error VestingStartTooOld();
    error TokenNotDisabled();
    error EndBeforeOrEqual();
    error NotPendingAdmin();
    error AlreadyDisabled();
    error NotFutureAdmin();
    error InvalidCliff();
    error ZeroDuration();
    error ZeroAddress();
    error ZeroAmount();
    error NotAdmin();

    /// @notice Get the number of unclaimed, vested tokens for a given TokenId
    /// @param _tokenId Grant Token Id to be used
    /// NOTE: if `rugPull` is activated, limit by the activation timestamp
    function unclaimed(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the number of locked tokens for a given TokenId
    /// @param _tokenId Grant Token Id to be used
    /// NOTE: if `rugPull` is activated, limit by the activation timestamp
    function locked(uint256 _tokenId) external view returns (uint256);

    /// @notice Create a new Vesting NFT given its duration
    /// @dev    By default the vesting starts in the Current Timestamp
    /// @param _token Address of the ERC20 token being distributed
    /// @param _recipient Address to vest tokens for
    /// @param _amount Amount of tokens being vested for `recipient`
    /// @param _duration Duration of the vesting period
    /// @param _cliffLength Duration after which the first portion vests
    function createGrant(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _duration,
        uint256 _cliffLength
    ) external returns (uint256);

    /// @notice Create a new Vesting NFT given their start and end timestamps
    /// @param _token Address of the ERC20 token being distributed
    /// @param _recipient Address to vest tokens for
    /// @param _amount Amount of tokens being vested for `recipient`
    /// @param _startTime Epoch time at which token distribution starts
    /// @param _endTime Time until everything should be vested
    /// @param _cliffLength Duration after which the first portion vests
    function createGrant(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cliffLength
    ) external returns (uint256);

    /// @notice Claim all available tokens that have been vested
    /// @dev    Callable by the grant's recipient or its approved operators
    /// @param _tokenId Grant Token Id from where tokens should be claimed
    /// @param beneficiary Address to transfer claimed tokens to
    function claim(uint256 _tokenId, address beneficiary) external;

    /// @notice Claim tokens which have vested in the amount specified
    /// @dev    Callable by the grant's recipient or its approved operators
    /// @param _tokenId Grant Token Id from where tokens should be claimed
    /// @param beneficiary Address to transfer claimed tokens to
    /// @param amount Amount of tokens to claim
    function claim(uint256 _tokenId, address beneficiary, uint256 amount) external;

    /// @notice Transfer Admin priviledge of the Grant to `addr`
    /// @dev    Can only be called by the current Admin
    /// @param _tokenId Grant Token Id to have the Admin set
    /// @param addr Address to have ownership transferred to
    function setAdmin(uint256 _tokenId, address addr) external;

    /// @notice Apply pending Admin transfer to the given Grant
    /// @dev    Can only be called by the pending Admin
    /// @param _tokenId Grant Token Id to have the Admin set
    function acceptAdmin(uint256 _tokenId) external;

    /// @notice Renounce admin control of the escrow
    /// @dev    Renouncing admin control would leave the Grant without an admin,
    ///         thereby removing any functionality only available to that role
    /// @param _tokenId Grant Token Id to be used
    function renounceAdmin(uint256 _tokenId) external;

    /// @notice Disable further flow of tokens from a given Grant and clawback the unvested part to admin
    /// @param _tokenId Grant Token Id to be rug pulled
    function rugPull(uint256 _tokenId) external;
}

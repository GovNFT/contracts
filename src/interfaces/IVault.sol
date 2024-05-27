// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

interface IVault {
    error ZeroAddress();
    error NotOwner(address account);

    /// @notice Address of the token being vested
    /// @return The Token contract address
    function token() external view returns (address);

    /// @notice Address of the Vault's Owner
    /// @return The Owner address
    function owner() external view returns (address);

    /// @notice Withdraw `_amount` of `token` from the Vault
    /// @param _recipient Address to receive the tokens
    /// @param _amount Amount of tokens to withdraw
    /// @dev Only callable by the Lock recipient through the GovNFT contract
    function withdraw(address _recipient, uint256 _amount) external;

    /// @notice Delegates voting power of a given Lock to `_delegatee`
    /// @param _delegatee Address to delegate voting power to
    /// @dev Only callable by the Lock recipient through the GovNFT contract
    function delegate(address _delegatee) external;

    /// @notice Sweep `_amount` of `_token` from the Vault to `_recipient`
    /// @param _token Address of the `token` to sweep
    /// @param _recipient Address to receive the tokens
    /// @param _amount Amount of tokens to sweep
    /// @dev Only callable by the Lock recipient through the GovNFT contract
    function sweep(address _token, address _recipient, uint256 _amount) external;

    /// @notice Called on Vault creation by GovNFT
    /// @param _token Address if the token to be vested
    function initialize(address _token) external;

    /// @notice Transfers Ownership of the Vault to a new Owner
    /// @param _newOwner New Owner to be set
    function setOwner(address _newOwner) external;

    /// @notice Executes a transaction on behalf of the Vault
    /// @param _to Address of the contract to call
    /// @param _data Data to be sent to use in the call
    function execute(address _to, bytes calldata _data) external;
}

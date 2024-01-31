// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

interface IVault {
    /// @notice Address of the token being vested
    /// @return The Token contract address
    function token() external view returns (address);

    /// @notice Withdraw `_amount` of `token` from the Vault
    /// @param _receiver Address to receive the tokens
    /// @param _amount Amount of tokens to withdraw
    /// @dev Only callable by the Lock recipient through the GovNFT contract
    function withdraw(address _receiver, uint256 _amount) external;

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
}

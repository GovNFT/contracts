// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface IVault {
    // @notice Withdraw `amount` of `token` from the Vault
    // @param receiver Address to receive the tokens
    // @param amount Amount of tokens to withdraw
    // @dev Only callable by the Lock recipient through the GovNFT contract
    function withdraw(address receiver, uint256 amount) external;

    // @notice Delegates voting power of a given Lock to `delegatee`
    // @param delegatee Address to delegate voting power to
    // @dev Only callable by the Lock recipient through the GovNFT contract
    function delegate(address delegatee) external;

    // @notice Sweep `amount` of `token` from the Vault to `recipient`
    // @param token Address of the `token` to sweep
    // @param recipient Address to receive the tokens
    // @param amount Amount of tokens to sweep
    // @dev Only callable by the Lock recipient through the GovNFT contract
    function sweep(address _token, address recipient, uint256 amount) external;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface IVault {
    // @notice Withdraw `amount` of `token` from the Vault
    // @param receiver Address to receive the tokens
    // @param amount Amount of tokens to withdraw
    function withdraw(address receiver, uint256 amount) external;

    // @notice Delegates voting power of a given Grant to `delegatee`
    // @param delegatee Address to delegate voting power to
    function delegate(address delegatee) external;
}

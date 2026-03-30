// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MyToken} from "../../MyToken.sol";

/// @notice Library for generating permit digests for testing purposes.
/// @author @ohMySol
library PermitHash {
    /// @notice The typehash for the permit function.
    bytes32 constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    /// @notice Generates a permit digest for a given token, owner, spender, value, and deadline.
    /// @param token The token to generate the digest for.
    /// @param tokenOwner The owner of the token.
    /// @param spender The spender of the token.
    /// @param value The value of the token.
    /// @param deadline The deadline of the permit.
    /// @return The digest of the permit.
    function getPermitDigest(
        MyToken token,
        address tokenOwner,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (bytes32) {
        uint256 nonce = token.nonces(tokenOwner);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, tokenOwner, spender, value, nonce, deadline)
        );
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
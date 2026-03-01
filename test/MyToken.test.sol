// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MyToken} from "../src/MyToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract MyTokenTest is Test {
   bytes32 constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    MyToken public myToken;
    address owner;
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    uint256 internal permitOwnerKey = 1;


    function setUp() public {
        owner = vm.addr(permitOwnerKey);
        
        vm.startPrank(owner);
        myToken = new MyToken();
        myToken.mint(owner, 1000 ether);
        vm.stopPrank();
    }

    /* CONSTRUCTOR TESTS*/

    function test_constructor_intiializes_correctly() public {
        assertEq(myToken.owner(), owner);
        assertEq(myToken.name(), "MyToken");
        assertEq(myToken.symbol(), "MTK");
    }

    /* MINT TESTS */

    function test_mint_should_mint_tokens_to_address() public {
        uint256 amount = 100 ether;

        vm.prank(owner);
        myToken.mint(user, amount);

        assertEq(myToken.balanceOf(user), amount);
    }

    function test_mint_should_revert_when_called_by_non_owner() public {
        uint256 amount = 100 ether;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        myToken.mint(user, amount);
    }

    /* PERMIT TESTS */

    function _getPermitDigest(
        address tokenOwner,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (bytes32) {
        uint256 nonce = myToken.nonces(tokenOwner);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, tokenOwner, spender, value, nonce, deadline)
        );
        bytes32 domainSeparator = myToken.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function test_permit_should_permit_spender_to_spend_tokens() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _getPermitDigest(owner, user, amount, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerKey, digest);

        // Anyone can submit the permit | we call it as user (the spender).
        vm.prank(user);
        myToken.permit(owner, user, amount, deadline, v, r, s);

        assertEq(myToken.allowance(owner, user), amount);
    }

    function test_permit_should_allow_spender_to_transferFrom_after_permit() public {
        uint256 amount = 50 ether;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _getPermitDigest(owner, user, amount, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerKey, digest);

        vm.startPrank(user);
        myToken.permit(owner, user, amount, deadline, v, r, s);
        myToken.transferFrom(owner, user, amount);
        vm.stopPrank();

        assertEq(myToken.balanceOf(owner), 1000 ether - amount);
        assertEq(myToken.balanceOf(user), amount);
    }

    function test_permit_should_revert_when_deadline_expired() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp - 1; // already expired

        bytes32 digest = _getPermitDigest(owner, user, amount, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerKey, digest);

        vm.expectRevert(abi.encodeWithSelector(ERC2612ExpiredSignature.selector, deadline));
        vm.prank(user);
        myToken.permit(owner, user, amount, deadline, v, r, s);
    }

    function test_permit_should_revert_when_signer_is_not_owner() public {
        // We sign a permit for (owner, user) but then call permit(user2, user, ...) to test the revert.
        // The contract hashes (user2, user, ...), so it recovers from a different digest.
        // The recovered address will not be user2, so it reverts ERC2612InvalidSigner(recovered, user2).
        uint256 amount = 50 ether;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digestSigned = _getPermitDigest(owner, user, amount, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerKey, digestSigned);

        // Contract will use this digest (for user2 as owner), so recovery gives the "wrong" signer.
        bytes32 digestUsedByContract = _getPermitDigest(user2, user, amount, deadline);
        address recoveredSigner = ecrecover(digestUsedByContract, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(ERC2612InvalidSigner.selector, recoveredSigner, user2));
        vm.prank(user);
        myToken.permit(user2, user, amount, deadline, v, r, s);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MyToken} from "../src/MyToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract MyTokenTest is Test {
    MyToken public myToken;
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        myToken = new MyToken();
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

        vm.startPrank(owner);
        myToken.mint(user, amount);
        vm.stopPrank();

        assertEq(myToken.balanceOf(user), amount);
    }

    function test_mint_should_revert_when_called_by_non_owner() public {
        uint256 amount = 100 ether;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        myToken.mint(user, amount);
        vm.stopPrank();
    }
} 
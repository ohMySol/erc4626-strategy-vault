// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {VaultFactory} from "../src/VaultFactory.sol";
import {MyToken} from "../src/MyToken.sol";

import {IVault} from "../src/interfaces/IVault.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";

contract VaultFactoryTest is Test {
    VaultFactory public vaultFactory;
    MyToken public myToken;
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        myToken = new MyToken();
        vm.stopPrank();

        vaultFactory = new VaultFactory();
    }

    /* CREATE VAULT TESTS */
    
    function test_createVault_should_create_vault_successfully() public {
        IVault vault = vaultFactory.createVault(
            owner,            // vault owner
            address(myToken), // underlying asset
            "vToken",         // name
            "vTK",            // symbol
            1000,             // vault fee
            owner             // fee recipient
        );

        assertEq(vaultFactory.isValidVault(address(vault)), true);
    }

    function test_createVault_should_emit_VaultCreated_event() public {
        vm.expectEmit(false, true, true, true);

        emit EventsLib.VaultCreated(
            address(0),       // vault (not checked)
            owner,            
            owner,           
            address(myToken),
            "vToken",
            "vTK",
            1000,
            owner
        );

        vm.startPrank(owner);
        vaultFactory.createVault(
            owner,
            address(myToken),
            "vToken",
            "vTK",
            1000,
            owner
        );
        vm.stopPrank();
    }

    function test_vault_shouldnt_be_registered_if_creation_reverted() public {
        vm.expectRevert();
        vaultFactory.createVault(
            owner,
            address(0),
            "vToken",
            "vTK",
            1000,
            owner
        );

        assertEq(vaultFactory.isValidVault(address(0)), false);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentINFT.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract AgentINFTTest is Test {
    AgentINFT nft;
    address minter = makeAddr("minter");
    address other = makeAddr("other");

    function setUp() public {
        nft = new AgentINFT();
    }

    function test_mint_returns_sequential_ids() public {
        uint256 id0 = nft.mint(minter, "Job-0", "desc", "", bytes32(0), "");
        uint256 id1 = nft.mint(minter, "Job-1", "desc", "", bytes32(0), "");
        assertEq(id0, 0);
        assertEq(id1, 1);
    }

    function test_mint_assigns_ownership() public {
        uint256 id = nft.mint(minter, "Job", "desc", "", bytes32(0), "");
        assertEq(nft.ownerOf(id), minter);
    }

    function test_mint_emits_transfer() public {
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), minter, 0);
        nft.mint(minter, "Job", "desc", "", bytes32(0), "");
    }

    function test_mint_stores_token_data() public {
        bytes memory enc = hex"deadbeef";
        bytes32 hash = keccak256(abi.encodePacked("result"));
        uint256 id = nft.mint(minter, "MyJob", "inference result", enc, hash, "0g://abc123");

        AgentINFT.TokenData memory td = nft.getTokenData(id);
        assertEq(td.name, "MyJob");
        assertEq(td.description, "inference result");
        assertEq(td.encryptedMetadata, enc);
        assertEq(td.metadataHash, hash);
        assertEq(td.daRef, "0g://abc123");
    }

    function test_updateEncryptedMetadata_by_owner() public {
        uint256 id = nft.mint(minter, "Job", "desc", hex"aa", bytes32(0), "");

        bytes memory newEnc = hex"bbccdd";
        vm.prank(minter);
        nft.updateEncryptedMetadata(id, newEnc);

        AgentINFT.TokenData memory td = nft.getTokenData(id);
        assertEq(td.encryptedMetadata, newEnc);
        assertEq(td.metadataHash, keccak256(newEnc));
    }

    function test_updateEncryptedMetadata_emits_event() public {
        uint256 id = nft.mint(minter, "Job", "desc", hex"aa", bytes32(0), "");

        bytes memory newEnc = hex"bbccdd";
        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit AgentINFT.MetadataUpdated(id, keccak256(newEnc));
        nft.updateEncryptedMetadata(id, newEnc);
    }

    function test_updateEncryptedMetadata_reverts_non_owner() public {
        uint256 id = nft.mint(minter, "Job", "desc", hex"aa", bytes32(0), "");

        vm.prank(other);
        vm.expectRevert("not token owner");
        nft.updateEncryptedMetadata(id, hex"ff");
    }

    function test_updateEncryptedMetadata_after_transfer() public {
        uint256 id = nft.mint(minter, "Job", "desc", hex"aa", bytes32(0), "");

        // Transfer from minter to other.
        vm.prank(minter);
        nft.transferFrom(minter, other, id);
        assertEq(nft.ownerOf(id), other);

        // New owner can update metadata.
        vm.prank(other);
        nft.updateEncryptedMetadata(id, hex"ee");
        assertEq(nft.getTokenData(id).encryptedMetadata, hex"ee");

        // Old owner can no longer update.
        vm.prank(minter);
        vm.expectRevert("not token owner");
        nft.updateEncryptedMetadata(id, hex"ff");
    }

    function test_getTokenData_reverts_nonexistent() public {
        vm.expectRevert();
        nft.getTokenData(999);
    }
}

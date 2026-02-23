// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentINFT
/// @notice ERC-7857 iNFT contract for AI inference provenance on 0G Chain.
/// Stores encrypted metadata and a DA-layer storage reference per token.
/// The ABI matches the Go minter in agent-inference/internal/zerog/inft/minter.go.
contract AgentINFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    struct TokenData {
        string name;
        string description;
        bytes encryptedMetadata;
        bytes32 metadataHash;
        string daRef;
    }

    mapping(uint256 => TokenData) private _tokenData;

    event MetadataUpdated(uint256 indexed tokenId, bytes32 newHash);

    constructor() ERC721("AgentINFT", "AINFT") Ownable(msg.sender) {}

    /// @notice Mint a new iNFT with encrypted metadata.
    /// @dev Matches ABI: mint(address,string,string,bytes,bytes32,string)
    function mint(
        address to,
        string calldata name,
        string calldata description,
        bytes calldata encryptedMeta,
        bytes32 resultHash,
        string calldata storageRef
    ) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        _tokenData[tokenId] = TokenData(name, description, encryptedMeta, resultHash, storageRef);
        return tokenId;
    }

    /// @notice Update encrypted metadata for a token. Only the token owner may call.
    /// @dev Matches ABI: updateEncryptedMetadata(uint256,bytes)
    function updateEncryptedMetadata(uint256 tokenId, bytes calldata encryptedMeta) external {
        require(ownerOf(tokenId) == msg.sender, "not token owner");
        _tokenData[tokenId].encryptedMetadata = encryptedMeta;
        _tokenData[tokenId].metadataHash = keccak256(encryptedMeta);
        emit MetadataUpdated(tokenId, _tokenData[tokenId].metadataHash);
    }

    /// @notice Read the full token data for a given tokenId.
    function getTokenData(uint256 tokenId) external view returns (TokenData memory) {
        require(ownerOf(tokenId) != address(0), "token does not exist");
        return _tokenData[tokenId];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./MIP721Snapshot.sol";

contract MIP721 is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, AccessControl, ERC721Burnable, MIP721Snapshot {
    using Counters for Counters.Counter;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    Counters.Counter private _tokenIdCounter;

    string private _baseTokenURI;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) ERC721(name, symbol) {
        _baseTokenURI = baseTokenURI;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseUri) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = baseUri;
    }

    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function mint(address to, string memory uri) public onlyRole(ADMIN_ROLE) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function snapshot(uint256 _id, uint256 _hash) public override onlyRole(ADMIN_ROLE) {
        //require(ownerOf(_id) == _msgSender(), "not owner");
        MIP721Snapshot._snapshot(_id, _hash);
    }
    
    function removeSnapshot(uint256 _id) public onlyRole(ADMIN_ROLE) {
        //require(ownerOf(_id) == _msgSender(), "not owner");
        MIP721Snapshot._snapshot(_id, 0x0);
    }

    function tokensOfOwner(address owner, uint256 startIdx, uint256 endIdx) public view returns (uint256[] memory) {
        require(startIdx <= endIdx, "parameter endIdx must >= startIdx");
        uint256 tokenCount = ERC721.balanceOf(owner);
        if (tokenCount > 0 && tokenCount > startIdx) {
            if (endIdx >= tokenCount) {
                endIdx = tokenCount - 1;
            }
            uint returnCount = endIdx - startIdx + 1;
            uint256[] memory tokenList = new uint256[](returnCount);
            for (uint256 i=startIdx; i < returnCount ; i++){
                tokenList[i] = tokenOfOwnerByIndex(owner, i);
            }
            return tokenList;
        } else {
            return new uint256[](0);
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal whenNotPaused override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, AccessControl, MIP721Snapshot) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

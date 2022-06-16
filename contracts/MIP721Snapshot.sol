// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

abstract contract MIP721Snapshot {
    mapping(uint256 => uint256) private snapshortList;

    event Snapshot(address indexed _operator, uint256 indexed _id, uint256 _hash);

    function snapshot(uint256 _id, uint256 _hash) public virtual;

    function _snapshot(uint256 _id, uint256 _hash) internal virtual {
        // require(snapshortList[_id] == 0, "MIP721Snapshot: already snapshoted");
        // require(_hash != 0, "MIP721Snapshot: _hash can not have 0");

        if(_hash != 0) {
            snapshortList[_id] = _hash;
        } else {
            delete snapshortList[_id];
        }
        
        emit Snapshot(msg.sender, _id, _hash);
    }

    function snapshoted(uint256 _id) public view virtual returns (bool) {
        return (snapshortList[_id] != 0);
    }
    function snapshotOf(uint256 _id) public virtual returns (uint256) {
        return snapshortList[_id];
    }

    // /**
    //  * @dev for ERC721
    //  */
    // function _beforeTokenTransfer(
    //     address, // from,
    //     address, // to,
    //     uint256 tokenId
    // ) internal virtual {
    //     require(!snapshoted(tokenId), "MIP721Snapshot: token is locked");
    // }

    // /**
    //  * @dev for ERC1155
    //  */
    // function _beforeTokenTransfer(
    //     address, // operator,
    //     address, // from,
    //     address, // to,
    //     uint256[] memory ids,
    //     uint256[] memory, // amounts,
    //     bytes memory // data
    // ) internal virtual {
    //     for (uint256 i = 0; i < ids.length; ++i) {
    //         require(!snapshoted(ids[i]), "MIP721Snapshot: token(1155) is locked");
    //     }
    // }

    // /**
    //  * @dev See {IERC165-supportsInterface}.
    //  */
    // function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
    //     return interfaceId == type(MIP721Snapshot).interfaceId;
    // }
}

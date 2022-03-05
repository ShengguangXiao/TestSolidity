// SPDX-License-Identifier: MIT

//** NFT Airdrop Contract */
//** Author Xiao Shengguang : NFT Airdrop Contract 2022.1 */

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/ILFGNFT.sol";

contract NftAirdrop is Ownable, ReentrancyGuard, IERC721Receiver {

    struct WhitelistInfo {
        address wallet;
        uint256 nftAmount;
        uint256 distributedAmount;
        bool active;
    }

    /**
     *
     * @dev this event calls when new whitelist member joined to the pool
     *
     */
    event AddWhitelist(address wallet);

    /**
     *
     * @dev this event calls when new whitelist member is deactivated
     *
     */
    event DecafList(address wallet);

    /**
     *
     * @dev this event calls when user claim the NFT
     *
     */
    event ClaimDistribution(address wallet, uint256 amount);

    /**
     *
     * @dev this event calls when user update the NFT contract
     *
     */
    event SetLfgNft(ILFGNFT _nft);

    /**
     *
     * @dev whitelistPools store all active whitelist member details.
     *
     */
    mapping(address => WhitelistInfo) public whitelistPools;

    /**
     *
     * @dev whitelistAddresses array of all active whitelist adresses, using array so can iterate all the keys.
     *
     */
    address [] public whitelistAddresses;


    ILFGNFT public lfgNft;

    constructor(
        ILFGNFT _nft
    ) {
        lfgNft = _nft;
    }

    /**
     *
     * @dev set nft address for contract
     *
     * @param {_token} address of IERC20 instance
     * @return {bool} return status of token address
     *
     */
    function setNftToken(ILFGNFT _nft) external onlyOwner returns (bool) {
        lfgNft = _nft;
        emit SetLfgNft(_nft);
        return true;
    }

    /**
     *
     * @dev set the address as whitelist user address
     *
     * @param {address} address of the user
     *
     * @return {bool} return status of the whitelist
     *
     */
    function addWhitelists(
        address[] calldata _wallet,
        uint256[] calldata _nftAmount
    ) external onlyOwner returns (bool) {
        require(_wallet.length == _nftAmount.length, "Invalid array length");

        for (uint256 i = 0; i < _wallet.length; i++) {
            require(whitelistPools[_wallet[i]].wallet != _wallet[i], "Whitelist already available");

            whitelistPools[_wallet[i]].active = true;
            whitelistPools[_wallet[i]].wallet = _wallet[i];
            whitelistPools[_wallet[i]].nftAmount = _nftAmount[i];
            whitelistPools[_wallet[i]].distributedAmount = 0;

            whitelistAddresses.push(_wallet[i]);

            emit AddWhitelist(_wallet[i]);
        }

        return true;
    }

    /**
     *
     * @dev get the count of whitelist addresses
     *
     * @return count of whitelist addresses
     *
     */
    function getWhitelistCount() external view returns (uint256) {
        return whitelistAddresses.length;
    }

    /**
     *
     * @dev distribute the token to the investors
     *
     * @param {address} wallet address of the investor
     *
     * @return {bool} return status of distribution
     *
     */
    function claimDistribution() external nonReentrant returns (bool) {
        require(whitelistPools[msg.sender].active, "User is not in whitelist");
        require(whitelistPools[msg.sender].distributedAmount < whitelistPools[msg.sender].nftAmount,
            "All nft has been claimed");

        lfgNft.mint(whitelistPools[msg.sender].nftAmount - whitelistPools[msg.sender].distributedAmount, msg.sender);
        whitelistPools[msg.sender].distributedAmount = whitelistPools[msg.sender].nftAmount;
        
        emit ClaimDistribution(msg.sender, whitelistPools[msg.sender].nftAmount - whitelistPools[msg.sender].distributedAmount);
        return true;
    }

    function decafLists(
        address[] calldata _wallet
    ) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < _wallet.length; i++) {
            require(whitelistPools[_wallet[i]].active, "Whitelist not exist or deactivated already");
            whitelistPools[_wallet[i]].active = false;

            emit DecafList(_wallet[i]);
        }

        return true;
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

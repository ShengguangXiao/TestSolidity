// SPDX-License-Identifier: MIT

//** SAM(Social Aggregator Marketplace) Contract */
//** Author Xiao Shengguang : SAM(Social Aggregator Marketplace) Contract 2022.1 */

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/IERC2981.sol";

contract SAMContract is Ownable, ReentrancyGuard, IERC721Receiver {
    event ListingPlaced(
        bytes32 indexed listingId,
        address indexed sender,
        address indexed hostContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 buyNowPrice,
        uint256 startTime,
        uint256 duration,
        bool dutchAuction,
        uint256 discountInterval,
        uint256 discountAmount,
        string uri
    );

    event ListingRemoved(bytes32 indexed listingId, address indexed sender);

    event BiddingPlaced(bytes32 indexed biddingId, bytes32 listingId, uint256 price);

    event BuyNow(bytes32 indexed listingId, address indexed buyer, uint256 price);

    event ClaimNFT(bytes32 indexed listingId, bytes32 indexed biddingId, address indexed buyer);

    event ClaimToken(address indexed addr, uint256 amount);

    event NewFeeRate(uint256 feeRate);

    event NewFeeBurnRate(uint256 burnRate);

    event NewRoyaltiesFeeRate(uint256 royaltiesFeeRate);

    event RevenueSweep(address indexed to, uint256 amount);

    event NftDeposit(address indexed sender, address indexed hostContract, uint256 tokenId);

    event NftTransfer(address indexed sender, address indexed hostContract, uint256 tokenId);

    event RoyaltiesPaid(
        address indexed hostContract,
        uint256 indexed tokenId,
        uint256 royaltiesAmount
    );

    event RoyaltiesFeePaid(
        address indexed hostContract,
        uint256 indexed tokenId,
        uint256 royaltiesFeeAmount
    );

    event SetNftContractWhitelist(address indexed nftContract, bool isWhitelist);

    // https://eips.ethereum.org/EIPS/eip-2981
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // https://eips.ethereum.org/EIPS/eip-721
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    // https://eips.ethereum.org/EIPS/eip-1155
    bytes4 private constant _INTERFACE_ID_ERC1155 = 0xd9b67a26;

    struct listing {
        bytes32 id; // The listing id
        address seller; // The owner of the NFT who want to sell it
        address hostContract; // The source of the contract
        uint256 tokenId; // The NFT token ID
        uint256 startPrice; // The auction start price
        uint256 buyNowPrice; // The price user can directly buy the NFT
        uint256 startTime; // The timestamp of the listing creation
        uint256 auctionDuration; // The duration of the biddings, in seconds
        bool dutchAuction; // Is this auction a dutch auction
        uint256 discountInterval; // The discount interval, in seconds
        uint256 discountAmount; // The discount amount after every discount interval
        bytes32[] biddingIds; // The array of the bidding Ids
    }

    struct bidding {
        bytes32 id; // The bidding id
        address bidder; // User who submit the bidding
        bytes32 listingId; // The target listing id
        uint256 price; // The bidder price
        uint256 timestamp; // The timestamp user create the bidding
    }

    // The NFT contract whitelists, only NFT contract whitelisted can sell in the marketplace
    mapping(address => bool) public nftContractWhiteLists;

    mapping(bytes32 => listing) public listingRegistry; // The mapping of listing Id to listing details

    mapping(address => bytes32[]) public addrListingIds; // The mapping of the listings of address

    mapping(bytes32 => bidding) public biddingRegistry; // The mapping of bidding Id to bidding details

    mapping(address => bytes32[]) public addrBiddingIds; // The mapping of the bidding of address

    uint256 operationNonce;

    uint256 public constant MAXIMUM_FEE_RATE = 5000;
    uint256 public constant FEE_RATE_BASE = 10000;
    uint256 public feeRate;

    uint256 public constant MAXIMUM_FEE_BURN_RATE = 10000; // maximum burn 100% of the fee

    // The rate of fee to burn
    uint256 public feeBurnRate;

    // maximum charge 50% royalty fee
    uint256 public constant MAXIMUM_ROYALTIES_FEE_RATE = 5000;

    // The royalties fee rate
    uint256 public royaltiesFeeRate;

    // The address to burn token
    address public burnAddress;

    uint256 public totalBurnAmount;

    // The revenue address
    address public revenueAddress;

    // Total revenue amount
    uint256 public revenueAmount;

    IERC20 public lfgToken;

    struct nftItem {
        address owner; // The owner of the NFT
        address hostContract; // The source of the contract
        uint256 tokenId; // The NFT token ID
    }

    mapping(bytes32 => nftItem) public nftItems;

    struct userToken {
        uint256 lockedAmount;
    }

    mapping(address => userToken) public addrTokens;

    uint256 public totalEscrowAmount;

    constructor(
        address _owner,
        IERC20 _lfgToken,
        address _burnAddress,
        address _revenueAddress
    ) {
        _transferOwnership(_owner);
        lfgToken = _lfgToken;
        burnAddress = _burnAddress;
        revenueAddress = _revenueAddress;

        feeRate = 250; // 2.5%
        feeBurnRate = 5000; // 50%
    }

    /// @notice Checks if NFT contract implements the ERC-2981 interface
    /// @param _contract - the address of the NFT contract to query
    /// @return true if ERC-2981 interface is supported, false otherwise
    function _checkRoyalties(address _contract) internal view returns (bool) {
        bool success = ERC721(_contract).supportsInterface(_INTERFACE_ID_ERC2981);
        return success;
    }

    function _deduceRoyalties(
        address _contract,
        uint256 tokenId,
        uint256 grossSaleValue
    ) internal returns (uint256 netSaleAmount) {
        // Get amount of royalties to pays and recipient
        (address royaltiesReceiver, uint256 royaltiesAmount) = IERC2981(_contract).royaltyInfo(
            tokenId,
            grossSaleValue
        );
        // Deduce royalties from sale value
        uint256 netSaleValue = grossSaleValue - royaltiesAmount;
        // Transfer royalties to rightholder if not zero
        if (royaltiesAmount > 0) {
            uint256 royaltyFee = (royaltiesAmount * royaltiesFeeRate) / FEE_RATE_BASE;
            if (royaltyFee > 0) {
                _transferToken(msg.sender, revenueAddress, royaltyFee);
                revenueAmount += royaltyFee;

                emit RoyaltiesFeePaid(_contract, tokenId, royaltyFee);
            }

            uint256 payToReceiver = royaltiesAmount - royaltyFee;
            _transferToken(msg.sender, royaltiesReceiver, payToReceiver);

            // Broadcast royalties payment
            emit RoyaltiesPaid(_contract, tokenId, payToReceiver);
        }

        return netSaleValue;
    }

    /*
     * @notice Update the fee rate
     * @dev Only callable by owner.
     * @param _fee: the fee rate
     */
    function updateFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= MAXIMUM_FEE_RATE, "Invalid fee rate");
        feeRate = _feeRate;
        emit NewFeeRate(_feeRate);
    }

    /*
     * @notice Update the fee rate
     * @dev Only callable by owner.
     * @param _fee: the fee rate
     */
    function updateFeeBurnRate(uint256 _burnRate) external onlyOwner {
        require(_burnRate <= MAXIMUM_FEE_BURN_RATE, "Invalid fee rate");
        feeBurnRate = _burnRate;
        emit NewFeeBurnRate(_burnRate);
    }

    /*
     * @notice Update the royalty fee rate
     * @dev Only callable by owner.
     * @param _fee: the fee rate
     */
    function updateroyaltiesFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= MAXIMUM_ROYALTIES_FEE_RATE, "Invalid royalty fee rate");
        royaltiesFeeRate = _feeRate;
        emit NewRoyaltiesFeeRate(_feeRate);
    }

    /*
     * @notice Add NFT to marketplace, Support auction(Price increasing), buyNow (Fixed price) and dutch auction (Price decreasing).
     * @dev Only the token owner can call, because need to transfer the ownership to marketplace contract.
     */
    function addListing(
        address _hostContract,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _buyNowPrice,
        uint256 _startTime,
        uint256 _duration,
        bool _dutchAuction,
        uint256 _discountInterval,
        uint256 _discountAmount
    ) external nonReentrant {
        require(
            nftContractWhiteLists[_hostContract],
            "The NFT hosting contract is not in whitelist"
        );
        require(_startTime >= block.timestamp, "Listing auction start time past already");

        if (_dutchAuction) {
            uint256 discount = (_discountAmount * _duration) / _discountInterval;
            require(
                _startPrice > discount,
                "Dutch auction start price lower than the total discount"
            );
        }

        _depositNft(msg.sender, _hostContract, _tokenId);

        bytes32 listingId = keccak256(abi.encodePacked(operationNonce, _hostContract, _tokenId));

        listingRegistry[listingId].id = listingId;
        listingRegistry[listingId].seller = msg.sender;
        listingRegistry[listingId].hostContract = _hostContract;
        listingRegistry[listingId].tokenId = _tokenId;
        listingRegistry[listingId].startPrice = _startPrice;
        listingRegistry[listingId].buyNowPrice = _buyNowPrice;
        listingRegistry[listingId].startTime = _startTime;
        listingRegistry[listingId].auctionDuration = _duration;
        listingRegistry[listingId].dutchAuction = _dutchAuction;
        listingRegistry[listingId].discountInterval = _discountInterval;
        listingRegistry[listingId].discountAmount = _discountAmount;
        operationNonce++;

        addrListingIds[msg.sender].push(listingId);

        ERC721 hostContract = ERC721(_hostContract);
        string memory uri = hostContract.tokenURI(_tokenId);
        emit ListingPlaced(
            listingId,
            msg.sender,
            _hostContract,
            _tokenId,
            _startPrice,
            _buyNowPrice,
            _startTime,
            _duration,
            _dutchAuction,
            _discountInterval,
            _discountAmount,
            uri
        );
    }

    function listingOfAddr(address addr) public view returns (listing[] memory) {
        listing[] memory resultlistings = new listing[](addrListingIds[addr].length);
        for (uint256 i = 0; i < addrListingIds[addr].length; ++i) {
            bytes32 listingId = addrListingIds[addr][i];
            resultlistings[i] = listingRegistry[listingId];
        }
        return resultlistings;
    }

    function getPrice(bytes32 listingId) public view returns (uint256) {
        listing storage lst = listingRegistry[listingId];
        require(lst.startTime > 0, "The listing doesn't exist");

        if (lst.dutchAuction) {
            uint256 timeElapsed = block.timestamp - lst.startTime;
            uint256 discount = lst.discountAmount * (timeElapsed / lst.discountInterval);
            return lst.startPrice - discount;
        }

        return lst.buyNowPrice;
    }

    /*
     * @notice Place bidding for the listing item, only support normal auction.
     * @dev The bidding price must higher than previous price.
     */
    function placeBid(bytes32 listingId, uint256 price) external nonReentrant {
        listing storage lst = listingRegistry[listingId];
        require(block.timestamp >= lst.startTime, "The auction haven't start");
        require(
            lst.startTime + lst.auctionDuration >= block.timestamp,
            "The auction already expired"
        );
        require(!lst.dutchAuction, "Cannot place bid for dutch auction");

        uint256 minPrice = lst.startPrice;
        // The last element is the current highest price
        if (lst.biddingIds.length > 0) {
            bytes32 lastBiddingId = lst.biddingIds[lst.biddingIds.length - 1];
            minPrice = biddingRegistry[lastBiddingId].price;
        }

        require(price > minPrice, "Bid price too low");

        _depositToken(msg.sender, price);

        bytes32 biddingId = keccak256(
            abi.encodePacked(operationNonce, lst.hostContract, lst.tokenId)
        );
        biddingRegistry[biddingId].id = biddingId;
        biddingRegistry[biddingId].bidder = msg.sender;
        biddingRegistry[biddingId].listingId = listingId;
        biddingRegistry[biddingId].price = price;
        biddingRegistry[biddingId].timestamp = block.timestamp;

        operationNonce++;

        lst.biddingIds.push(biddingId);

        addrBiddingIds[msg.sender].push(biddingId);

        emit BiddingPlaced(biddingId, listingId, price);
    }

    function biddingOfListing(bytes32 listingId) public view returns (bidding[] memory) {
        listing storage lst = listingRegistry[listingId];
        bidding[] memory bids = new bidding[](lst.biddingIds.length);
        for (uint256 i = 0; i < lst.biddingIds.length; ++i) {
            bytes32 biddingId = lst.biddingIds[i];
            bids[i] = biddingRegistry[biddingId];
        }
        return bids;
    }

    function biddingOfAddr(address addr) public view returns (bidding[] memory) {
        bidding[] memory biddings = new bidding[](addrBiddingIds[addr].length);
        for (uint256 i = 0; i < addrBiddingIds[addr].length; ++i) {
            bytes32 biddingId = addrBiddingIds[addr][i];
            biddings[i] = biddingRegistry[biddingId];
        }
        return biddings;
    }

    /*
     * @notice Immediately buy the NFT.
     * @dev If it is dutch auction, then the price is dutch auction price, if normal auction, then the price is buyNowPrice.
     */
    function buyNow(bytes32 listingId) external nonReentrant {
        listing storage lst = listingRegistry[listingId];
        require(block.timestamp >= lst.startTime, "The auction haven't start");
        require(
            lst.startTime + lst.auctionDuration >= block.timestamp,
            "The auction already expired"
        );

        uint256 price = getPrice(listingId);

        _processFee(msg.sender, price);

        // Deposit the tokens to market place contract.
        _depositToken(msg.sender, price);

        uint256 sellerAmount = price;
        if (_checkRoyalties(lst.hostContract)) {
            sellerAmount = _deduceRoyalties(lst.hostContract, lst.tokenId, price);
        }

        _transferToken(msg.sender, lst.seller, sellerAmount);
        _transferNft(msg.sender, lst.hostContract, lst.tokenId);

        emit BuyNow(listingId, msg.sender, price);

        // Refund the failed bidder
        for (uint256 i = 0; i < lst.biddingIds.length; ++i) {
            bytes32 tmpId = lst.biddingIds[i];
            _transferToken(
                biddingRegistry[tmpId].bidder,
                biddingRegistry[tmpId].bidder,
                biddingRegistry[tmpId].price
            );
        }

        _removeListing(listingId, lst.seller);
    }

    function _removeListing(bytes32 listingId, address seller) private {
        uint256 length = addrListingIds[seller].length;
        for (uint256 index = 0; index < length; ++index) {
            // Move the last element to the index need to remove
            if (addrListingIds[seller][index] == listingId && index != length - 1) {
                addrListingIds[seller][index] = addrListingIds[seller][length - 1];
            }
        }
        // Remove the last element
        addrListingIds[seller].pop();

        // Delete from the mapping
        delete listingRegistry[listingId];

        emit ListingRemoved(listingId, seller);
    }

    /*
     * @notice The highest bidder claim the NFT he bought.
     * @dev Can only claim after the auction period finished.
     */
    function claimNft(bytes32 biddingId) external nonReentrant {
        bidding storage bid = biddingRegistry[biddingId];
        require(bid.bidder == msg.sender, "Only bidder can claim NFT");

        listing storage lst = listingRegistry[bid.listingId];
        require(
            lst.startTime + lst.auctionDuration < block.timestamp,
            "The bidding period haven't complete"
        );
        for (uint256 i = 0; i < lst.biddingIds.length; ++i) {
            bytes32 tmpId = lst.biddingIds[i];
            if (biddingRegistry[tmpId].price > bid.price) {
                require(false, "The bidding is not the highest price");
            }
        }

        _processFee(msg.sender, bid.price);
        _transferNft(msg.sender, lst.hostContract, lst.tokenId);

        uint256 sellerAmount = bid.price;
        if (_checkRoyalties(lst.hostContract)) {
            sellerAmount = _deduceRoyalties(lst.hostContract, lst.tokenId, bid.price);
        }

        _transferToken(msg.sender, lst.seller, sellerAmount);

        emit ClaimNFT(lst.id, biddingId, msg.sender);

        // Refund the failed bidder
        for (uint256 i = 0; i < lst.biddingIds.length; ++i) {
            bytes32 tmpId = lst.biddingIds[i];
            if (tmpId != biddingId) {
                _transferToken(
                    biddingRegistry[tmpId].bidder,
                    biddingRegistry[tmpId].bidder,
                    biddingRegistry[tmpId].price
                );
            }
        }

        _removeListing(lst.id, lst.seller);
    }

    function removeListing(bytes32 listingId) external nonReentrant {
        listing storage lst = listingRegistry[listingId];
        require(
            lst.startTime + lst.auctionDuration < block.timestamp,
            "The listing haven't expired"
        );
        require(lst.seller == msg.sender, "Only seller can remove the listing");
        require(lst.biddingIds.length == 0, "Already received bidding, cannot close it");

        // return the NFT to seller
        _transferNft(msg.sender, lst.hostContract, lst.tokenId);

        _removeListing(lst.id, lst.seller);
    }

    function _processFee(address buyer, uint256 price) internal {
        uint256 fee = (price * feeRate) / FEE_RATE_BASE;
        uint256 feeToBurn = (fee * feeBurnRate) / FEE_RATE_BASE;
        uint256 revenue = fee - feeToBurn;
        lfgToken.transferFrom(buyer, revenueAddress, revenue);
        lfgToken.transferFrom(buyer, burnAddress, feeToBurn);
        totalBurnAmount += feeToBurn;

        revenueAmount += revenue;
    }

    function _depositNft(
        address from,
        address _hostContract,
        uint256 _tokenId
    ) internal {
        ERC721 nftContract = ERC721(_hostContract);
        nftContract.safeTransferFrom(from, address(this), _tokenId);

        bytes32 itemId = keccak256(abi.encodePacked(_hostContract, _tokenId));
        nftItems[itemId] = nftItem({owner: from, hostContract: _hostContract, tokenId: _tokenId});

        emit NftDeposit(from, _hostContract, _tokenId);
    }

    function _transferNft(
        address to,
        address _hostContract,
        uint256 _tokenId
    ) internal {
        bytes32 itemId = keccak256(abi.encodePacked(_hostContract, _tokenId));

        ERC721 nftContract = ERC721(_hostContract);
        nftContract.safeTransferFrom(address(this), to, _tokenId);
        delete nftItems[itemId];

        emit NftTransfer(to, _hostContract, _tokenId);
    }

    function _depositToken(address addr, uint256 _amount) internal {
        lfgToken.transferFrom(addr, address(this), _amount);
        addrTokens[addr].lockedAmount += _amount;
        totalEscrowAmount += _amount;
    }

    function _transferToken(
        address from,
        address to,
        uint256 _amount
    ) internal {
        require(addrTokens[from].lockedAmount >= _amount, "The locked amount is not enough");
        lfgToken.transfer(to, _amount);
        addrTokens[from].lockedAmount -= _amount;
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /*
     * @notice Update the burn address
     * @dev Only callable by owner.
     * @param _fee: the burn address
     */
    function updateBurnAddress(address _burnAddress) external onlyOwner {
        burnAddress = _burnAddress;
    }

    /*
     * @notice Update the revenue address
     * @dev Only callable by owner.
     * @param _fee: the revenue address
     */
    function updateRevenueAddress(address _revenueAddress) external onlyOwner {
        require(_revenueAddress != address(0), "Invalid revenue address");
        revenueAddress = _revenueAddress;
    }

    function setNftContractWhitelist(address _addr, bool _isWhitelist) external onlyOwner {
        require(_addr != address(0), "Invalid NFT contract address");
        require(
            IERC165(_addr).supportsInterface(_INTERFACE_ID_ERC721),
            "Invalid NFT token contract address"
        );

        nftContractWhiteLists[_addr] = _isWhitelist;

        emit SetNftContractWhitelist(_addr, _isWhitelist);
    }
}

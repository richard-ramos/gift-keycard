pragma solidity ^0.6.1;
pragma experimental ABIEncoderV2;

import "./ERC20Token.sol";

contract GiftBucket {

  bool initialized;

  address payable public owner;

  ERC20Token public tokenContract;

  uint256 public expirationTime;

  struct Gift {
    address recipient;
    uint256 amount;
    bytes32 code;
  }

  mapping(address => Gift) public gifts;

  struct Redeem {
    address recipient;
    address receiver;
    bytes32 code;
  }

  uint256 public redeemableSupply;

  bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 constant REDEEM_TYPEHASH = keccak256("Redeem(address recipient,address receiver,bytes32 code)");
  bytes32 DOMAIN_SEPARATOR;

  modifier onlyOwner() {
    require(msg.sender == owner, "owner required");
    _;
  }

  constructor(address _tokenAddress, uint256 _expirationTime) public {
    initialize(_tokenAddress, _expirationTime, msg.sender);
  }

  function initialize(address _tokenAddress, uint256 _expirationTime, address _owner) public {
    require(initialized == false, "already initialized");

    require(_expirationTime > block.timestamp, "expiration can't be in the past");

    tokenContract = ERC20Token(_tokenAddress);
    expirationTime = _expirationTime;
    owner = payable(_owner);

    DOMAIN_SEPARATOR = keccak256(abi.encode(
      EIP712DOMAIN_TYPEHASH,
      keccak256("KeycardGift"),
      keccak256("1"),
      _getChainID(),
      address(this)
    ));

    initialized = true;
  }

  function _getChainID() internal pure returns (uint256) {
    uint256 id;
    assembly {
      id := chainid()
    }

    return id;
  }

  function totalSupply() public view returns(uint256) {
    return tokenContract.balanceOf(address(this));
  }

  function availableSupply() public view returns(uint256) {
    uint256 _totalSupply = this.totalSupply();
    require(_totalSupply >= redeemableSupply, "redeemableSupply is greater than redeemableSupply");

    return _totalSupply - redeemableSupply;
  }

  function createGift(address recipient, uint256 amount, bytes32 code) external onlyOwner {
    require(amount > 0, "invalid amount");

    uint256 _availableSupply = this.availableSupply();
    require(_availableSupply >= amount, "low supply");

    Gift storage gift = gifts[recipient];
    require(gift.amount == 0, "recipient already used");

    gift.recipient = recipient;
    gift.amount = amount;
    gift.code = code;

    require(redeemableSupply + amount > redeemableSupply, "addition overflow");
    redeemableSupply += amount;
  }

  function redeem(Redeem calldata _redeem, bytes calldata sig) external {
    require(block.timestamp < expirationTime, "expired gift");

    Gift storage gift = gifts[_redeem.recipient];
    require(gift.amount > 0, "not found");

    bool signedByKeycard = verifySig(_redeem, sig);
    require(signedByKeycard, "wrong recipient sig");

    bytes32 codeHash = keccak256(abi.encodePacked(_redeem.code));
    require(codeHash == gift.code, "invalid code");

    uint256 amount = gift.amount;
    require(redeemableSupply >= amount, "not enough redeemable supply");

    gift.amount = 0;
    redeemableSupply -= amount;

    tokenContract.transfer(_redeem.receiver, amount);
  }

  function kill() external onlyOwner {
    require(block.timestamp >= expirationTime, "not expired yet");

    bool success = tokenContract.transfer(owner, this.totalSupply());
    assert(success);

    selfdestruct(owner);
  }

  function hashRedeem(Redeem memory _redeem) internal pure returns (bytes32) {
    return keccak256(abi.encode(
      REDEEM_TYPEHASH,
      _redeem.recipient,
      _redeem.receiver,
      _redeem.code
    ));
  }

  function verifySig(Redeem memory _redeem, bytes memory sig) internal view returns(bool) {
    require(sig.length == 65, "bad signature length");

    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
      r := mload(add(sig, 32))
      s := mload(add(sig, 64))
      v := byte(0, mload(add(sig, 96)))
    }

    if (v < 27) {
      v += 27;
    }

    require(v == 27 || v == 28, "signature version doesn't match");

    bytes32 digest = keccak256(abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        hashRedeem(_redeem)
    ));

    return ecrecover(digest, v, r, s) == _redeem.recipient;
  }
}

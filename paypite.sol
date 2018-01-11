pragma solidity ^0.4.18;

library SafeMath {
  uint256 constant public MAX_UINT256 =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a / b;
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions"
 */
contract Ownable {
  address public owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account
   */
  function Ownable() public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner
   * @param newOwner The address to transfer ownership to
   */
  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0));
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }
}

contract ERC223 {
  function balanceOf(address who) constant public returns (uint);

  function name() constant public returns (string _name);
  function symbol() constant public returns (string _symbol);
  function decimals() constant public returns (uint8 _decimals);
  function totalSupply() constant public returns (uint256 _supply);

  function transfer(address to, uint value) public returns (bool ok);
  function transfer(address to, uint value, bytes data) public returns (bool ok);
  function transfer(address to, uint value, bytes data, string customFallback) public returns (bool ok);
  event Transfer(address indexed from, address indexed to, uint value, bytes indexed data);
}

 contract ContractReceiver {
    struct TKN {
      address sender;
      uint value;
      bytes data;
      bytes4 sig;
    }

    function tokenFallback(address _from, uint _value, bytes _data) {
      TKN memory tkn;
      tkn.sender = _from;
      tkn.value = _value;
      tkn.data = _data;
      uint32 u = uint32(_data[3]) + (uint32(_data[2]) << 8) + (uint32(_data[1]) << 16) + (uint32(_data[0]) << 24);
      tkn.sig = bytes4(u);

     /* tkn variable is analogue of msg variable of Ether transaction
      * tkn.sender is person who initiated this token transaction   (analogue of msg.sender)
      * tkn.value the number of tokens that were sent   (analogue of msg.value)
      * tkn.data is data of token transaction   (analogue of msg.data)
      * tkn.sig is 4 bytes signature of function
      * if data of token transaction is a function execution
      */
    }
}

contract PaypiteToken is Ownable, ERC223 {
  using SafeMath for uint256;

  address public owner = msg.sender;

  uint8 private _decimals = 18;
  uint256 public decimalMultiplier = 10**(uint256(_decimals));

  string private _name = "Paypite";
  string private _symbol = "PIT";
  uint256 private _totalSupply = 274000000 * decimalMultiplier;

  bool public tradable = true;

  // Wallet Address of Token
  address public multisig;

  // Function to access name of token
  function name() constant returns (string) {
    return _name;
  }

  // Function to access symbol of token
  function symbol() constant returns (string) {
    return _symbol;
  }

  // Function to access decimals of token
  function decimals() constant returns (uint8) {
    return _decimals;
  }

  // Function to access total supply of tokens
  function totalSupply() constant returns (uint256) {
    return _totalSupply;
  }

  mapping(address => uint256) balances;
  mapping(address => mapping (address => uint256)) allowed;
  mapping(address => uint256) releaseTimes;

  event Transfer(address indexed _from, address indexed _to, uint256 _value);
  event Approval(address indexed _owner, address indexed _spender, uint256 _value);
  event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

  // Constructor
  // @notice PaypiteToken Contract
  // @return the transaction address
  function PaypiteToken(address _multisig) {
    require(_multisig != 0x0);
    multisig = _multisig;
    balances[multisig] = _totalSupply;
    owner = msg.sender;
  }

  modifier canTrade() {
    require(tradable);
    _;
  }

  // Function that is called when a user or another contract wants to transfer funds
  function transfer(address _to, uint256 _value, bytes _data, string _customFallback) canTrade public returns (bool) {
    if (isContract(_to)) {
      require(balanceOf(msg.sender) > _value);
      balances[msg.sender] = (balanceOf(msg.sender)).sub(_value);
      balances[_to] = (balanceOf(_to)).add(_value);
      assert(_to.call.value(0)(bytes4(sha3(_customFallback)), msg.sender, _value, _data));
      Transfer(msg.sender, _to, _value, _data);
      return true;
    } else {
      return transferToAddress(_to, _value, _data);
    }
  }

  // Function that is called when a user or another contract wants to transfer funds
  function transfer(address _to, uint _value, bytes _data) canTrade returns (bool success) {
    if (isContract(_to)) {
      return transferToContract(_to, _value, _data);
    } else {
      return transferToAddress(_to, _value, _data);
    }
  }

  // Standard function transfer similar to ERC20 transfer with no _data
  // Added due to backwards compatibility reasons
  function transfer(address _to, uint _value) canTrade returns (bool success) {
    require(!timeLocked(msg.sender));

    // standard function transfer similar to ERC20 transfer with no _data
    // added due to backwards compatibility reasons
    bytes memory empty;
    if (isContract(_to)) {
      return transferToContract(_to, _value, empty);
    } else {
      return transferToAddress(_to, _value, empty);
    }
  }

  // assemble the given address bytecode. If bytecode exists then the _addr is a contract
  function isContract(address _addr) private returns (bool) {
    uint length;
    assembly {
      // retrieve the size of the code on target address, this needs assembly
      length := extcodesize(_addr)
    }
    return (length > 0);
  }

  // function that is called when transaction target is an address
  function transferToAddress(address _to, uint _value, bytes _data) private returns (bool success) {
    assert(balanceOf(msg.sender) > _value);
    balances[msg.sender] = (balanceOf(msg.sender)).sub(_value);
    balances[_to] = (balanceOf(_to)).add(_value);
    Transfer(msg.sender, _to, _value, _data);
    return true;
  }

  // function that is called when transaction target is a contract
  function transferToContract(address _to, uint _value, bytes _data) private returns (bool success) {
    assert(balanceOf(msg.sender) > _value);
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    ContractReceiver receiver = ContractReceiver(_to);
    receiver.tokenFallback(msg.sender, _value, _data);
    Transfer(msg.sender, _to, _value, _data);
    return true;
  }

  /**
   * @dev Gets the balance of the specified address
   * @param _owner The address to query the the balance of
   * @return An uint256 representing the amount owned by the passed address
   */
  function balanceOf(address _owner) view public returns (uint256 bal) {
    return balances[_owner];
  }

 /**
  * @dev Transfer tokens from one address to another
  * @param _from address The address which you want to send tokens from
  * @param _to address The address which you want to transfer to
  * @param _value uint256 the amount of tokens to be transfered
  */
  function transferFrom(address _from, address _to, uint256 _value) canTrade public returns (bool) {
    require(_to != address(0));
    require(!timeLocked(_from));
    uint256 _allowance = allowed[_from][msg.sender];
    require(_allowance >= _value);
    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender
   * @param _spender The address which will spend the funds
   * @param _value The amount of tokens to be spent
   */
  function approve(address _spender, uint256 _value) canTrade public returns (bool) {
    require((_value == 0) || (allowed[msg.sender][_spender] == 0));
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  /**
   * @dev Function to update tradable status
   * @param _newTradableState New tradable state
   * @return A boolean that indicates if the operation was successful
   */
  function setTradable(bool _newTradableState) onlyOwner public returns (bool success) {
    tradable = _newTradableState;
  }

  function modifyCap(uint256 _cap) onlyOwner public {
    _totalSupply = _cap;
  }

  /**
   * Function to lock a given address until the specified date
   * @param spender Address to lock
   * @param date A timestamp specifying when the account will be unlocked
   * @return A boolean that indicates if the operation was successful
   */
  function timeLock(address spender, uint256 date) public onlyOwner returns (bool) {
    releaseTimes[spender] = date;
    return true;
  }

  /**
   * Function to check if a given address is locked or not
   * @param _spender Address
   * @return A boolean that indicates if the account is locked or not
   */
  function isLocked(address _spender) public view returns (bool) {
    if (releaseTimes[_spender] == 0) {
      return false;
    }

    // If time-lock is expired, delete it
    // We consider timestamp dependency to be safe enough in this application
    if (releaseTimes[_spender] <= block.timestamp) {
      return false;
    }

    return true;
  }

  // Checks if funds of a given address are time-locked
  function timeLocked(address _spender) public returns (bool) {
    if (releaseTimes[_spender] == 0) {
      return false;
    }

    // If time-lock is expired, delete it
    // We consider timestamp dependency to be safe enough in this application
    if (releaseTimes[_spender] <= block.timestamp) {
      delete releaseTimes[_spender];
      return false;
    }

    return true;
  }
}
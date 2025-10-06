// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RemoteVaultHop } from "src/contracts/hop/RemoteVaultHop.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ======================= RemoteVaultDeposit =======================
// ====================================================================

/// @title RemoteVaultDeposit
/// @author Frax Finance: https://github.com/FraxFinance
/// @notice ERC20 token representing deposits in remote vaults, can only be minted/burned by the RemoteVault contract
contract RemoteVaultDeposit is ERC20, Ownable {
    /// @notice The RemoteVaultHop contract that controls this token
    address payable public immutable REMOTE_VAULT_HOP;

    /// @notice The chain ID where the vault is located
    uint32 public immutable VAULT_CHAIN_ID;
    
    /// @notice The address of the vault on the remote chain
    address public immutable VAULT_ADDRESS;

    /// @notice The asset deposited into the remote vault
    address public immutable ASSET;

    /// @notice Price per share of the remote vault
    uint128 private pps;

    /// @notice Previous price per share of the remote vault
    uint128 private previousPps;

    /// @notice Block number when price per share was last updated
    uint64 private ppsUpdateBlock;

    /// @notice Timestamp of the last price per share update from the remote vault
    uint64 private ppsRemoteTimestamp;

    /// @notice Only the RemoteVault contract can mint/burn tokens
    error OnlyRemoteVault();

    /// @notice Emitted when tokens are minted
    event Mint(address indexed to, uint256 amount);

    /// @notice Emitted when tokens are burned
    event Burn(address indexed from, uint256 amount);

    /// @dev Constructor sets up the ERC20 token and ownership
    /// @param _vaultChainId The chain ID where the vault is located
    /// @param _vaultAddress The address of the vault on the remote chain
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    constructor(
        uint32 _vaultChainId,
        address _vaultAddress,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        REMOTE_VAULT_HOP = payable(msg.sender);
        VAULT_CHAIN_ID = _vaultChainId;
        VAULT_ADDRESS = _vaultAddress;
        ASSET = _asset;
    }

    /// @notice Receive ETH payments
    receive() external payable {}

    /// @notice Mint tokens to a specific address
    /// @dev Can only be called by the RemoteVault contract (owner)
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /// @notice Get the current price per share of the remote vault
    /// @dev Returns the last known price per share, with a simple linear interpolation if called within 100 blocks of the last update
    function pricePerShare() public view returns (uint256) {
        if (block.number > ppsUpdateBlock + 100) return pps;
        else return previousPps + (uint256(pps - previousPps) * (block.number - ppsUpdateBlock)) / 100;
    }

    /// @notice Set the price per share of the remote vault
    /// @dev Can only be called by the owner (RemoteVault contract)
    function setPricePerShare(uint64 _remoteTimestamp, uint128 _pricePerShare) external onlyOwner {
        if (_pricePerShare > 0 && _remoteTimestamp > ppsRemoteTimestamp) {
            previousPps = uint128(pricePerShare());
            if (previousPps == 0) previousPps = _pricePerShare;
            ppsUpdateBlock = uint64(block.number);
            ppsRemoteTimestamp = _remoteTimestamp;
            pps = _pricePerShare;
        }
    }

    function deposit(uint256 _amount) external payable {
        deposit(_amount, msg.sender);
    }

    function deposit(uint256 _amount, address _to) public payable {
        IERC20(ASSET).transferFrom(msg.sender, address(REMOTE_VAULT_HOP), _amount);
        RemoteVaultHop(REMOTE_VAULT_HOP).deposit{value: msg.value}(_amount, VAULT_CHAIN_ID, VAULT_ADDRESS, _to);
        if (address(this).balance > 0) {
            (bool success, ) = msg.sender.call{value: address(this).balance}("");
            require(success, "Refund failed");
        }
    }

    function redeem(uint256 _amount) public payable {
        redeem(_amount, msg.sender);
    }

    function redeem(uint256 _amount, address _to) public payable {
        _burn(msg.sender, _amount);
        emit Burn(msg.sender, _amount);

        RemoteVaultHop(REMOTE_VAULT_HOP).redeem{value: msg.value}(_amount, VAULT_CHAIN_ID, VAULT_ADDRESS, _to);
        if (address(this).balance > 0) {
            (bool success, ) = msg.sender.call{value: address(this).balance}("");
            require(success, "Refund failed");
        }
    }

    function quote(uint256 _amount) public view returns (uint256) {
        return  RemoteVaultHop(REMOTE_VAULT_HOP).quote(_amount, VAULT_CHAIN_ID, VAULT_ADDRESS);
    }
}

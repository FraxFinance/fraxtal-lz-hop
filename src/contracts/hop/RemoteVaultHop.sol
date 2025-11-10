pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IHopComposer } from "./interfaces/IHopComposer.sol";
import { IHopV2 } from "./interfaces/IHopV2.sol";
import { RemoteVaultDeposit } from "./RemoteVaultDeposit.sol";
import { IOFT2 } from "./interfaces/IOFT2.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== RemoteVault ============================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract RemoteVaultHop is Ownable2Step, IHopComposer {
    IERC20 public immutable TOKEN;
    address public immutable OFT;
    IHopV2 public immutable HOP;
    uint32 public immutable EID; // This chain's EID on LayerZero
    uint256 public immutable DECIMAL_CONVERSION_RATE;
    uint128 public constant DEFAULT_REMOTE_GAS = 400000;
    uint32 public constant FRAXTAL_EID = 30255;
    uint32 public constant FRAXTAL_GAS = 400000;

    // Local vault management
    /// @notice The vault share token by vault address
    mapping(address => address) public vaultShares;
    /// @notice The balance of shares owned by users in remote vaults
    mapping(uint32 => mapping(address => uint256)) public balance; // vault => srcEid => srcAddress => shares

    // Remote vault management
    /// @notice Remote vault hop address by eid
    mapping(uint32 => address) public remoteVaultHops;
    /// @notice Deposit token mapping for tracking user deposits in remote vaults
    mapping(uint32 => mapping(address => RemoteVaultDeposit)) public depositToken; // eid => vault => rvd
    /// @notice The token used for deposits and withdrawals
    mapping(uint32 => mapping(address => uint128)) public remoteGas; // eid => vault => remote gas

    /// @notice Message structure for cross-chain communication
    /// @dev Used in hopCompose to decode incoming messages
    struct RemoteVaultMessage {
        Action action;
        uint32 userEid;
        address userAddress;
        uint32 remoteEid;
        address remoteVault;
        uint256 amount;
        uint64 remoteTimestamp;
        uint128 pricePerShare;
    }

    enum Action {
        Deposit,
        DepositReturn,
        Redeem,
        RedeemReturn
    }

    error ZeroAmount();
    error InvalidChain();
    error InvalidOFT();
    error InsufficientFee();
    error NotHop();
    error InvalidAction();
    error InvalidVault();
    error InvalidAmount();
    error VaultExists();
    error RefundFailed();
    error InvalidCaller();

    event VaultAdded(address vault, address share);
    event RemoteVaultAdded(uint32 eid, address vault, string name, string symbol);
    event RemoteVaultHopSet(uint32 eid, address remoteVaultHop);
    event RemoteGasSet(uint32 eid, address vault, uint128 remoteGas);
    event Deposit(address indexed to, uint32 indexed remoteEid, address indexed remoteVault, uint256 amount);
    event Redeem(address indexed to, uint32 indexed remoteEid, address indexed remoteVault, uint256 amount);

    constructor(address _token, address _oft, address _hop, uint32 _eid) Ownable(msg.sender) {
        TOKEN = IERC20(_token);
        OFT = _oft;
        HOP = IHopV2(_hop);
        EID = _eid;
        DECIMAL_CONVERSION_RATE = IOFT2(OFT).decimalConversionRate();
    }

    /// @notice Receive ETH payments
    receive() external payable {}

    function deposit(uint256 _amount, uint32 _remoteEid, address _remoteVault, address _to) external payable {
        if (remoteVaultHops[_remoteEid] == address(0)) revert InvalidChain();
        if (address(depositToken[_remoteEid][_remoteVault]) != msg.sender) revert InvalidCaller();

        uint256 fee = quote(_amount, _remoteEid, _remoteVault);
        if (msg.value < fee) revert InsufficientFee();
        SafeERC20.forceApprove(TOKEN, address(HOP), _amount);
        bytes memory hopComposeMessage = abi.encode(
            RemoteVaultMessage({
                action: Action.Deposit,
                userEid: EID,
                userAddress: _to,
                remoteEid: _remoteEid,
                remoteVault: _remoteVault,
                amount: _amount,
                remoteTimestamp: 0,
                pricePerShare: 0
            })
        );
        uint128 _remoteGas = getRemoteVaultGas(_remoteEid, _remoteVault);
        HOP.sendOFT{ value: fee }(
            OFT,
            _remoteEid,
            bytes32(uint256(uint160(remoteVaultHops[_remoteEid]))),
            _amount,
            _remoteGas,
            hopComposeMessage
        );
        if (msg.value > fee) {
            (bool success, ) = msg.sender.call{ value: msg.value - fee }("");
            if (!success) revert RefundFailed();
        }
        emit Deposit(_to, _remoteEid, _remoteVault, _amount);
    }

    function redeem(uint256 _amount, uint32 _remoteEid, address _remoteVault, address _to) external payable {
        if (remoteVaultHops[_remoteEid] == address(0)) revert InvalidChain();
        if (address(depositToken[_remoteEid][_remoteVault]) != msg.sender) revert InvalidCaller();

        uint256 fee = quote(_amount, _remoteEid, _remoteVault);
        if (msg.value < fee) revert InsufficientFee();
        bytes memory hopComposeMessage = abi.encode(
            RemoteVaultMessage({
                action: Action.Redeem,
                userEid: EID,
                userAddress: _to,
                remoteEid: _remoteEid,
                remoteVault: _remoteVault,
                amount: _amount,
                remoteTimestamp: 0,
                pricePerShare: 0
            })
        );
        uint128 _remoteGas = getRemoteVaultGas(_remoteEid, _remoteVault);
        HOP.sendOFT{ value: fee }(
            OFT,
            _remoteEid,
            bytes32(uint256(uint160(remoteVaultHops[_remoteEid]))),
            0,
            _remoteGas,
            hopComposeMessage
        );
        if (msg.value > fee) {
            (bool success, ) = msg.sender.call{ value: msg.value - fee }("");
            if (!success) revert RefundFailed();
        }
        emit Redeem(_to, _remoteEid, _remoteVault, _amount);
    }

    function quote(uint256 _amount, uint32 _remoteEid, address _remoteVault) public view returns (uint256) {
        bytes memory hopComposeMessage = abi.encode(
            RemoteVaultMessage({
                action: Action.Redeem,
                userEid: EID,
                userAddress: msg.sender,
                remoteEid: _remoteEid,
                remoteVault: _remoteVault,
                amount: _amount,
                remoteTimestamp: 0,
                pricePerShare: 0
            })
        );

        uint128 _remoteGas = getRemoteVaultGas(_remoteEid, _remoteVault);

        // Quote double hop to RemoteVault
        uint256 fee = HOP.quote(
            OFT,
            _remoteEid,
            bytes32(uint256(uint160(address(this)))),
            _amount,
            _remoteGas,
            hopComposeMessage
        );

        // Quote double return hop to this contract
        fee += HOP.quote(OFT, EID, bytes32(uint256(uint160(address(this)))), _amount, _remoteGas, hopComposeMessage);
        return fee;
    }

    function hopCompose(
        uint32 _srcEid,
        bytes32 _srcAddress,
        address _oft,
        uint256 _amount,
        bytes memory _data
    ) external {
        if (msg.sender != address(HOP)) revert NotHop();
        if (_oft != OFT) revert InvalidOFT();
        if (bytes32(uint256(uint160(remoteVaultHops[_srcEid]))) != _srcAddress) revert InvalidChain();

        //(uint256 _actionUint, uint32 _userEid, address _userAddress, uint32 _vaultEid, address _vaultAddress, uint256 _amnt, uint256 _pricePerShare) = abi.decode(_data, (uint256, uint32, address, uint32, address, uint256, uint256));
        RemoteVaultMessage memory message = abi.decode(_data, (RemoteVaultMessage));
        if (message.action == Action.Deposit) {
            if (_amount != message.amount) revert InvalidAmount();
            _handleDeposit(message);
        } else if (message.action == Action.Redeem) {
            _handleRedeem(message);
        } else if (message.action == Action.RedeemReturn) {
            if (_amount != message.amount) revert InvalidAmount();
            _handleRedeemReturn(message);
        } else if (message.action == Action.DepositReturn) {
            _handleDepositReturn(message);
        } else {
            revert InvalidAction();
        }
    }

    function _handleDeposit(RemoteVaultMessage memory message) internal {
        SafeERC20.forceApprove(TOKEN, message.remoteVault, message.amount);
        uint256 out = IERC4626(message.remoteVault).deposit(message.amount, address(this));
        balance[message.remoteEid][message.remoteVault] += out;

        uint256 _pricePerShare = IERC4626(message.remoteVault).convertToAssets(1E18);
        bytes memory _data = abi.encode(
            RemoteVaultMessage({
                action: Action.DepositReturn,
                userEid: message.userEid,
                userAddress: message.userAddress,
                remoteEid: EID,
                remoteVault: message.remoteVault,
                amount: out,
                remoteTimestamp: uint64(block.timestamp),
                pricePerShare: uint128(_pricePerShare)
            })
        );

        uint256 fee = HOP.quote(
            OFT,
            message.userEid,
            bytes32(uint256(uint160(remoteVaultHops[message.userEid]))),
            0,
            FRAXTAL_GAS,
            _data
        );
        HOP.sendOFT{ value: fee }(
            OFT,
            message.userEid,
            bytes32(uint256(uint160(remoteVaultHops[message.userEid]))),
            0,
            FRAXTAL_GAS,
            _data
        );
    }

    function _handleRedeem(RemoteVaultMessage memory message) internal {
        IERC20(vaultShares[message.remoteVault]).approve(address(message.remoteVault), message.amount);
        uint256 out = IERC4626(message.remoteVault).redeem(message.amount, address(this), address(this));
        balance[message.remoteEid][message.remoteVault] -= message.amount;
        out = removeDust(out);
        uint256 _pricePerShare = IERC4626(message.remoteVault).convertToAssets(1E18);
        bytes memory _data = abi.encode(
            RemoteVaultMessage({
                action: Action.RedeemReturn,
                userEid: message.userEid,
                userAddress: message.userAddress,
                remoteEid: EID,
                remoteVault: message.remoteVault,
                amount: out,
                remoteTimestamp: uint64(block.timestamp),
                pricePerShare: uint128(_pricePerShare)
            })
        );
        uint256 fee = HOP.quote(
            OFT,
            message.userEid,
            bytes32(uint256(uint160(remoteVaultHops[message.userEid]))),
            out,
            FRAXTAL_GAS,
            _data
        );
        SafeERC20.forceApprove(TOKEN, address(HOP), out);
        HOP.sendOFT{ value: fee }(
            OFT,
            message.userEid,
            bytes32(uint256(uint160(remoteVaultHops[message.userEid]))),
            out,
            FRAXTAL_GAS,
            _data
        );
    }

    function _handleRedeemReturn(RemoteVaultMessage memory message) internal {
        SafeERC20.safeTransfer(TOKEN, message.userAddress, message.amount);
        depositToken[message.remoteEid][message.remoteVault].setPricePerShare(
            message.remoteTimestamp,
            message.pricePerShare
        );
    }

    function _handleDepositReturn(RemoteVaultMessage memory message) internal {
        depositToken[message.remoteEid][message.remoteVault].mint(message.userAddress, message.amount);
        depositToken[message.remoteEid][message.remoteVault].setPricePerShare(
            message.remoteTimestamp,
            message.pricePerShare
        );
    }

    function setRemoteVaultHop(uint32 _eid, address _remoteVault) external onlyOwner {
        remoteVaultHops[_eid] = _remoteVault;
        emit RemoteVaultHopSet(_eid, _remoteVault);
    }

    function addLocalVault(address _vault, address _share) external onlyOwner {
        vaultShares[_vault] = _share;
        emit VaultAdded(_vault, _share);
    }

    function addRemoteVault(uint32 _eid, address _vault, string memory name, string memory symbol) external onlyOwner {
        if (address(depositToken[_eid][_vault]) != address(0)) revert VaultExists();
        depositToken[_eid][_vault] = new RemoteVaultDeposit(_eid, _vault, address(TOKEN), name, symbol);
        emit RemoteVaultAdded(_eid, _vault, name, symbol);
    }

    function getRemoteVaultGas(uint32 _eid, address _vault) public view returns (uint128) {
        uint128 _remoteGas = remoteGas[_eid][_vault];
        if (_remoteGas == 0) _remoteGas = DEFAULT_REMOTE_GAS;
        return _remoteGas;
    }

    function setRemoteVaultGas(uint32 _eid, address _vault, uint128 _gas) external onlyOwner {
        if (address(depositToken[_eid][_vault]) == address(0)) revert InvalidVault();
        remoteGas[_eid][_vault] = _gas;
        emit RemoteGasSet(_eid, _vault, _gas);
    }

    function removeDust(uint256 _amountLD) internal view returns (uint256) {
        return (_amountLD / DECIMAL_CONVERSION_RATE) * DECIMAL_CONVERSION_RATE;
    }
}

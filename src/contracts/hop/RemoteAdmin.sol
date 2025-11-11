pragma solidity 0.8.23;

import { IHopComposer } from "src/contracts/hop/interfaces/IHopComposer.sol";

/// @notice Contract to remotely set admin functions on contracts via hops
/// @dev must be authorized as REMOTE_ADMIN_ROLE on target HopV2 contract
contract RemoteAdmin is IHopComposer {
    uint32 internal constant FRAXTAL_EID = 30255;
    
    address public immutable oft;
    address public immutable hopV2;
    bytes32 public immutable fraxtalMsig;

    error NotAuthorized();
    error InvalidSourceEid();
    error InvalidOFT();
    error FailedRemoteCall();

    constructor(address _oft, address _hopV2, address _fraxtalMsig){
        oft = _oft;
        hopV2 = _hopV2;
        fraxtalMsig = bytes32(uint256(uint160(_fraxtalMsig)));
    }

    function hopCompose(uint32 _srcEid, bytes32 _sender, address _oft, uint256 /* _amount */, bytes memory _data) external override {

        // Only allow composes from the hop where the original sender is the fraxtal msig
        if (msg.sender != hopV2 || _sender != fraxtalMsig) {
            revert NotAuthorized();
        }

        if (_srcEid != FRAXTAL_EID) {
            revert InvalidSourceEid();
        }

        if (_oft != oft) {
            revert InvalidOFT();
        }

        (address target, bytes memory data) = abi.decode(_data, (address, bytes));
        (bool success, ) = target.call(data);
        if (!success) revert FailedRemoteCall();
    }
}
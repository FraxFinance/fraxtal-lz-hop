// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { FraxtalStorage } from "src/contracts/FraxtalStorage.sol";

interface ICurve {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
    function get_balances() external view returns (uint256[] memory);
}

contract LZCurveAMO is AccessControlUpgradeable, FraxtalStorage {
    using OptionsBuilder for bytes;

    // keccak256(abi.encode(uint256(keccak256("frax.storage.LZCurveAmoStorage")) - 1));
    bytes32 private constant LZCurveAmoStorageLocation =
        0x34cfa87765bced8684ef975fad48f7c370ba6aca6fca817512efcf044977addf;
    struct LZCurveAmoStorage {
        address ethereumComposer;
    }
    function _getLZCurveAmoStorage() private pure returns (LZCurveAmoStorage storage $) {
        assembly {
            $.slot := LZCurveAmoStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function setEthereumComposer(address _ethereumComposer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        LZCurveAmoStorage storage $ = _getLZCurveAmoStorage();
        $.ethereumComposer = _ethereumComposer;
    }

    // todo: AC
    function exchange(address _oApp, bool _sell, uint256 _amountIn, uint256 _amountOutMin) external {
        (address nToken, address curve) = _getRespectiveTokens(_oApp);

        uint256 amountOut;
        if (_sell) {
            // _sell oft for nToken
            IERC20(_oApp).approve(curve, _amountIn);
            amountOut = ICurve(curve).exchange({ i: int128(1), j: int128(0), _dx: _amountIn, _min_dy: _amountOutMin });
        } else {
            // sell nToken for oft
            IERC20(nToken).approve(curve, _amountIn);
            amountOut = ICurve(curve).exchange({ i: int128(0), j: int128(1), _dx: _amountIn, _min_dy: _amountOutMin });
        }

        // TODO: now what
    }

    // TODO: AC
    function sendToAdapterAndBridgeBackNatively(address _oApp, uint256 _amount) external {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 100_000, 0);
        bytes memory composeMsg = abi.encode(uint256(0));
        SendParam memory sendParam = SendParam({
            dstEid: uint32(30101), // Ethereum
            to: bytes32(uint256(uint160(ethereumComposer()))),
            amountLD: _amount,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }

    // TODO: AC
    function sendToFerry(address _oApp, uint256 _amount) external {}

    function ethereumComposer() public view returns (address) {
        LZCurveAmoStorage storage $ = _getLZCurveAmoStorage();
        return $.ethereumComposer;
    }
}

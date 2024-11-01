// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { FraxtalL2 } from "src/contracts/chain-constants/FraxtalL2.sol";

interface ICurve {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
    function get_balances() external view returns (uint256[] memory);
}

interface IWETH {
    function withdraw(uint256 wad) external;
    function deposit() external payable;
}

contract MockReceiver is IOAppComposer, Initializable {
    error InvalidOApp();
    error FailedEthTransfer();

    // keccak256(abi.encode(uint256(keccak256("frax.storage.MockReceiver")) - 1))
    bytes32 private constant MockReceiverStorageLocation =
        0xcccecfe20bdc879dd2c4066c8efdc75a9ac7e0c7b3cb009c3bfb30c9e281e34d;
    struct MockReceiverStorage {
        address endpoint;
        // Note: each curve pool is "native" token / "layerzero" token with "a" factor of 1400
        // All OFTs can be referenced at https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#proxy-upgradeable-ofts

        address fraxOft;
        address fraxCurve;
        address sFraxOft;
        address sFraxCurve;
        address frxEthOft;
        address frxEthCurve;
        address sFrxEthOft;
        address sFrxEthCurve;
        address fxsOft;
        address fxsCurve;
        address fpiOft;
        address fpiCurve;
    }

    function _getMockReceiverStorage() private pure returns (MockReceiverStorage storage $) {
        assembly {
            $.slot := MockReceiverStorageLocation
        }
    }
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract.
    function initialize(
        address _endpoint,
        address _fraxOft,
        address _sFraxOft,
        address _frxEthOft,
        address _sFrxEthOft,
        address _fxsOft,
        address _fpiOft
    ) external initializer {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        $.endpoint = _endpoint;
        $.fraxOft = _fraxOft;
        $.sFraxOft = _sFraxOft;
        $.frxEthOft = _frxEthOft;
        $.sFrxEthOft = _sFrxEthOft;
        $.fxsOft = _fxsOft;
        $.fpiOft = _fpiOft;
    }

    function initialize2(
        address _fraxCurve,
        address _sFraxCurve,
        address _frxEthCurve,
        address _sFrxEthCurve,
        address _fxsCurve,
        address _fpiCurve
    ) external reinitializer(2) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        $.fraxCurve = _fraxCurve;
        $.sFraxCurve = _sFraxCurve;
        $.frxEthCurve = _frxEthCurve;
        $.sFrxEthCurve = _sFrxEthCurve;
        $.fxsCurve = _fxsCurve;
        $.fpiCurve = _fpiCurve;
    }

    receive() external payable {}

    /// @dev Using the _oApp address (as provided by the endpoint), return the respective tokens
    /// @dev ie. a send of FRAX would have the _oApp address of the FRAX OFT
    /// @return nToken "Native token" (pre-compiled proxy address)
    /// @return curve (Address of curve.fi pool for nToken/lzToken)
    function _getRespectiveTokens(address _oApp) internal view returns (address nToken, address curve) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        if (_oApp == $.fraxOft) {
            nToken = FraxtalL2.FRAX;
            curve = $.fraxCurve;
        } else if (_oApp == $.sFraxOft) {
            nToken = FraxtalL2.SFRAX;
            curve = $.sFraxCurve;
        } else if (_oApp == $.frxEthOft) {
            nToken = FraxtalL2.WFRXETH;
            curve = $.frxEthCurve;
        } else if (_oApp == $.sFrxEthOft) {
            nToken = FraxtalL2.SFRXETH;
            curve = $.sFrxEthCurve;
        } else if (_oApp == $.fxsOft) {
            nToken = FraxtalL2.FXS;
            curve = $.fxsCurve;
        } else if (_oApp == $.fpiOft) {
            nToken = FraxtalL2.FPI;
            curve = $.fpiCurve;
        } else {
            revert InvalidOApp();
        }
    }

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a token swap.
    ///      This method expects the encoded compose message to contain the swap amount and recipient address.
    /// @dev source: https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
    /// @param _oApp The address of the originating OApp.
    /// @param /*_guid*/ The globally unique identifier of the message (unused in this mock).
    /// @param _message The encoded message content in the format of the OFTComposeMsgCodec.
    /// @param /*Executor*/ Executor address (unused in this mock).
    /// @param /*Executor Data*/ Additional data for checking for a specific executor (unused in this mock).
    function lzCompose(
        address _oApp,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*Executor*/,
        bytes calldata /*Executor Data*/
    ) external payable override {
        require(msg.sender == endpoint(), "!endpoint");

        (address nToken, address curve) = _getRespectiveTokens(_oApp);

        // Extract the composed message from the delivered message using the MsgCodec
        (address recipient, uint256 amountOutMin) = abi.decode(
            OFTComposeMsgCodec.composeMsg(_message),
            (address, uint256)
        );
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);

        // try swap
        IERC20(_oApp).approve(curve, amount);
        try ICurve(curve).exchange({ i: int128(1), j: int128(0), _dx: amount, _min_dy: amountOutMin }) returns (
            uint256 amountOut
        ) {
            if (nToken == FraxtalL2.WFRXETH) {
                // unwrap then send
                IWETH(nToken).withdraw(amountOut);
                (bool success, ) = recipient.call{ value: amountOut }("");
                if (!success) revert FailedEthTransfer();
            } else {
                // simple send the now-native token
                IERC20(nToken).transfer(recipient, amountOut);
            }
        } catch {
            // reset approval - swap failed
            IERC20(_oApp).approve(curve, 0);

            // send non-converted OFT to recipient
            IERC20(_oApp).transfer(recipient, amount);
        }
    }

    /// @notice swap native token on curve and send OFT to another chain
    /// @param _oApp Address of the upgradeable OFT
    /// @param _dstEid Destination EID
    /// @param _to  Bytes32 representation of recipient ( ie. for EVM: bytes32(uint256(uint160(addr))) )
    /// @param _amount Amount of OFT to send
    /// @param _minAmountLD Minimum amount allowed to receive after LZ send (includes curve.fi swap slippage)
    function swapAndSend(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amount,
        uint256 _minAmountLD
    ) external payable {
        (address nToken, address curve) = _getRespectiveTokens(_oApp);

        // transfer from sender to here
        uint256 msgValue;
        if (nToken == FraxtalL2.WFRXETH) {
            // wrap amount to swap
            IWETH(nToken).deposit{ value: _amount }();
            // subtract amount wrapped from msg.value (remaining is to be paid through IOFT(_oApp.send()) )
            msgValue = msg.value - _amount;
        } else {
            // Simple token pull
            IERC20(nToken).transferFrom(msg.sender, address(this), _amount);
            msgValue = msg.value;
        }

        // Swap
        IERC20(nToken).approve(curve, _amount);
        /// @dev: can have amountOut as 0 as net slippage is checked via _minAmountLD in _send()
        uint256 amountOut = ICurve(curve).exchange({ i: int128(0), j: int128(1), _dx: _amount, _min_dy: 0 });

        // Send OFT to destination chain
        _send({
            _oApp: _oApp,
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: amountOut,
            _minAmountLD: _minAmountLD,
            _msgValue: msgValue
        });
    }

    function _send(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint256 _msgValue
    ) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _minAmountLD
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        require(_msgValue >= fee.nativeFee);

        // Send the oft
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, payable(msg.sender));

        // refund any extra sent ETH
        if (_msgValue > fee.nativeFee) {
            (bool success, ) = address(msg.sender).call{ value: _msgValue - fee.nativeFee }("");
            if (!success) revert FailedEthTransfer();
        }
    }

    function _generateSendParam(
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) internal pure returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        sendParam.dstEid = _dstEid;
        sendParam.to = _to;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        sendParam.extraOptions = options;
    }

    /// @notice Quote the send cost of ETH required
    function quoteSendNativeFee(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) external view returns (uint256) {
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _minAmountLD
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        return fee.nativeFee;
    }

    /// @notice Estimate how much token is required to rebalance the pool to the desired ratio
    /// @dev Calculated by the delta of current token balance to the balance at the desired ratio
    /// @dev returns (address(0), 0) if the pool is currently within range
    /// @param _oApp Address of OFT
    /// @param _minDesiredPct Minimum desired percent of the pool, with basis points. ie. 4000 means rebalance
    ///                         to a ratio of 40/60
    /// @return tokenIn Address of token to swap into the pool
    /// @return amountIn Amount of token
    function estimateAmountToRebalance(
        address _oApp,
        uint256 _minDesiredPct
    ) external view returns (address tokenIn, uint256 amountIn) {
        (address nToken, address curve) = _getRespectiveTokens(_oApp);
        uint256[] memory balances = ICurve(curve).get_balances();
        (uint256 nBalance, uint256 lzBalance) = (balances[0], balances[1]);
        uint256 totalBalance = nBalance + lzBalance;
        uint256 minDesiredBalance = (totalBalance * _minDesiredPct) / 10_000;

        if (nBalance < minDesiredBalance) {
            tokenIn = nToken;
            amountIn = minDesiredBalance - nBalance;
        } else if (lzBalance < minDesiredBalance) {
            tokenIn = _oApp;
            amountIn = minDesiredBalance - lzBalance;
        } // else returns (address(0), 0)
    }

    function endpoint() public view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.endpoint;
    }

    function fraxOft() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.fraxOft;
    }

    function fraxCurve() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.fraxCurve;
    }

    function sFraxOft() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.sFraxOft;
    }

    function sFraxCurve() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.sFraxCurve;
    }

    function frxEthOft() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.frxEthOft;
    }

    function frxEthCurve() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.frxEthCurve;
    }

    function sFrxEthOft() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.sFrxEthOft;
    }

    function sFrxEthCurve() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.sFrxEthCurve;
    }

    function fxsOft() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.fxsOft;
    }

    function fxsCurve() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.fxsCurve;
    }

    function fpiOft() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.fpiOft;
    }

    function fpiCurve() external view returns (address) {
        MockReceiverStorage storage $ = _getMockReceiverStorage();
        return $.fpiCurve;
    }
}

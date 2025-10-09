## Hop Encoding notes

## Current Conditions

### From src
1a. Sending from src => dst WITH composeMsg
```
composeMsg = abi.encode(
    _to,
    _dstEid,
    _composeGas,
    abi.encode(
        localEID,
        sender,
        _composeMsg
    )
)
```
2a. Sending from src => dst WITHOUT composeMsg
```
composeMsg = abi.encode(
    _to,
    _dstEid,
    _composeGas,
    ""
)
```

### At Fraxtal
1b. Sending from fraxtal => dst WITH composeMsg
```
composeMsg = abi.encode(
    _recipient,
    abi.encode(
        fraxtalEID,
        sender,
        _composeMsg
    )
)
```
2b. Sending from src => fraxtal => dst WITH composeMsg
```
composeMsg = abi.encode(
    _recipient,
    _composeMsg
)
WHERE 
_composeMsg = 1a
```
3b. Sending from src => fraxtal => dst WITH composeMsg FROM non-hop address
```
composeMsg = abi.encode(
    _srcEid,
    composeFrom,
    _composeMsg
)
```

## Conclusion
- There are five different types of encoding of composed messages.
- Source EID sometimes persists as `OFTComposeMsgCodec.srcEid()`, sometimes as encoded `localEID`
- Destination EID sometimes persists as encoded data
- Sender is always encoded in composeMsg, sometimes without composeMsg

## Solution
```
struct HopMessage {
    uint32 srcEid;
    uint32 dstEid;
    uint128 dstGas;
    bytes32 srcSender;
    bytes32 dstAddress;
    bytes data;
}
composeMsg = abi.encode(HopMessage);
```
- Persistent arguments across all hops
- Encoded arguments are packed
- Less arguments in decoding
- Flexible addition of new hop arguments
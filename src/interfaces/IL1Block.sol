// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IL1Block {
    function DEPOSITOR_ACCOUNT() external view returns (address);

    function baseFeeScalar() external view returns (uint32);

    function basefee() external view returns (uint256);

    function batcherHash() external view returns (bytes32);

    function blobBaseFee() external view returns (uint256);

    function blobBaseFeeScalar() external view returns (uint32);

    function hash() external view returns (bytes32);

    function l1FeeOverhead() external view returns (uint256);

    function l1FeeScalar() external view returns (uint256);

    function number() external view returns (uint64);

    function sequenceNumber() external view returns (uint64);

    function setL1BlockValues(
        uint64 _number,
        uint64 _timestamp,
        uint256 _basefee,
        bytes32 _hash,
        uint64 _sequenceNumber,
        bytes32 _batcherHash,
        uint256 _l1FeeOverhead,
        uint256 _l1FeeScalar
    ) external;

    function setL1BlockValuesEcotone() external;

    function timestamp() external view returns (uint64);

    function version() external view returns (string memory);
}

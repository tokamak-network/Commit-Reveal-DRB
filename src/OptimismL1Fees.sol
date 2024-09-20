// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IOVM_GasPriceOracle} from "./interfaces/IOVM_GasPriceOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract OptimismL1Fees is Ownable {
    /// @dev This is the padding size for unsigned RLP-encoded transaction without the signature data
    /// @dev The padding size was estimated based on hypothetical max RLP-encoded transaction size
    uint256 internal constant L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE = 71;
    /// @dev Signature data size used in the GasPriceOracle predeploy
    /// @dev reference: https://github.com/ethereum-optimism/optimism/blob/a96cbe7c8da144d79d4cec1303d8ae60a64e681e/packages/contracts-bedrock/contracts/L2/GasPriceOracle.sol#L145
    uint256 internal constant L1_TX_SIGNATURE_DATA_BYTES_SIZE = 68;
    // /// @dev L1_FEE_DATA_PADDING includes 71 bytes for L1 data padding for Optimism
    // bytes internal constant L1_FEE_DATA_PADDING =
    //     hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    /// @dev OVM_GASPRICEORACLE_ADDR is the address of the OVM_GasPriceOracle precompile on Optimism.
    /// @dev reference: https://community.optimism.io/docs/developers/build/transaction-fees/#estimating-the-l1-data-fee
    address private constant OVM_GASPRICEORACLE_ADDR =
        address(0x420000000000000000000000000000000000000F);
    IOVM_GasPriceOracle internal constant OVM_GASPRICEORACLE =
        IOVM_GasPriceOracle(OVM_GASPRICEORACLE_ADDR);

    // mode
    /// @dev  getL1FeeUpperBound() function from predeploy GasPriceOracle contract (available after Fjord upgrade)
    uint8 internal constant L1_GAS_FEES_UPPER_BOUND_MODE = 0;
    uint8 internal constant L1_GAS_FEES_ECOTONE_MODE = 1;
    uint8 internal constant L1_GAS_FEES_LEGACY_MODE = 2;
    uint8 internal constant NOT_L2 = 3;

    uint8 internal s_l1FeeCalculationMode = 1;

    /// @dev L1 fee coefficient can be applied to options 2 or 3 to reduce possibly inflated gas price
    uint8 internal s_l1FeeCoefficient = 100;

    error InvalidL1FeeCalculationMode(uint8 mode);
    error InvalidL1FeeCoefficient(uint8 coefficient);

    event L1FeeCalculationSet(uint8 mode, uint8 coefficient);

    function setL1FeeCalculation(
        uint8 mode,
        uint8 coefficient
    ) external virtual onlyOwner {
        _setL1FeeCalculationInternal(mode, coefficient);
    }

    function getL1FeeCalculationMode()
        external
        view
        returns (uint8 mode, uint8 coefficient)
    {
        return (s_l1FeeCalculationMode, s_l1FeeCoefficient);
    }

    function _setL1FeeCalculationInternal(
        uint8 mode,
        uint8 coefficient
    ) internal {
        if (mode >= 4) {
            revert InvalidL1FeeCalculationMode(mode);
        }
        if (coefficient == 0 || coefficient > 100) {
            revert InvalidL1FeeCoefficient(coefficient);
        }

        s_l1FeeCalculationMode = mode;
        s_l1FeeCoefficient = coefficient;

        emit L1FeeCalculationSet(mode, coefficient);
    }

    function _getL1CostWeiForCalldataSize(
        uint256 calldataSizeBytes
    ) internal view returns (uint256) {
        uint8 l1FeeCalculationMode = s_l1FeeCalculationMode;
        if (l1FeeCalculationMode == L1_GAS_FEES_ECOTONE_MODE) {
            // estimate based on unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
            return
                _calculateOptimismL1DataFee(
                    calldataSizeBytes + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                );
        } else if (l1FeeCalculationMode == L1_GAS_FEES_UPPER_BOUND_MODE) {
            // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
            return
                OVM_GASPRICEORACLE.getL1FeeUpperBound(
                    calldataSizeBytes + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                );
        } else if (l1FeeCalculationMode == L1_GAS_FEES_LEGACY_MODE)
            return _calculateLegacyL1DataFee(calldataSizeBytes);
        else return 0;
    }

    function _getOptimismL1UpperBoundDataFee(
        uint256 calldataSizeBytes
    ) internal view returns (uint256) {
        // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for padding bytes as well
        return
            (s_l1FeeCoefficient *
                OVM_GASPRICEORACLE.getL1FeeUpperBound(
                    calldataSizeBytes + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                )) / 100;
    }

    function _calculateOptimismL1DataFee(
        uint256 calldataSizeBytes
    ) internal view returns (uint256) {
        // reference: https://docs.optimism.io/stack/transactions/fees#ecotone
        // also: https://github.com/ethereum-optimism/specs/blob/main/specs/protocol/exec-engine.md#ecotone-l1-cost-fee-changes-eip-4844-da
        // we treat all bytes in the calldata payload as non-zero bytes (cost: 16 gas) because accurate estimation is too expensive
        // we also have to account for the signature data size
        uint256 l1GasUsed = (calldataSizeBytes +
            L1_TX_SIGNATURE_DATA_BYTES_SIZE) * 16;
        uint256 scaledBaseFee = OVM_GASPRICEORACLE.baseFeeScalar() *
            16 *
            OVM_GASPRICEORACLE.l1BaseFee();
        uint256 scaledBlobBaseFee = OVM_GASPRICEORACLE.blobBaseFeeScalar() *
            OVM_GASPRICEORACLE.blobBaseFee();
        uint256 fee = l1GasUsed * (scaledBaseFee + scaledBlobBaseFee);
        return
            (s_l1FeeCoefficient *
                (fee / (16 * 10 ** OVM_GASPRICEORACLE.decimals()))) / 100;
    }

    function _calculateLegacyL1DataFee(
        uint256 calldataSizeBytes
    ) internal view returns (uint256) {
        uint256 l1GasUsed = (calldataSizeBytes +
            L1_TX_SIGNATURE_DATA_BYTES_SIZE) *
            16 +
            OVM_GASPRICEORACLE.overhead();
        uint256 l1Fee = l1GasUsed * OVM_GASPRICEORACLE.l1BaseFee();
        uint256 divisor = 10 ** OVM_GASPRICEORACLE.decimals();
        uint256 unscaled = l1Fee * OVM_GASPRICEORACLE.scalar();
        uint256 scaled = unscaled / divisor;
        return scaled;
    }
}

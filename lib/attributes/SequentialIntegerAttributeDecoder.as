// Ported from draco
// compression/attributes/sequential_integer_attribute_decoder.h/.cc
// (bitstream >= 2.2 subset). Entropy-decodes residuals, zigzags back to
// signed, reverts the prediction scheme, then stores native-typed values.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { DataType, dataTypeLength } from "../core/DracoTypes";
import { convertSymbolsToSignedInts } from "../core/BitUtils";
import {
    PredictionSchemeMethod,
    PredictionSchemeTransformType,
} from "../config/CompressionShared";
import { decodeSymbols } from "../entropy/SymbolDecoding";
import { GeometryAttribute } from "./GeometryAttribute";
import { PointAttribute } from "./PointAttribute";
import { SequentialAttributeDecoder } from "./SequentialAttributeDecoder";
import { PredictionSchemeDecoder } from "../prediction/PredictionSchemeDecoder";
import { PredictionSchemeWrapDecodingTransform } from "../prediction/PredictionSchemeWrapDecodingTransform";
import { createPredictionSchemeForDecoderWrap } from "../prediction/CreatePredictionSchemeForDecoder";

export class SequentialIntegerAttributeDecoder extends SequentialAttributeDecoder {
    protected predictionScheme_: PredictionSchemeDecoder? = null;

    transformAttributeToOriginalFormat(pointIds: Int32Array): bool {
        return this.storeValues(pointIds.length);
    }

    decodeValues(pointIds: Int32Array, buffer: DecoderBuffer): bool {
        let predictionSchemeMethod = buffer.decodeInt8();
        if (buffer.err) {
            return false;
        }
        if (predictionSchemeMethod < PredictionSchemeMethod.PREDICTION_NONE ||
            predictionSchemeMethod >= PredictionSchemeMethod.NUM_PREDICTION_SCHEMES) {
            return false;
        }

        if (predictionSchemeMethod != PredictionSchemeMethod.PREDICTION_NONE) {
            let predictionTransformType = buffer.decodeInt8();
            if (buffer.err) {
                return false;
            }
            if (predictionTransformType < PredictionSchemeTransformType.PREDICTION_TRANSFORM_NONE ||
                predictionTransformType >=
                    PredictionSchemeTransformType.NUM_PREDICTION_SCHEME_TRANSFORM_TYPES) {
                return false;
            }
            this.predictionScheme_ = this.createIntPredictionScheme(
                predictionSchemeMethod, predictionTransformType);
        }

        let scheme = this.predictionScheme_;
        if (scheme != null) {
            if (!this.initPredictionScheme(scheme)) {
                return false;
            }
        }

        return this.decodeIntegerValues(pointIds, buffer);
    }

    protected unsafe decodeIntegerValues(pointIds: Int32Array, buffer: DecoderBuffer): bool {
        let numComponents = this.getNumValueComponents();
        if (numComponents <= 0) {
            return false;
        }
        let numEntries = pointIds.length;
        let numValues = numEntries * numComponents;
        this.preparePortableAttribute(numEntries, numComponents);
        let portableAttributeData = this.getPortableAttributeData();
        if (portableAttributeData == null) {
            return false;
        }

        let compressed = buffer.decodeUint8();
        if (buffer.err) {
            return false;
        }

        if (compressed > 0) {
            // decodeSymbols writes uint32 values into the provided view.
            let outUint32 = Uint32Array.wrap(
                portableAttributeData.buffer, portableAttributeData.byteOffset, numValues);
            if (!decodeSymbols(numValues, numComponents, buffer, outUint32)) {
                return false;
            }
        } else {
            // Decode the integer data directly.
            let numBytes = <i32>buffer.decodeUint8();
            if (buffer.err) {
                return false;
            }
            if (numBytes == dataTypeLength(DataType.INT32)) {
                let byteCount = numValues << 2;
                if (buffer.remainingSize() < byteCount) {
                    return false;
                }
                let src = buffer.dataHead();
                memory.copy(portableAttributeData.dataStart, src.dataStart, <usize>byteCount);
                buffer.advance(byteCount);
            } else {
                if (buffer.remainingSize() < numBytes * numValues) {
                    return false;
                }
                for (let i = 0; i < numValues; i++) {
                    // Little-endian assembly into a 32-bit int.
                    let val: u32 = 0;
                    for (let b = 0; b < numBytes; b++) {
                        val |= buffer.decodeUint8() << (b * 8);
                    }
                    if (buffer.err) {
                        return false;
                    }
                    portableAttributeData[i] = <i32>val;
                }
            }
        }

        let scheme = this.predictionScheme_;
        if (numValues > 0 && (scheme == null || !scheme.areCorrectionsPositive())) {
            // Convert the values back to the original signed format.
            let asUint32 = Uint32Array.wrap(
                portableAttributeData.buffer, portableAttributeData.byteOffset, numValues);
            convertSymbolsToSignedInts(asUint32, numValues, portableAttributeData);
        }

        if (scheme != null) {
            if (!scheme.decodePredictionData(buffer)) {
                return false;
            }
            if (numValues > 0) {
                if (!scheme.computeOriginalValues(
                        portableAttributeData, portableAttributeData, numValues,
                        numComponents, pointIds)) {
                    return false;
                }
            }
        }
        return true;
    }

    // Prediction scheme for integer values; subclasses override for others.
    protected createIntPredictionScheme(
        method: i32, transformType: i32): PredictionSchemeDecoder? {
        if (transformType != PredictionSchemeTransformType.PREDICTION_TRANSFORM_WRAP) {
            return null; // For now only the wrap transform is supported here.
        }
        let transform = new PredictionSchemeWrapDecodingTransform();
        return createPredictionSchemeForDecoderWrap(
            method, this.attributeId(), this.decoder(), transform);
    }

    protected getNumValueComponents(): i32 {
        return this.attribute().numComponents;
    }

    // Stores decoded integer values into the attribute in its native type.
    protected storeValues(numValues: i32): bool {
        let dt = this.attribute().dataType;
        if (dt == DataType.UINT8 || dt == DataType.INT8) {
            this.storeTypedValues8(numValues);
        } else if (dt == DataType.UINT16 || dt == DataType.INT16) {
            this.storeTypedValues16(numValues);
        } else if (dt == DataType.UINT32 || dt == DataType.INT32) {
            this.storeTypedValues32(numValues);
        } else {
            return false;
        }
        return true;
    }

    // Truncating int32 stores per output width; sign variants share bytes.
    private unsafe storeTypedValues8(numValues: i32): void {
        let src = this.getPortableAttributeData()!;
        let total = numValues * this.attribute().numComponents;
        let dst = this.attribute().getAddress(0);
        for (let i = 0; i < total; i++) {
            store<u8>(dst.dataStart + <usize>i, <u8>src[i]);
        }
    }

    private unsafe storeTypedValues16(numValues: i32): void {
        let src = this.getPortableAttributeData()!;
        let total = numValues * this.attribute().numComponents;
        let dst = this.attribute().getAddress(0);
        for (let i = 0; i < total; i++) {
            store<u16>(dst.dataStart + (<usize>i << 1), <u16>src[i]);
        }
    }

    private unsafe storeTypedValues32(numValues: i32): void {
        let src = this.getPortableAttributeData()!;
        let total = numValues * this.attribute().numComponents;
        let dst = this.attribute().getAddress(0);
        memory.copy(dst.dataStart, src.dataStart, <usize>total << 2);
    }

    protected preparePortableAttribute(numEntries: i32, numComponents: i32): void {
        let ga = new GeometryAttribute();
        ga.init(
            this.attribute().attributeType, null, numComponents, DataType.INT32,
            false, numComponents * dataTypeLength(DataType.INT32), 0);
        let portAtt = new PointAttribute(ga);
        portAtt.setIdentityMapping();
        portAtt.reset(numEntries);
        portAtt.uniqueId = this.attribute().uniqueId;
        this.setPortableAttribute(portAtt);
    }

    protected getPortableAttributeData(): Int32Array? {
        let portable = this.portableAttribute();
        if (portable == null || portable.size() == 0) {
            return null;
        }
        let addr = portable.getAddress(0);
        return Int32Array.wrap(
            addr.buffer, addr.byteOffset, portable.size() * portable.numComponents);
    }
}

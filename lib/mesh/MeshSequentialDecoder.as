// Ported from draco compression/mesh/mesh_sequential_decoder.h/.cc
// (bitstream >= 2.2). Encoders pick it at compression level 0 and for meshes
// whose vertex order must survive, such as glTF primitives with morph targets.

import { LinearSequencer } from "../attributes/LinearSequencer";
import { SequentialAttributeDecodersController } from "../attributes/SequentialAttributeDecodersController";
import { decodeSymbols } from "../entropy/SymbolDecoding";
import { MeshDecoder } from "./MeshDecoder";

export class MeshSequentialDecoder extends MeshDecoder {
    decodeConnectivity(): bool {
        let buffer = this.buffer();
        let numFaces = buffer.decodeVarintUint32();
        let numPoints = buffer.decodeVarintUint32();
        if (buffer.err) {
            return false;
        }
        // Compressed sequential encoding can only handle (2^32 - 1) / 3
        // indices, and the indices must fit in the remaining bytes.
        if (numFaces > 0xFFFFFFFF / 3 || numFaces > <u32>buffer.remainingSize() / 3 ||
            this.exceedsLimits(numPoints, numFaces)) {
            return false;
        }
        let connectivityMethod = buffer.decodeUint8();
        if (buffer.err) {
            return false;
        }
        let mesh = this.mesh();
        mesh.setNumFaces(<i32>numFaces);
        if (connectivityMethod == 0) {
            if (!this.decodeAndDecompressIndices(numFaces, numPoints)) {
                return false;
            }
        } else {
            // Raw indices, as narrow as the point count allows.
            for (let i = 0; i < <i32>numFaces * 3; i++) {
                let val: u32;
                if (numPoints < 256) {
                    val = buffer.decodeUint8();
                } else if (numPoints < (1 << 16)) {
                    val = buffer.decodeUint16();
                } else if (numPoints < (1 << 21)) {
                    val = buffer.decodeVarintUint32();
                } else {
                    val = buffer.decodeUint32();
                }
                if (buffer.err || val >= numPoints) {
                    return false;
                }
                unchecked(mesh.faces[i] = <i32>val);
            }
        }
        mesh.setNumPoints(<i32>numPoints);
        return true;
    }

    createAttributesDecoder(attDecoderId: i32): bool {
        return this.storeAttributesDecoder(
            attDecoderId,
            new SequentialAttributeDecodersController(
                new LinearSequencer(this.pointCloud().numPoints())));
    }

    // Indices arrive as entropy coded differences from the previous index,
    // the sign in the low bit.
    private decodeAndDecompressIndices(numFaces: u32, numPoints: u32): bool {
        let numIndices = <i32>numFaces * 3;
        let indices = new Uint32Array(numIndices);
        if (!decodeSymbols(numIndices, 1, this.buffer(), indices)) {
            return false;
        }
        let faces = this.mesh().faces;
        let lastIndexValue = 0;
        for (let i = 0; i < numIndices; i++) {
            let encodedVal = unchecked(indices[i]);
            let indexDiff = <i32>(encodedVal >> 1);
            if ((encodedVal & 1) != 0) {
                if (indexDiff > lastIndexValue) {
                    return false;
                }
                indexDiff = -indexDiff;
            } else if (indexDiff > i32.MAX_VALUE - lastIndexValue) {
                return false;
            }
            let indexValue = indexDiff + lastIndexValue;
            if (indexValue < 0 || <u32>indexValue >= numPoints) {
                return false;
            }
            unchecked(faces[i] = indexValue);
            lastIndexValue = indexValue;
        }
        return true;
    }
}

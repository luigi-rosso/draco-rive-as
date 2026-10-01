// Ported from draco compression/decode.h/.cc: header peek + decoder dispatch.
// Only the edgebreaker triangular mesh path is implemented; the other method
// bytes keep their dispatch slots and report a clear unsupported error.

import {
    DracoHeader,
    EncodedGeometryType,
    MeshEncoderMethod,
} from "./config/CompressionShared";
import { DecoderOptions } from "./config/DecoderOptions";
import { DecoderBuffer } from "./core/DecoderBuffer";
import { Status, StatusCode } from "./core/Status";
import { Mesh } from "./mesh/Mesh";
import { MeshDecoder } from "./mesh/MeshDecoder";
import { MeshEdgebreakerDecoder } from "./mesh/MeshEdgebreakerDecoder";
import { PointCloudDecoder, decodeHeader } from "./point_cloud/PointCloudDecoder";

export class DecodeMeshResult {
    mesh: Mesh? = null;
    status: Status = new Status();
}

// Reads the header from a copy that mirrors inBuffer's position, without
// advancing the original.
function peekHeader(inBuffer: DecoderBuffer, outHeader: DracoHeader): Status {
    let tempBuffer = new DecoderBuffer();
    tempBuffer.initView(inBuffer.data(), inBuffer.dataSize, inBuffer.bitstreamVersion);
    tempBuffer.advance(inBuffer.decodedSize());
    return decodeHeader(tempBuffer, outHeader);
}

function createMeshDecoder(method: i32): MeshDecoder? {
    if (method == MeshEncoderMethod.MESH_SEQUENTIAL_ENCODING) {
        return null; // Sequential mesh encoding is not in the ported subset.
    } else if (method == MeshEncoderMethod.MESH_EDGEBREAKER_ENCODING) {
        return new MeshEdgebreakerDecoder();
    }
    return null;
}

export class Decoder {
    private options_: DecoderOptions = new DecoderOptions();

    getEncodedGeometryType(inBuffer: DecoderBuffer): i32 {
        let header = new DracoHeader();
        if (!peekHeader(inBuffer, header).ok()) {
            return EncodedGeometryType.INVALID_GEOMETRY_TYPE;
        }
        if (header.encoderType >= EncodedGeometryType.NUM_ENCODED_GEOMETRY_TYPES) {
            return EncodedGeometryType.INVALID_GEOMETRY_TYPE;
        }
        return header.encoderType;
    }

    decodeMeshFromBuffer(inBuffer: DecoderBuffer): DecodeMeshResult {
        let result = new DecodeMeshResult();
        let mesh = new Mesh();
        result.status = this.decodeBufferToMesh(inBuffer, mesh);
        if (result.status.ok()) {
            result.mesh = mesh;
        }
        return result;
    }

    decodeBufferToMesh(inBuffer: DecoderBuffer, outGeometry: Mesh): Status {
        let header = new DracoHeader();
        let headerStatus = peekHeader(inBuffer, header);
        if (!headerStatus.ok()) {
            return headerStatus;
        }
        if (header.encoderType != EncodedGeometryType.TRIANGULAR_MESH) {
            return new Status(StatusCode.DRACO_ERROR, "Input is not a mesh.");
        }
        let decoder = createMeshDecoder(header.encoderMethod);
        if (decoder == null) {
            return new Status(
                StatusCode.UNSUPPORTED_FEATURE, "Unsupported mesh encoding method.");
        }
        return decoder.decodeMesh(this.options_, inBuffer, outGeometry);
    }

    options(): DecoderOptions {
        return this.options_;
    }
}

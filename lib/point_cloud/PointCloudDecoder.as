// Ported from draco compression/point_cloud/point_cloud_decoder.h/.cc.
// Abstract base for all point cloud / mesh decoders. Extends phase B's
// MeshEdgebreakerDecoderHost so the whole decoder chain satisfies the seam the
// edgebreaker impl pulls its buffer/mesh/attribute registry from (C++ gets the
// same wiring through MeshEdgebreakerDecoder's template plumbing).
//
// The geometry class here is Mesh for both the point cloud and mesh roles;
// this port decodes triangle meshes only.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { Status, StatusCode, okStatus } from "../core/Status";
import { MetadataDecoder } from "../metadata/MetadataDecoder";
import {
    DRACO_BITSTREAM_VERSION,
    DracoHeader,
    EncodedGeometryType,
    METADATA_FLAG_MASK,
    kDracoMeshBitstreamVersionMajor,
    kDracoMeshBitstreamVersionMinor,
    kDracoPointCloudBitstreamVersionMajor,
    kDracoPointCloudBitstreamVersionMinor,
} from "../config/CompressionShared";
import { DecoderOptions } from "../config/DecoderOptions";
import { Mesh } from "../mesh/Mesh";
import { MeshEdgebreakerDecoderHost } from "../mesh/MeshEdgebreakerDecoderHost";
import { CornerTable } from "../mesh/CornerTable";
import { MeshAttributeCornerTable } from "../mesh/MeshAttributeCornerTable";
import { MeshAttributeIndicesEncodingData } from "../mesh/MeshAttributeIndicesEncodingData";
import { PointAttribute } from "../attributes/PointAttribute";
import { AttributesDecoder } from "../attributes/AttributesDecoder";

const kIoErrorMsg = "Failed to parse Draco header.";

// "DRACO" magic bytes.
const MAGIC_D: u32 = 68;
const MAGIC_R: u32 = 82;
const MAGIC_A: u32 = 65;
const MAGIC_C: u32 = 67;
const MAGIC_O: u32 = 79;

// Static header parse (C++ PointCloudDecoder::DecodeHeader). On success
// outHeader is populated.
export function decodeHeader(buffer: DecoderBuffer, outHeader: DracoHeader): Status {
    let bytes = buffer.decodeBytes(5);
    if (bytes == null) {
        return new Status(StatusCode.IO_ERROR, kIoErrorMsg);
    }
    for (let i = 0; i < 5; i++) {
        outHeader.dracoString[i] = <i8>bytes[i];
    }
    if (bytes[0] != MAGIC_D || bytes[1] != MAGIC_R || bytes[2] != MAGIC_A ||
        bytes[3] != MAGIC_C || bytes[4] != MAGIC_O) {
        return new Status(StatusCode.DRACO_ERROR, "Not a Draco file.");
    }
    outHeader.versionMajor = <i32>buffer.decodeUint8();
    if (buffer.err) {
        return new Status(StatusCode.IO_ERROR, kIoErrorMsg);
    }
    outHeader.versionMinor = <i32>buffer.decodeUint8();
    if (buffer.err) {
        return new Status(StatusCode.IO_ERROR, kIoErrorMsg);
    }
    outHeader.encoderType = <i32>buffer.decodeUint8();
    if (buffer.err) {
        return new Status(StatusCode.IO_ERROR, kIoErrorMsg);
    }
    outHeader.encoderMethod = <i32>buffer.decodeUint8();
    if (buffer.err) {
        return new Status(StatusCode.IO_ERROR, kIoErrorMsg);
    }
    outHeader.flags = <i32>buffer.decodeUint16();
    if (buffer.err) {
        return new Status(StatusCode.IO_ERROR, kIoErrorMsg);
    }
    return okStatus();
}

export class PointCloudDecoder extends MeshEdgebreakerDecoderHost {
    protected pointCloud_: Mesh | null = null;
    protected buffer_: DecoderBuffer | null = null;
    protected versionMajor_: i32 = 0;
    protected versionMinor_: i32 = 0;
    protected options_: DecoderOptions | null = null;
    protected attributesDecoders_: Array<AttributesDecoder> = new Array<AttributesDecoder>();
    // Attribute id to attributes-decoder id.
    protected attributeToDecoderMap_: Int32Array = new Int32Array(0);

    getGeometryType(): i32 {
        return EncodedGeometryType.POINT_CLOUD;
    }

    decode(options: DecoderOptions, inBuffer: DecoderBuffer, outPointCloud: Mesh): Status {
        this.options_ = options;
        this.buffer_ = inBuffer;
        this.pointCloud_ = outPointCloud;

        let header = new DracoHeader();
        let headerStatus = decodeHeader(inBuffer, header);
        if (!headerStatus.ok()) {
            return headerStatus;
        }

        if (header.encoderType != this.getGeometryType()) {
            return new Status(
                StatusCode.DRACO_ERROR,
                "Using incompatible decoder for the input geometry.");
        }

        this.versionMajor_ = header.versionMajor;
        this.versionMinor_ = header.versionMinor;

        let isPointCloud = header.encoderType == EncodedGeometryType.POINT_CLOUD;
        let maxSupportedMajorVersion = isPointCloud
            ? kDracoPointCloudBitstreamVersionMajor
            : kDracoMeshBitstreamVersionMajor;
        let maxSupportedMinorVersion = isPointCloud
            ? kDracoPointCloudBitstreamVersionMinor
            : kDracoMeshBitstreamVersionMinor;

        if (this.versionMajor_ < 1 || this.versionMajor_ > maxSupportedMajorVersion) {
            return new Status(StatusCode.UNKNOWN_VERSION, "Unknown major version.");
        }
        if (this.versionMajor_ == maxSupportedMajorVersion &&
            this.versionMinor_ > maxSupportedMinorVersion) {
            return new Status(StatusCode.UNKNOWN_VERSION, "Unknown minor version.");
        }

        inBuffer.bitstreamVersion =
            <i32>DRACO_BITSTREAM_VERSION(<u32>this.versionMajor_, <u32>this.versionMinor_);

        if (header.encoderType == EncodedGeometryType.TRIANGULAR_MESH &&
            <u32>inBuffer.bitstreamVersion < DRACO_BITSTREAM_VERSION(2, 2)) {
            return new Status(
                StatusCode.UNKNOWN_VERSION,
                "Unsupported bitstream version (only Draco 2.2 meshes are supported).");
        }

        if ((header.flags & METADATA_FLAG_MASK) != 0) {
            let metadataDecoder = new MetadataDecoder();
            if (!metadataDecoder.skipGeometryMetadata(inBuffer)) {
                return new Status(StatusCode.DRACO_ERROR, "Failed to decode metadata.");
            }
        }

        if (!this.initializeDecoder()) {
            return new Status(StatusCode.DRACO_ERROR, "Failed to initialize the decoder.");
        }
        if (!this.decodeGeometryData()) {
            return new Status(StatusCode.DRACO_ERROR, "Failed to decode geometry data.");
        }
        if (!this.decodePointAttributes()) {
            return new Status(StatusCode.DRACO_ERROR, "Failed to decode point attributes.");
        }
        return okStatus();
    }

    bitstreamVersion(): i32 {
        return <i32>DRACO_BITSTREAM_VERSION(<u32>this.versionMajor_, <u32>this.versionMinor_);
    }

    // C++ PointCloudDecoder::SetAttributesDecoder. Registration always arrives
    // in id order from decodePointAttributes, so the array grows append-only.
    storeAttributesDecoder(attDecoderId: i32, decoder: AttributesDecoder): bool {
        if (attDecoderId < 0 || attDecoderId > this.attributesDecoders_.length) {
            return false;
        }
        if (attDecoderId == this.attributesDecoders_.length) {
            this.attributesDecoders_.push(decoder);
        } else {
            this.attributesDecoders_[attDecoderId] = decoder;
        }
        return true;
    }

    getPortableAttribute(parentAttId: i32): PointAttribute | null {
        let pc = this.pointCloud_;
        if (pc == null || parentAttId < 0 || parentAttId >= pc.numAttributes()) {
            return null;
        }
        let parentAttDecoderId = this.attributeToDecoderMap_[parentAttId];
        return this.attributesDecoders_[parentAttDecoderId].getPortableAttribute(parentAttId);
    }

    attributesDecoder(decId: i32): AttributesDecoder {
        return this.attributesDecoders_[decId];
    }

    numAttributesDecoders(): i32 {
        return this.attributesDecoders_.length;
    }

    attributesDecoderNumAttributes(decoderId: i32): i32 {
        return this.attributesDecoders_[decoderId].getNumAttributes();
    }

    attributesDecoderAttributeId(decoderId: i32, j: i32): i32 {
        return this.attributesDecoders_[decoderId].getAttributeId(j);
    }

    pointCloud(): Mesh {
        return this.pointCloud_!;
    }

    buffer(): DecoderBuffer {
        return this.buffer_!;
    }

    options(): DecoderOptions | null {
        return this.options_;
    }

    // Virtuals for the prediction scheme factory; the mesh decoders override.
    getCornerTable(): CornerTable | null {
        return null;
    }

    getAttributeCornerTable(attId: i32): MeshAttributeCornerTable | null {
        return null;
    }

    getAttributeEncodingData(attId: i32): MeshAttributeIndicesEncodingData | null {
        return null;
    }

    // Virtuals overridden by subclasses.
    initializeDecoder(): bool {
        return true;
    }

    createAttributesDecoder(attDecoderId: i32): bool {
        return false;
    }

    decodeGeometryData(): bool {
        return true;
    }

    decodePointAttributes(): bool {
        let buffer = this.buffer_!;
        let numAttributesDecoders = <i32>buffer.decodeUint8();
        if (buffer.err) {
            return false;
        }
        for (let i = 0; i < numAttributesDecoders; i++) {
            if (!this.createAttributesDecoder(i)) {
                return false;
            }
        }
        for (let i = 0; i < this.attributesDecoders_.length; i++) {
            if (!this.attributesDecoders_[i].init(this, this.pointCloud_!)) {
                return false;
            }
        }
        for (let i = 0; i < numAttributesDecoders; i++) {
            if (!this.attributesDecoders_[i].decodeAttributesDecoderData(buffer)) {
                return false;
            }
        }

        let pc = this.pointCloud_!;
        let map = new Int32Array(pc.numAttributes());
        for (let i = 0; i < numAttributesDecoders; i++) {
            let numAttributes = this.attributesDecoders_[i].getNumAttributes();
            for (let j = 0; j < numAttributes; j++) {
                let attId = this.attributesDecoders_[i].getAttributeId(j);
                if (attId < 0 || attId >= map.length) {
                    return false;
                }
                map[attId] = i;
            }
        }
        this.attributeToDecoderMap_ = map;

        if (!this.decodeAllAttributes()) {
            return false;
        }
        if (!this.onAttributesDecoded()) {
            return false;
        }
        return true;
    }

    decodeAllAttributes(): bool {
        let buffer = this.buffer_!;
        for (let i = 0; i < this.attributesDecoders_.length; i++) {
            if (!this.attributesDecoders_[i].decodeAttributes(buffer)) {
                return false;
            }
        }
        return true;
    }

    onAttributesDecoded(): bool {
        return true;
    }
}

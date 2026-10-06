// Ported from draco metadata/metadata_decoder.h/.cc. glTF has no use for the
// entries, so this walks the geometry metadata only to step past it, failing
// exactly where canonical draco would.

import { DecoderBuffer } from "../core/DecoderBuffer";
import { IntVector } from "../mesh/IntVector";

const kMaxSubmetadataLevel = 1000;

export class MetadataDecoder {
    // Sub-metadata names per decoded node, since a duplicate name fails.
    private subNames: Array<Set<string>> = new Array<Set<string>>();

    skipGeometryMetadata(buffer: DecoderBuffer): bool {
        let numAttMetadata = buffer.decodeVarintUint32();
        if (buffer.err) {
            return false;
        }
        for (let i: u32 = 0; i < numAttMetadata; i++) {
            buffer.decodeVarintUint32();
            if (buffer.err || !this.skipMetadata(buffer)) {
                return false;
            }
        }
        return this.skipMetadata(buffer);
    }

    private skipMetadata(buffer: DecoderBuffer): bool {
        // Pending nodes as parent node id (-1 for the root) and level.
        let parents = new IntVector();
        let levels = new IntVector();
        parents.push(-1);
        levels.push(0);
        while (parents.size() > 0) {
            let parent = parents.back();
            let level = levels.back();
            parents.popBack();
            levels.popBack();
            if (parent >= 0) {
                if (level > kMaxSubmetadataLevel) {
                    return false;
                }
                let name = this.decodeName(buffer);
                if (name == null) {
                    return false;
                }
                let siblings = this.subNames[parent];
                if (siblings.has(name)) {
                    return false;
                }
                siblings.add(name);
            }
            let node = this.subNames.length;
            this.subNames.push(new Set<string>());

            let numEntries = buffer.decodeVarintUint32();
            if (buffer.err) {
                return false;
            }
            for (let i: u32 = 0; i < numEntries; i++) {
                if (!this.skipEntry(buffer)) {
                    return false;
                }
            }
            let numSubMetadata = buffer.decodeVarintUint32();
            if (buffer.err || numSubMetadata > <u32>buffer.remainingSize()) {
                return false;
            }
            let childLevel = parent >= 0 ? level + 1 : level;
            for (let i: u32 = 0; i < numSubMetadata; i++) {
                parents.push(node);
                levels.push(childLevel);
            }
        }
        return true;
    }

    private skipEntry(buffer: DecoderBuffer): bool {
        if (this.decodeName(buffer) == null) {
            return false;
        }
        let dataSize = buffer.decodeVarintUint32();
        if (buffer.err || dataSize == 0 || dataSize > <u32>buffer.remainingSize()) {
            return false;
        }
        buffer.advance(<i32>dataSize);
        return true;
    }

    // The name's bytes as a string key, or null when the buffer runs out.
    private decodeName(buffer: DecoderBuffer): string? {
        let nameLen = <i32>buffer.decodeUint8();
        if (buffer.err || nameLen > buffer.remainingSize()) {
            return null;
        }
        let name = "";
        for (let i = 0; i < nameLen; i++) {
            name += String.fromCharCode(<i32>buffer.decodeUint8());
        }
        return name;
    }
}

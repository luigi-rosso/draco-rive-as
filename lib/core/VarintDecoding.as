// Ported from draco.js core/VarintDecoding.js (varint_decoding.h). The raw
// LEB128 loop lives on DecoderBuffer (decodeVarintU64) to avoid an import
// cycle; these wrappers keep the Luau module surface:
//
//   decodeVarint(db)        -> decodeVarintUnsigned(db)
//   decodeVarint(db, true)  -> decodeVarintSigned(db)
//
// On error db.err is set and 0 is returned.

import { DecoderBuffer } from "./DecoderBuffer";
import { convertSymbolToSignedInt } from "./BitUtils";

export function decodeVarintUnsigned(db: DecoderBuffer): u64 {
    return db.decodeVarintU64();
}

// Applies zigzag decoding. The zigzag operates on the low 32 bits, matching
// the Luau port's bit32 semantics.
export function decodeVarintSigned(db: DecoderBuffer): i32 {
    let value = db.decodeVarintU64(5);
    if (db.err) {
        return 0;
    }
    return convertSymbolToSignedInt(<u32>value);
}

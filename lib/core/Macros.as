// Ported from draco.js core/Macros.js (macros.h).

// Packs major/minor into a single uint16.
export function bitstreamVersion(major: u32, minor: u32): u32 {
    return ((major & 0xFF) << 8) | (minor & 0xFF);
}

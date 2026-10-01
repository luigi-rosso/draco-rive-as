// Ported from draco.js core/DataBuffer.js (data_buffer.h/cc).
//
// TypedArray#set does not compile under rasc (valueof on the generic source
// type), so byte copies go through memory.copy.

export class DataBuffer {
    private _data: Uint8Array = new Uint8Array(0);

    // `data == null` resizes to size + offset without writing.
    unsafe update(data: Uint8Array?, size: i32, offset: i32 = 0): bool {
        if (data == null) {
            if (size + offset < 0) {
                return false;
            }
            this._resize(size + offset);
        } else {
            if (size < 0) {
                return false;
            }
            if (size + offset > this._data.length) {
                this._resize(size + offset);
            }
            memory.copy(this._data.dataStart + <usize>offset, data.dataStart, <usize>size);
        }
        return true;
    }

    resize(newSize: i32): void {
        this._resize(newSize);
    }

    unsafe write(bytePos: i32, inArray: Uint8Array, dataSize: i32): void {
        memory.copy(this._data.dataStart + <usize>bytePos, inArray.dataStart, <usize>dataSize);
    }

    data(): Uint8Array {
        return this._data;
    }

    dataSize(): i32 {
        return this._data.length;
    }

    private unsafe _resize(newSize: i32): void {
        if (newSize == this._data.length) {
            return;
        }
        let newData = new Uint8Array(newSize);
        let keep = min(this._data.length, newSize);
        memory.copy(newData.dataStart, this._data.dataStart, <usize>keep);
        this._data = newData;
    }
}

// Growable i32 vector standing in for the C++ std::vector<int>/IndexTypeVector
// uses across the mesh decoder (AS typed arrays do not grow on write-past-end).

export class IntVector {
    private _data: Int32Array;
    // Raw element pointer, refreshed on growth; skips a view indirection on
    // every access.
    private _ptr: usize;
    private _size: i32 = 0;

    constructor(capacity: i32 = 0) {
        let data = new Int32Array(capacity > 0 ? capacity : 0);
        this._data = data;
        this._ptr = data.dataStart;
    }

    size(): i32 {
        return this._size;
    }

    // Doubles for push, but a large jump allocates exactly what it asks for.
    private grow(minCapacity: i32): void {
        let cap = max(this._data.length << 1, 8);
        if (cap < minCapacity) {
            cap = minCapacity;
        }
        let grown = new Int32Array(cap);
        grown.set(this._data);
        this._data = grown;
        this._ptr = grown.dataStart;
    }

    reserve(capacity: i32): void {
        if (capacity > this._data.length) {
            this.grow(capacity);
        }
    }

    @inline
    unsafe push(value: i32): void {
        if (this._size == this._data.length) {
            this.grow(this._size + 1);
        }
        store<i32>(this._ptr + (<usize>this._size << 2), value);
        this._size++;
    }

    unsafe get(index: i32): i32 {
        return load<i32>(this._ptr + (<usize>index << 2));
    }

    unsafe set(index: i32, value: i32): void {
        store<i32>(this._ptr + (<usize>index << 2), value);
    }

    unsafe back(): i32 {
        return load<i32>(this._ptr + (<usize>(this._size - 1) << 2));
    }

    unsafe setBack(value: i32): void {
        store<i32>(this._ptr + (<usize>(this._size - 1) << 2), value);
    }

    popBack(): void {
        this._size--;
    }

    clear(): void {
        this._size = 0;
    }

    // std::vector::resize(n, fill): new slots get |fill|, shrink keeps data.
    unsafe resize(newSize: i32, fill: i32 = 0): void {
        if (newSize > this._data.length) {
            this.grow(newSize);
        }
        for (let i = this._size; i < newSize; i++) {
            store<i32>(this._ptr + (<usize>i << 2), fill);
        }
        this._size = newSize;
    }

    // std::vector::assign(n, fill): every slot becomes |fill|.
    assign(newSize: i32, fill: i32): void {
        if (newSize > this._data.length) {
            this.grow(newSize);
        }
        this._data.fill(fill, 0, newSize);
        this._size = newSize;
    }

    // Live view of the current contents; invalidated by growth.
    view(): Int32Array {
        return this._data.subarray(0, this._size);
    }
}

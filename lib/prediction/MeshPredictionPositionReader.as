// The position lookup the tex coord and geometric normal predictors share:
// C++ ConvertValue to int64 of the entry's point, read straight from memory
// for the int32 positions every quantized mesh has.

import { PointAttribute } from "../attributes/PointAttribute";
import { DataType } from "../core/DracoTypes";

export class MeshPredictionPositionReader {
    x: i64 = 0;
    y: i64 = 0;
    z: i64 = 0;
    attribute: PointAttribute? = null;
    entryToPointIdMap: Int32Array = new Int32Array(0);
    private scratch: Float64Array = new Float64Array(3);

    @inline
    unsafe load(entryId: i32): void {
        let att = this.attribute!;
        let attIndex = <i32>att.mappedIndex(this.entryToPointIdMap[entryId]);
        if (att.dataType == DataType.INT32 && att.numComponents >= 3) {
            let p = att.buffer!.data().dataStart +
                <usize>(att.byteOffset + att.byteStride * attIndex);
            this.x = <i64>load<i32>(p);
            this.y = <i64>load<i32>(p, 4);
            this.z = <i64>load<i32>(p, 8);
            return;
        }
        att.convertValue(attIndex, this.scratch);
        this.x = <i64>this.scratch[0];
        this.y = <i64>this.scratch[1];
        this.z = <i64>this.scratch[2];
    }
}

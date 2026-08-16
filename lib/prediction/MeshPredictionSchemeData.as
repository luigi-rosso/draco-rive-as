// Ported from draco prediction_schemes/mesh_prediction_scheme_data.h. The
// CornerTableT template parameter becomes CornerTableBase, covering both the
// C++ instantiations (CornerTable and MeshAttributeCornerTable).

import { CornerTableBase } from "../mesh/CornerTable";
import { IntVector } from "../mesh/IntVector";
import { Mesh } from "../mesh/Mesh";

export class MeshPredictionSchemeData {
    private _mesh: Mesh | null = null;
    private _cornerTable: CornerTableBase | null = null;

    // Mapping between vertices and their encoding order.
    private _vertexToDataMap: Int32Array = new Int32Array(0);

    // Which corner was processed when a given attribute entry was decoded.
    private _dataToCornerMap: IntVector | null = null;

    private _isInitialized: bool = false;

    set(mesh: Mesh, table: CornerTableBase, dataToCornerMap: IntVector,
        vertexToDataMap: Int32Array): void {
        this._mesh = mesh;
        this._cornerTable = table;
        this._dataToCornerMap = dataToCornerMap;
        this._vertexToDataMap = vertexToDataMap;
        this._isInitialized = true;
    }

    mesh(): Mesh {
        return this._mesh!;
    }

    cornerTable(): CornerTableBase {
        return this._cornerTable!;
    }

    vertexToDataMap(): Int32Array {
        return this._vertexToDataMap;
    }

    dataToCornerMap(): IntVector {
        return this._dataToCornerMap!;
    }

    isInitialized(): bool {
        return this._isInitialized;
    }
}

// Minimal connectivity holder for draco mesh/mesh.h: flat face array plus the
// point count, extended in phase C with the PointCloud attribute store
// (point_cloud/point_cloud.h subset) so one class serves both C++ roles.

import { PointAttribute } from "../attributes/PointAttribute";
import { GeometryAttributeType } from "../attributes/GeometryAttribute";

export enum MeshAttributeElementType {
    MESH_VERTEX_ATTRIBUTE = 0,
    MESH_CORNER_ATTRIBUTE = 1,
    MESH_FACE_ATTRIBUTE = 2,
}

export class Mesh {
    // 3 point indices per face; corner index ci maps directly to faces[ci].
    faces: Int32Array = new Int32Array(0);
    private _numFaces: i32 = 0;
    private _numPoints: i32 = 0;

    private _attributes: Array<PointAttribute> = new Array<PointAttribute>();
    // Attribute ids per named type, in registration order.
    private _namedAttributeIndex: Array<Array<i32>> = new Array<Array<i32>>();

    constructor() {
        for (let t = 0; t < GeometryAttributeType.NAMED_ATTRIBUTES_COUNT; t++) {
            this._namedAttributeIndex.push(new Array<i32>());
        }
    }

    numAttributes(): i32 {
        return this._attributes.length;
    }

    attribute(attId: i32): PointAttribute {
        return this._attributes[attId];
    }

    // C++ PointCloud::AddAttribute; ids are sequential.
    addAttribute(pa: PointAttribute): i32 {
        let attId = this._attributes.length;
        if (pa.attributeType >= 0 &&
            pa.attributeType < GeometryAttributeType.NAMED_ATTRIBUTES_COUNT) {
            this._namedAttributeIndex[pa.attributeType].push(attId);
        }
        pa.uniqueId = <u32>attId;
        this._attributes.push(pa);
        return attId;
    }

    numNamedAttributes(type: i32): i32 {
        if (type < 0 || type >= GeometryAttributeType.NAMED_ATTRIBUTES_COUNT) {
            return 0;
        }
        return this._namedAttributeIndex[type].length;
    }

    getNamedAttributeId(type: i32, i: i32 = 0): i32 {
        if (this.numNamedAttributes(type) <= i) {
            return -1;
        }
        return this._namedAttributeIndex[type][i];
    }

    getNamedAttribute(type: i32, i: i32 = 0): PointAttribute | null {
        let attId = this.getNamedAttributeId(type, i);
        if (attId == -1) {
            return null;
        }
        return this._attributes[attId];
    }

    unsafe setNumFaces(numFaces: i32): void {
        if (this.faces.length < numFaces * 3) {
            let grown = new Int32Array(numFaces * 3);
            memory.copy(grown.dataStart, this.faces.dataStart, <usize>this.faces.length << 2);
            this.faces = grown;
        }
        this._numFaces = numFaces;
    }

    numFaces(): i32 {
        return this._numFaces;
    }

    setFace(faceId: i32, v0: i32, v1: i32, v2: i32): void {
        let o = faceId * 3;
        unchecked(this.faces[o] = v0);
        unchecked(this.faces[o + 1] = v1);
        unchecked(this.faces[o + 2] = v2);
    }

    // C++ Mesh::CornerToPointId.
    cornerToPointId(corner: i32): i32 {
        return unchecked(this.faces[corner]);
    }

    setNumPoints(numPoints: i32): void {
        this._numPoints = numPoints;
    }

    numPoints(): i32 {
        return this._numPoints;
    }
}

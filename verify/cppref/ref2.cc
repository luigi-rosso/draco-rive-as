#include "draco/compression/attributes/normal_compression_utils.h"
#include "draco/compression/attributes/prediction_schemes/mesh_prediction_scheme_parallelogram_shared.h"
#include "draco/mesh/corner_table.h"
#include <cstdint>
#include <cstdio>
#include <vector>

using namespace draco;

static void
dumpCornerTable(const char *name,
                const std::vector<std::array<VertexIndex, 3>> &faceList) {
  IndexTypeVector<FaceIndex, CornerTable::FaceType> faces;
  for (auto &f : faceList)
    faces.push_back({{f[0], f[1], f[2]}});
  auto ct = CornerTable::Create(faces);
  if (!ct) {
    printf("CT %s NULL\n", name);
    return;
  }
  printf("CT %s %d %d %d %d %d\n", name, ct->num_vertices(), ct->num_corners(),
         ct->NumDegeneratedFaces(), ct->NumIsolatedVertices(),
         ct->NumNewVertices());
  for (int c = 0; c < ct->num_corners(); ++c) {
    printf("CTC %s %d %d %d\n", name, c, ct->Opposite(CornerIndex(c)).value(),
           ct->Vertex(CornerIndex(c)).value());
  }
  for (int v = 0; v < ct->num_vertices(); ++v) {
    printf("CTV %s %d %d %d %d\n", name, v,
           ct->LeftMostCorner(VertexIndex(v)).value(),
           (int)ct->IsOnBoundary(VertexIndex(v)), ct->Valence(VertexIndex(v)));
  }
  // Parallelogram sweep over this table with synthetic maps.
  int nv = ct->num_vertices();
  std::vector<int32_t> v2d(nv);
  for (int v = 0; v < nv; ++v)
    v2d[v] = v; // identity data map
  std::vector<int32_t> data(nv * 3);
  uint32_t rng = 777;
  for (int i = 0; i < nv * 3; ++i) {
    rng = rng * 1664525u + 1013904223u;
    data[i] = (int32_t)(rng % 2001) - 1000;
  }
  for (int c = 0; c < ct->num_corners(); ++c) {
    int32_t pred[3] = {0, 0, 0};
    // Pretend all entries are decoded (data_entry_id = nv).
    bool ok = ComputeParallelogramPrediction(nv, CornerIndex(c), ct.get(), v2d,
                                             data.data(), 3, pred);
    printf("PP %s %d %d %d %d %d\n", name, c, (int)ok, pred[0], pred[1],
           pred[2]);
  }
}

int main() {
  // Two triangles sharing an edge.
  dumpCornerTable("quad", {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
                           {{VertexIndex(2), VertexIndex(1), VertexIndex(3)}}});
  // Tetrahedron (closed).
  dumpCornerTable("tetra",
                  {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
                   {{VertexIndex(0), VertexIndex(3), VertexIndex(1)}},
                   {{VertexIndex(0), VertexIndex(2), VertexIndex(3)}},
                   {{VertexIndex(1), VertexIndex(3), VertexIndex(2)}}});
  // Fan with boundary + a degenerate face.
  dumpCornerTable("fan", {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
                          {{VertexIndex(0), VertexIndex(2), VertexIndex(3)}},
                          {{VertexIndex(0), VertexIndex(3), VertexIndex(4)}},
                          {{VertexIndex(5), VertexIndex(5), VertexIndex(4)}}});
  // Non-manifold: two fans sharing only vertex 0 (bowtie).
  dumpCornerTable("bowtie",
                  {{{VertexIndex(0), VertexIndex(1), VertexIndex(2)}},
                   {{VertexIndex(0), VertexIndex(3), VertexIndex(4)}}});

  // Octahedron canonicalization sweep (feeds the geometric normal path).
  OctahedronToolBox tb;
  tb.SetQuantizationBits(8);
  uint32_t rng = 42;
  for (int i = 0; i < 512; ++i) {
    rng = rng * 1664525u + 1013904223u;
    int32_t x = (int32_t)(rng % 40001) - 20000;
    rng = rng * 1664525u + 1013904223u;
    int32_t y = (int32_t)(rng % 40001) - 20000;
    rng = rng * 1664525u + 1013904223u;
    int32_t z = (int32_t)(rng % 40001) - 20000;
    int32_t vec[3] = {x, y, z};
    tb.CanonicalizeIntegerVector(vec);
    int32_t s, t;
    tb.IntegerVectorToQuantizedOctahedralCoords(vec, &s, &t);
    printf("CANON %d %d %d %d %d %d %d %d\n", x, y, z, vec[0], vec[1], vec[2],
           s, t);
  }
  return 0;
}

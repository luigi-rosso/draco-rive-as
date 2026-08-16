#include "draco/attributes/point_attribute.h"
#include "draco/compression/attributes/prediction_schemes/mesh_prediction_scheme_data.h"
#include "draco/compression/attributes/prediction_schemes/mesh_prediction_scheme_geometric_normal_predictor_area.h"
#include "draco/compression/attributes/prediction_schemes/mesh_prediction_scheme_tex_coords_portable_predictor.h"
#include "draco/compression/attributes/prediction_schemes/prediction_scheme_normal_octahedron_canonicalized_decoding_transform.h"
#include "draco/mesh/corner_table.h"
#include <cstdint>
#include <cstdio>
#include <vector>

using namespace draco;

typedef MeshPredictionSchemeData<CornerTable> MD;
typedef PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform<int32_t>
    TR;

static std::unique_ptr<CornerTable>
makeCT(const std::vector<std::array<uint32_t, 3>> &faceList) {
  IndexTypeVector<FaceIndex, CornerTable::FaceType> faces;
  for (auto &f : faceList)
    faces.push_back(
        {{VertexIndex(f[0]), VertexIndex(f[1]), VertexIndex(f[2])}});
  return CornerTable::Create(faces);
}

static uint32_t lcg(uint32_t &r) {
  r = r * 1664525u + 1013904223u;
  return r;
}

static void runMesh(const char *name,
                    const std::vector<std::array<uint32_t, 3>> &faceList) {
  auto ct = makeCT(faceList);
  int nv = ct->num_vertices();

  // Position attribute: identity mapping, INT32 x3, LCG seed 333.
  PointAttribute pa;
  pa.Init(GeometryAttribute::POSITION, 3, DT_INT32, false, nv);
  uint32_t rng = 333;
  for (int i = 0; i < nv; ++i) {
    int32_t pos[3];
    for (int c = 0; c < 3; ++c)
      pos[c] = (int32_t)(lcg(rng) % 1024);
    pa.SetAttributeValue(AttributeValueIndex(i), pos);
  }

  std::vector<int32_t> v2d(nv);
  std::vector<CornerIndex> d2c(nv);
  std::vector<PointIndex> e2p(nv);
  for (int i = 0; i < nv; ++i) {
    v2d[i] = i;
    d2c[i] = ct->LeftMostCorner(VertexIndex(i));
    e2p[i] = PointIndex(i);
  }

  MD md;
  md.Set(nullptr, ct.get(), &d2c, &v2d);

  // UV data, LCG seed 555.
  std::vector<int32_t> uv(nv * 2);
  rng = 555;
  for (int i = 0; i < nv * 2; ++i)
    uv[i] = (int32_t)(lcg(rng) % 1024);

  MeshPredictionSchemeTexCoordsPortablePredictor<int32_t, MD> pred(md);
  pred.SetPositionAttribute(pa);
  pred.SetEntryToPointIdMap(e2p.data());
  // Orientations, LCG seed 999.
  pred.ResizeOrientations(nv);
  rng = 999;
  for (int i = 0; i < nv; ++i)
    pred.set_orientation(i, ((lcg(rng) >> 16) & 1) != 0);

  for (int d = 0; d < nv; ++d) {
    bool ok = pred.ComputePredictedValue<false>(d2c[d], uv.data(), d);
    printf("TEX %s %d %d %d %d\n", name, d, (int)ok, pred.predicted_value()[0],
           pred.predicted_value()[1]);
  }

  // Geometric normal predictor area over the same table/positions.
  MeshPredictionSchemeGeometricNormalPredictorArea<int32_t, TR, MD> gnp(md);
  gnp.SetPositionAttribute(pa);
  gnp.SetEntryToPointIdMap(e2p.data());
  for (int d = 0; d < nv; ++d) {
    int32_t p[3];
    gnp.ComputePredictedValue(d2c[d], p);
    printf("GN %s %d %d %d %d\n", name, d, p[0], p[1], p[2]);
  }
}

int main() {
  runMesh("strip",
          {{0, 1, 2}, {2, 1, 3}, {2, 3, 4}, {4, 3, 5}, {4, 5, 6}, {6, 5, 7}});
  runMesh("tetra", {{0, 1, 2}, {0, 3, 1}, {0, 2, 3}, {1, 3, 2}});
  runMesh("fan", {{0, 1, 2}, {0, 2, 3}, {0, 3, 4}});
  return 0;
}

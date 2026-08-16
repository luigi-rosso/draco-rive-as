#include "draco/compression/attributes/normal_compression_utils.h"
#include "draco/compression/attributes/prediction_schemes/prediction_scheme_normal_octahedron_canonicalized_decoding_transform.h"
#include <cstdint>
#include <cstdio>

using namespace draco;

struct T
    : PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform<int32_t> {
  bool setup(int32_t maxq) { return this->set_max_quantized_value(maxq); }
};

int main() {
  // Sweep: qbits in {4, 8}, structured + pseudo random (pred, corr) pairs.
  for (int qb = 4; qb <= 8; qb += 4) {
    T t;
    int32_t maxq = (1 << qb) - 1;
    if (!t.setup(maxq)) {
      printf("SETUP_FAIL %d\n", qb);
      return 1;
    }
    uint32_t rng = 12345;
    int32_t maxcoord = 2 * t.center_value();
    for (int i = 0; i < 512; ++i) {
      rng = rng * 1664525u + 1013904223u;
      int32_t px = (rng >> 8) % (maxcoord + 1);
      rng = rng * 1664525u + 1013904223u;
      int32_t py = (rng >> 8) % (maxcoord + 1);
      rng = rng * 1664525u + 1013904223u;
      int32_t cx = (rng >> 8) % (maxcoord + 1);
      rng = rng * 1664525u + 1013904223u;
      int32_t cy = (rng >> 8) % (maxcoord + 1);
      int32_t pred[2] = {px, py};
      int32_t corr[2] = {cx, cy};
      int32_t out[2];
      t.ComputeOriginalValue(pred, corr, out);
      printf("%d %d %d %d %d %d %d\n", qb, px, py, cx, cy, out[0], out[1]);
    }
  }
  // OctahedronToolBox helper sweep: ModMax / IsInDiamond / InvertDiamond.
  OctahedronToolBox tb;
  tb.SetQuantizationBits(4);
  for (int s = -tb.center_value(); s <= tb.center_value(); ++s) {
    for (int u = -tb.center_value(); u <= tb.center_value(); ++u) {
      int32_t is = s, it = u;
      bool ind = tb.IsInDiamond(is, it);
      int32_t ds = s, dt = u;
      tb.InvertDiamond(&ds, &dt);
      printf("TB %d %d %d %d %d %d\n", s, u, (int)ind, ds, dt,
             tb.ModMax(s + u));
    }
  }
  return 0;
}

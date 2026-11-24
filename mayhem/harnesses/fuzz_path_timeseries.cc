// fuzz_path_timeseries: the input is a ground-motion / load-history text file, read by OpenSees'
// `timeSeries Path` file readers (PathSeries -filePath with -dt, PathTimeSeries -fileTime/-filePath)
// and then used as the load factor of a small static truss analysis.
#include "opensees_fuzz_common.h"

static const char kScript[] =
    "model basic -ndm 2 -ndf 2\n"
    "node 1 0.0 0.0\n"
    "node 2 1.0 0.0\n"
    "fix 1 1 1\n"
    "fix 2 0 1\n"
    "uniaxialMaterial Elastic 1 100.0\n"
    "element truss 1 1 2 1.0 1\n"
    "timeSeries Path 1 -dt 0.1 -filePath series.txt -factor 2.0\n"
    "timeSeries Path 2 -fileTime series.txt -filePath series.txt\n"
    "timeSeries Path 3 -dt 0.1 -filePath series.txt -useLast -prependZero\n"
    "pattern Plain 1 1 { load 2 1.0 0.0 }\n"
    "pattern Plain 2 2 { load 2 0.5 0.0 }\n"
    "pattern Plain 3 3 { load 2 0.25 0.0 }\n"
    "constraints Plain\n"
    "numberer Plain\n"
    "system BandGeneral\n"
    "test NormDispIncr 1.0e-8 10\n"
    "algorithm Newton\n"
    "integrator LoadControl 0.05\n"
    "analysis Static\n"
    "analyze 10\n";

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  Tcl_Interp *interp = ops_fuzz_new_interp();
  ops_fuzz_write_file("series.txt", data, size);
  Tcl_Eval(interp, kScript);
  ops_fuzz_free_interp(interp);
  return 0;
}

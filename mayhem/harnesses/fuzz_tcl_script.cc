// fuzz_tcl_script: the input is an OpenSees Tcl model/analysis script, evaluated the way the
// `OpenSees` interpreter evaluates a script file (Tcl_EvalEx in the global frame). Reaches every
// model-builder command (materials, sections, elements, patterns, time series) and the analysis
// stack (constraints, numberers, systems of equations, algorithms, integrators).
#include "opensees_fuzz_common.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  Tcl_Interp *interp = ops_fuzz_new_interp();
  Tcl_EvalEx(interp, reinterpret_cast<const char *>(data), (int)size, TCL_EVAL_GLOBAL);
  ops_fuzz_free_interp(interp);
  return 0;
}

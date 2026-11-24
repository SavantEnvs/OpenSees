// fuzz_uniaxial_material: one `uniaxialMaterial` definition driven through a strain history with
// OpenSees' own material tester (`model testUniaxial`, SRC/modelbuilder/tcl/TclUniaxialMaterialTester).
// Input: the first line is the argument list of `uniaxialMaterial` (e.g. `HystereticSM 1 ...`),
// passed word by word as a Tcl list, so no Tcl substitution happens; every following line is one
// trial strain, applied with `strainUniaxialTest` and read back with `stressUniaxialTest` and
// `tangUniaxialTest`.
#include "opensees_fuzz_common.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  std::string in(reinterpret_cast<const char *>(data), size);
  size_t nl = in.find('\n');
  std::string args = in.substr(0, nl);
  std::string rest = nl == std::string::npos ? "" : in.substr(nl + 1);

  Tcl_Interp *interp = ops_fuzz_new_interp();
  if (Tcl_Eval(interp, "model testUniaxial") != TCL_OK) abort();

  // Split the definition on blanks into words.
  Tcl_Obj *cmd = Tcl_NewListObj(0, nullptr);
  Tcl_IncrRefCount(cmd);
  Tcl_ListObjAppendElement(interp, cmd, Tcl_NewStringObj("uniaxialMaterial", -1));
  std::string tag;
  size_t i = 0;
  int word = 0;
  while (i < args.size()) {
    while (i < args.size() && (args[i] == ' ' || args[i] == '\t' || args[i] == '\r')) i++;
    size_t j = i;
    while (j < args.size() && args[j] != ' ' && args[j] != '\t' && args[j] != '\r') j++;
    if (j > i) {
      std::string w = args.substr(i, j - i);
      if (word == 1) tag = w;
      Tcl_ListObjAppendElement(interp, cmd, Tcl_NewStringObj(w.data(), (int)w.size()));
      word++;
    }
    i = j;
  }
  int objc = 0;
  Tcl_Obj **objv = nullptr;
  Tcl_ListObjGetElements(interp, cmd, &objc, &objv);
  if (Tcl_EvalObjv(interp, objc, objv, TCL_EVAL_GLOBAL) == TCL_OK && !tag.empty()) {
    Tcl_Obj *sel[2] = {Tcl_NewStringObj("uniaxialTest", -1), Tcl_NewStringObj(tag.data(), (int)tag.size())};
    for (Tcl_Obj *o : sel) Tcl_IncrRefCount(o);
    if (Tcl_EvalObjv(interp, 2, sel, TCL_EVAL_GLOBAL) == TCL_OK) {
      size_t p = 0;
      while (p < rest.size()) {
        size_t e = rest.find('\n', p);
        if (e == std::string::npos) e = rest.size();
        std::string s = rest.substr(p, e - p);
        p = e + 1;
        Tcl_Obj *st[2] = {Tcl_NewStringObj("strainUniaxialTest", -1), Tcl_NewStringObj(s.data(), (int)s.size())};
        for (Tcl_Obj *o : st) Tcl_IncrRefCount(o);
        int rc = Tcl_EvalObjv(interp, 2, st, TCL_EVAL_GLOBAL);
        for (Tcl_Obj *o : st) Tcl_DecrRefCount(o);
        if (rc != TCL_OK) continue;
        Tcl_Eval(interp, "stressUniaxialTest");
        Tcl_Eval(interp, "tangUniaxialTest");
      }
    }
    for (Tcl_Obj *o : sel) Tcl_DecrRefCount(o);
  }
  Tcl_DecrRefCount(cmd);
  ops_fuzz_free_interp(interp);
  return 0;
}

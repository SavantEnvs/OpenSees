// Shared setup for the OpenSees Tcl-driven fuzz harnesses.
//
// Every input gets a FRESH Tcl interpreter with OpenSees' commands registered by upstream's own
// OpenSeesAppInit() (SRC/tcl/commands.cpp, the same call tclAppInit.cpp makes), and ends with
// OpenSees' `wipe`, which clears the global domain/model builder/analysis objects, before the
// interpreter is deleted (plus `wipeReliability`). So no model state survives from one input to the next.
//
// Sandbox (allow-list): only the pure-computation Tcl core commands below survive, plus every
// OpenSees command except those that touch the file system, the process, the network or the
// clock. The process cwd is a private scratch dir (made once, under $TMPDIR), so relative paths an
// input reads stay inside it. Kept across inputs on purpose: the scratch dir (each harness rewrites
// its own data file before every eval) and Tcl's per-process library state.
#pragma once
extern "C" {
#include <tcl.h>
}
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <set>
#include <string>
// Upstream entry point (SRC/tcl/commands.h:41); commands.h itself needs the whole OpenSees include tree.
int OpenSeesAppInit(Tcl_Interp *interp);

// tclMain.cpp (linked for g3TclMain's helpers) declares Tcl_AppInit; tclAppInit.cpp, which holds
// main(), is not linked into the harnesses.
int Tcl_AppInit(Tcl_Interp *interp) { return OpenSeesAppInit(interp) < 0 ? TCL_ERROR : TCL_OK; }

static const char *kCoreAllowed[] = {
    "set", "unset", "expr", "if", "for", "foreach", "while", "proc", "return", "list", "lindex",
    "llength", "lappend", "lrange", "lsearch", "lsort", "lreplace", "linsert", "lassign", "lrepeat",
    "lreverse", "lset", "lmap", "string", "append", "incr", "array", "dict", "break", "continue",
    "catch", "error", "format", "scan", "split", "join", "concat", "regexp", "regsub", "switch",
    "upvar", "uplevel", "global", "variable", "eval", "subst", "apply", "try", "throw", "puts",
    "binary", "info", "tailcall", "namespace", nullptr};

// OpenSees commands that write/read arbitrary paths, end the process, talk to peers or read the clock.
static const char *kOpenSeesDenied[] = {
    "exit", "quit", "source", "recorder", "logFile", "database", "save", "restore", "video",
    "printA", "printB", "print", "printGID", "printModel", "stripXML", "convertBinaryToText",
    "convertTextToBinary", "searchPeerNGA", "send", "recv", "barrier", "partition", "start", "stop",
    "getTime", "setMaxOpenFiles", "exec", "loadPackage", "defaultUnits", "setTime", nullptr};

static void ops_fuzz_chdir_scratch() {
  static bool done = false;
  if (done) return;
  done = true;
  const char *tmp = getenv("TMPDIR");
  std::string tmpl = std::string(tmp && *tmp ? tmp : "/tmp") + "/opensees-fuzz-XXXXXX";
  char *dir = mkdtemp(&tmpl[0]);
  if (!dir || chdir(dir) != 0) { perror("opensees fuzz scratch dir"); abort(); }
}

static std::set<std::string> ops_fuzz_commands(Tcl_Interp *interp) {
  std::set<std::string> out;
  if (Tcl_Eval(interp, "info commands") != TCL_OK) abort();
  Tcl_Obj *res = Tcl_GetObjResult(interp);
  int n = 0;
  Tcl_Obj **items = nullptr;
  if (Tcl_ListObjGetElements(interp, res, &n, &items) != TCL_OK) abort();
  for (int i = 0; i < n; i++) out.insert(Tcl_GetString(items[i]));
  return out;
}

// A sandboxed interpreter with OpenSees loaded.
static Tcl_Interp *ops_fuzz_new_interp() {
  ops_fuzz_chdir_scratch();
  Tcl_Interp *interp = Tcl_CreateInterp();
  std::set<std::string> core = ops_fuzz_commands(interp);
  if (OpenSeesAppInit(interp) < 0) abort();
  std::set<std::string> all = ops_fuzz_commands(interp);
  std::set<std::string> keep;
  for (const char **c = kCoreAllowed; *c; c++) keep.insert(*c);
  std::set<std::string> deny;
  for (const char **c = kOpenSeesDenied; *c; c++) deny.insert(*c);
  for (const std::string &cmd : all) {
    bool from_core = core.count(cmd) && !keep.count(cmd);
    if (from_core || deny.count(cmd)) Tcl_DeleteCommand(interp, cmd.c_str());
  }
  // `unknown` must not exist either (it would auto-load/exec); it is a core proc only after Tcl_Init,
  // which is never called here.
  Tcl_DeleteCommand(interp, "unknown");
  return interp;
}

static void ops_fuzz_free_interp(Tcl_Interp *interp) {
  Tcl_Eval(interp, "wipe");
  // Reliability objects (random variables, limit-state functions, GFun evaluators) are global too
  // and `wipe` does not clear them.
  Tcl_Eval(interp, "wipeReliability");
  Tcl_DeleteInterp(interp);
}

static void ops_fuzz_write_file(const char *name, const uint8_t *data, size_t size) {
  FILE *f = fopen(name, "wb");
  if (!f) { perror(name); abort(); }
  if (size && fwrite(data, 1, size, f) != size) abort();
  fclose(f);
}

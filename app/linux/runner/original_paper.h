#ifndef RUNNER_ORIGINAL_PAPER_H_
#define RUNNER_ORIGINAL_PAPER_H_

#include <flutter_linux/flutter_linux.h>

// The original layout of an email, in WebKitGTK over the Flutter view.
// Flutter on Linux has no web view of its own, so the app places one on
// top of the paper's rectangle, clipped to what of it shows.
void original_paper_register(FlPluginRegistrar* registrar);

#endif  // RUNNER_ORIGINAL_PAPER_H_

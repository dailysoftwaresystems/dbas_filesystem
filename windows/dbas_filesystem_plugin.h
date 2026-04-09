#ifndef FLUTTER_PLUGIN_DBAS_FILESYSTEM_PLUGIN_H_
#define FLUTTER_PLUGIN_DBAS_FILESYSTEM_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

namespace dbas_filesystem {

class DbasFilesystemPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DbasFilesystemPlugin();
  virtual ~DbasFilesystemPlugin();

  DbasFilesystemPlugin(const DbasFilesystemPlugin&) = delete;
  DbasFilesystemPlugin& operator=(const DbasFilesystemPlugin&) = delete;
};

}  // namespace dbas_filesystem

#endif  // FLUTTER_PLUGIN_DBAS_FILESYSTEM_PLUGIN_H_

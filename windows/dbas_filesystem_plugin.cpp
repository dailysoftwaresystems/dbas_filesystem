#include "dbas_filesystem_plugin.h"

namespace dbas_filesystem {

void DbasFilesystemPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<DbasFilesystemPlugin>();
  registrar->AddPlugin(std::move(plugin));
}

DbasFilesystemPlugin::DbasFilesystemPlugin() {}

DbasFilesystemPlugin::~DbasFilesystemPlugin() {}

}  // namespace dbas_filesystem

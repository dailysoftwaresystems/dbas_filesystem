#include "include/dbas_filesystem/dbas_filesystem_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "dbas_filesystem_plugin.h"

void DbasFilesystemPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  dbas_filesystem::DbasFilesystemPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

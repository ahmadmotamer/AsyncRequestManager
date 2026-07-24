#include "include/async_request_manager/async_request_manager_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "async_request_manager_plugin.h"

void AsyncRequestManagerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  async_request_manager::AsyncRequestManagerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

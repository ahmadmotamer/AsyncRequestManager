#ifndef FLUTTER_PLUGIN_ASYNC_REQUEST_MANAGER_PLUGIN_H_
#define FLUTTER_PLUGIN_ASYNC_REQUEST_MANAGER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace async_request_manager {

class AsyncRequestManagerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  AsyncRequestManagerPlugin();
  virtual ~AsyncRequestManagerPlugin();

  AsyncRequestManagerPlugin(const AsyncRequestManagerPlugin&) = delete;
  AsyncRequestManagerPlugin& operator=(const AsyncRequestManagerPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace async_request_manager

#endif  // FLUTTER_PLUGIN_ASYNC_REQUEST_MANAGER_PLUGIN_H_

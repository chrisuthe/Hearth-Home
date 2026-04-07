#ifndef SENDSPIN_AUDIO_PLUGIN_H_
#define SENDSPIN_AUDIO_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <audioclient.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>

#include <memory>
#include <vector>

class SendspinAudioPlugin {
 public:
  // Registers the method channel on the given messenger.
  // The plugin instance is kept alive by the closure captured in the handler.
  static void Register(flutter::BinaryMessenger* messenger);

  SendspinAudioPlugin();
  ~SendspinAudioPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Initialize(
      int sample_rate, int channels, int bit_depth,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Start(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Stop(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void WriteSamples(
      const std::vector<uint8_t>& data,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetVolume(
      double volume,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetMuted(
      bool muted,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Dispose(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Cleanup();

  IMMDeviceEnumerator* device_enumerator_ = nullptr;
  IMMDevice* device_ = nullptr;
  IAudioClient* audio_client_ = nullptr;
  IAudioRenderClient* render_client_ = nullptr;
  ISimpleAudioVolume* volume_control_ = nullptr;
  UINT32 buffer_frame_count_ = 0;
  int channels_ = 0;
  int bit_depth_ = 0;
  bool is_started_ = false;
};

#endif  // SENDSPIN_AUDIO_PLUGIN_H_

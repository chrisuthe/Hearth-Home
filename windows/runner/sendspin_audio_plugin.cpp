#include "sendspin_audio_plugin.h"

#include <flutter/encodable_value.h>

#include <cstring>
#include <string>

// Helper to format HRESULT as a hex string for error messages.
static std::string HResultToString(HRESULT hr) {
  char buf[32];
  snprintf(buf, sizeof(buf), "0x%08lX", static_cast<unsigned long>(hr));
  return std::string(buf);
}

// Static instance kept alive for the lifetime of the engine.
static std::unique_ptr<SendspinAudioPlugin> g_plugin_instance;
static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_channel;

void SendspinAudioPlugin::Register(flutter::BinaryMessenger* messenger) {
  g_plugin_instance = std::make_unique<SendspinAudioPlugin>();

  g_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.hearth/sendspin_audio",
          &flutter::StandardMethodCodec::GetInstance());

  SendspinAudioPlugin* plugin_ptr = g_plugin_instance.get();
  g_channel->SetMethodCallHandler(
      [plugin_ptr](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });
}

SendspinAudioPlugin::SendspinAudioPlugin() {}

SendspinAudioPlugin::~SendspinAudioPlugin() { Cleanup(); }

void SendspinAudioPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "initialize") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected a map argument");
      return;
    }
    auto sr_it = args->find(flutter::EncodableValue("sampleRate"));
    auto ch_it = args->find(flutter::EncodableValue("channels"));
    auto bd_it = args->find(flutter::EncodableValue("bitDepth"));
    if (sr_it == args->end() || ch_it == args->end() ||
        bd_it == args->end()) {
      result->Error("INVALID_ARGS",
                    "Missing sampleRate, channels, or bitDepth");
      return;
    }
    int sample_rate = std::get<int>(sr_it->second);
    int channels = std::get<int>(ch_it->second);
    int bit_depth = std::get<int>(bd_it->second);
    Initialize(sample_rate, channels, bit_depth, std::move(result));
  } else if (method == "start") {
    Start(std::move(result));
  } else if (method == "stop") {
    Stop(std::move(result));
  } else if (method == "writeSamples") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected a map argument");
      return;
    }
    auto data_it = args->find(flutter::EncodableValue("data"));
    if (data_it == args->end()) {
      result->Error("INVALID_ARGS", "Missing 'data' key");
      return;
    }
    const auto* data = std::get_if<std::vector<uint8_t>>(&data_it->second);
    if (!data) {
      result->Error("INVALID_ARGS", "'data' must be a Uint8List");
      return;
    }
    WriteSamples(*data, std::move(result));
  } else if (method == "setVolume") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected a map argument");
      return;
    }
    auto vol_it = args->find(flutter::EncodableValue("volume"));
    if (vol_it == args->end()) {
      result->Error("INVALID_ARGS", "Missing 'volume' key");
      return;
    }
    double volume = std::get<double>(vol_it->second);
    SetVolume(volume, std::move(result));
  } else if (method == "setMuted") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected a map argument");
      return;
    }
    auto muted_it = args->find(flutter::EncodableValue("muted"));
    if (muted_it == args->end()) {
      result->Error("INVALID_ARGS", "Missing 'muted' key");
      return;
    }
    bool muted = std::get<bool>(muted_it->second);
    SetMuted(muted, std::move(result));
  } else if (method == "dispose") {
    Dispose(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void SendspinAudioPlugin::Initialize(
    int sample_rate, int channels, int bit_depth,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Clean up any previous session.
  Cleanup();

  channels_ = channels;
  bit_depth_ = bit_depth;

  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&device_enumerator_));
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "CoCreateInstance MMDeviceEnumerator failed: " +
                      HResultToString(hr));
    return;
  }

  hr = device_enumerator_->GetDefaultAudioEndpoint(eRender, eConsole,
                                                    &device_);
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "GetDefaultAudioEndpoint failed: " + HResultToString(hr));
    Cleanup();
    return;
  }

  hr = device_->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(&audio_client_));
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "IMMDevice::Activate failed: " + HResultToString(hr));
    Cleanup();
    return;
  }

  // Build the desired wave format.
  WAVEFORMATEX wfx = {};
  wfx.wFormatTag = WAVE_FORMAT_PCM;
  wfx.nChannels = static_cast<WORD>(channels);
  wfx.nSamplesPerSec = static_cast<DWORD>(sample_rate);
  wfx.wBitsPerSample = static_cast<WORD>(bit_depth);
  wfx.nBlockAlign =
      static_cast<WORD>((channels * bit_depth) / 8);
  wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;
  wfx.cbSize = 0;

  // Check if the format is supported in shared mode.
  WAVEFORMATEX* closest = nullptr;
  hr = audio_client_->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &wfx,
                                        &closest);
  if (closest) {
    CoTaskMemFree(closest);
    closest = nullptr;
  }

  // If the exact format isn't supported, fall back to the device mix format.
  WAVEFORMATEX* mix_format = nullptr;
  if (hr != S_OK) {
    hr = audio_client_->GetMixFormat(&mix_format);
    if (FAILED(hr)) {
      result->Error("WASAPI_ERROR",
                    "GetMixFormat failed: " + HResultToString(hr));
      Cleanup();
      return;
    }
  }

  const WAVEFORMATEX* format_to_use = mix_format ? mix_format : &wfx;

  // Update our tracking to match what we actually opened.
  if (mix_format) {
    channels_ = mix_format->nChannels;
    bit_depth_ = mix_format->wBitsPerSample;
  }

  // 200ms buffer duration in 100-ns units.
  REFERENCE_TIME buffer_duration = 2000000;

  hr = audio_client_->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, buffer_duration,
                                 0, format_to_use, nullptr);
  if (mix_format) {
    CoTaskMemFree(mix_format);
    mix_format = nullptr;
  }
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "IAudioClient::Initialize failed: " + HResultToString(hr));
    Cleanup();
    return;
  }

  hr = audio_client_->GetBufferSize(&buffer_frame_count_);
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "GetBufferSize failed: " + HResultToString(hr));
    Cleanup();
    return;
  }

  hr = audio_client_->GetService(__uuidof(IAudioRenderClient),
                                 reinterpret_cast<void**>(&render_client_));
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "GetService IAudioRenderClient failed: " +
                      HResultToString(hr));
    Cleanup();
    return;
  }

  hr = audio_client_->GetService(__uuidof(ISimpleAudioVolume),
                                 reinterpret_cast<void**>(&volume_control_));
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "GetService ISimpleAudioVolume failed: " +
                      HResultToString(hr));
    Cleanup();
    return;
  }

  result->Success(flutter::EncodableValue(true));
}

void SendspinAudioPlugin::Start(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!audio_client_) {
    result->Error("NOT_INITIALIZED", "Audio client not initialized");
    return;
  }
  if (is_started_) {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  HRESULT hr = audio_client_->Start();
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "IAudioClient::Start failed: " + HResultToString(hr));
    return;
  }
  is_started_ = true;
  result->Success(flutter::EncodableValue(true));
}

void SendspinAudioPlugin::Stop(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!audio_client_) {
    result->Error("NOT_INITIALIZED", "Audio client not initialized");
    return;
  }
  if (!is_started_) {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  HRESULT hr = audio_client_->Stop();
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "IAudioClient::Stop failed: " + HResultToString(hr));
    return;
  }
  is_started_ = false;
  result->Success(flutter::EncodableValue(true));
}

void SendspinAudioPlugin::WriteSamples(
    const std::vector<uint8_t>& data,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!audio_client_ || !render_client_) {
    result->Error("NOT_INITIALIZED", "Audio client not initialized");
    return;
  }

  int bytes_per_frame = (channels_ * bit_depth_) / 8;
  if (bytes_per_frame == 0) {
    result->Error("INVALID_STATE", "Invalid frame size (0 bytes per frame)");
    return;
  }

  UINT32 total_frames =
      static_cast<UINT32>(data.size()) / static_cast<UINT32>(bytes_per_frame);
  UINT32 frames_written = 0;

  while (frames_written < total_frames) {
    // Check how much buffer space is available.
    UINT32 padding = 0;
    HRESULT hr = audio_client_->GetCurrentPadding(&padding);
    if (FAILED(hr)) {
      result->Error("WASAPI_ERROR",
                    "GetCurrentPadding failed: " + HResultToString(hr));
      return;
    }

    UINT32 available = buffer_frame_count_ - padding;
    if (available == 0) {
      // Buffer is full. Sleep briefly and retry.
      Sleep(1);
      continue;
    }

    UINT32 frames_to_write = total_frames - frames_written;
    if (frames_to_write > available) {
      frames_to_write = available;
    }

    BYTE* buffer_data = nullptr;
    hr = render_client_->GetBuffer(frames_to_write, &buffer_data);
    if (FAILED(hr)) {
      result->Error("WASAPI_ERROR",
                    "GetBuffer failed: " + HResultToString(hr));
      return;
    }

    size_t byte_offset =
        static_cast<size_t>(frames_written) * static_cast<size_t>(bytes_per_frame);
    size_t byte_count =
        static_cast<size_t>(frames_to_write) * static_cast<size_t>(bytes_per_frame);
    memcpy(buffer_data, data.data() + byte_offset, byte_count);

    hr = render_client_->ReleaseBuffer(frames_to_write, 0);
    if (FAILED(hr)) {
      result->Error("WASAPI_ERROR",
                    "ReleaseBuffer failed: " + HResultToString(hr));
      return;
    }

    frames_written += frames_to_write;
  }

  result->Success(flutter::EncodableValue(static_cast<int>(frames_written)));
}

void SendspinAudioPlugin::SetVolume(
    double volume,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!volume_control_) {
    result->Error("NOT_INITIALIZED", "Audio client not initialized");
    return;
  }
  HRESULT hr =
      volume_control_->SetMasterVolume(static_cast<float>(volume), nullptr);
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "SetMasterVolume failed: " + HResultToString(hr));
    return;
  }
  result->Success(flutter::EncodableValue(true));
}

void SendspinAudioPlugin::SetMuted(
    bool muted,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!volume_control_) {
    result->Error("NOT_INITIALIZED", "Audio client not initialized");
    return;
  }
  HRESULT hr = volume_control_->SetMute(muted ? TRUE : FALSE, nullptr);
  if (FAILED(hr)) {
    result->Error("WASAPI_ERROR",
                  "SetMute failed: " + HResultToString(hr));
    return;
  }
  result->Success(flutter::EncodableValue(true));
}

void SendspinAudioPlugin::Dispose(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  Cleanup();
  result->Success(flutter::EncodableValue(true));
}

void SendspinAudioPlugin::Cleanup() {
  if (is_started_ && audio_client_) {
    audio_client_->Stop();
    is_started_ = false;
  }
  if (volume_control_) {
    volume_control_->Release();
    volume_control_ = nullptr;
  }
  if (render_client_) {
    render_client_->Release();
    render_client_ = nullptr;
  }
  if (audio_client_) {
    audio_client_->Release();
    audio_client_ = nullptr;
  }
  if (device_) {
    device_->Release();
    device_ = nullptr;
  }
  if (device_enumerator_) {
    device_enumerator_->Release();
    device_enumerator_ = nullptr;
  }
  buffer_frame_count_ = 0;
  channels_ = 0;
  bit_depth_ = 0;
}

#ifndef RUNNER_UNREAD_BADGE_H_
#define RUNNER_UNREAD_BADGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// How many emails are unread, as an overlay on the app's taskbar button:
// a dot in the app's accent with the number in it ("99+" past 99), and
// the words for screen readers. Nothing while none is unread.
class UnreadBadge {
 public:
  UnreadBadge(flutter::BinaryMessenger* messenger, HWND window);
  ~UnreadBadge();

 private:
  void Set(int count, const std::wstring& label, unsigned int color);

  HWND window_;
  HICON icon_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_UNREAD_BADGE_H_

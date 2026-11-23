.pragma library
// What a key means on a TV remote, whatever sent it: a CEC/IR remote, a
// Bluetooth remote, the gamepad bridge or a keyboard.

function isBack(e) {
  return e.key === Qt.Key_Escape || e.key === Qt.Key_Back || e.key === Qt.Key_Backspace
}
function isSelect(e) {
  return e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Select || e.key === Qt.Key_Space
}
function isMenu(e) {
  return e.key === Qt.Key_Menu || e.key === Qt.Key_Context1 || e.key === Qt.Key_F10 || e.key === Qt.Key_Info
}
function isMediaPlay(e) {
  return e.key === Qt.Key_MediaPlay || e.key === Qt.Key_MediaTogglePlayPause || e.key === Qt.Key_MediaPause || e.key === Qt.Key_Play
}

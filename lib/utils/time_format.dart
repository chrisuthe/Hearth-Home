// Shared time/date formatting for the home screen clock and ambient overlays.

String formatTime(DateTime dt, bool use24h) {
  if (use24h) {
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
  final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
}

String formatDateShort(DateTime dt) {
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
}

String formatDateLong(DateTime dt) {
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
}

const int customIdMinLength = 6;
const int customIdMaxLength = 16;

final RegExp customIdStartPattern = RegExp(r'^[a-zA-Z0-9]');
final RegExp customIdAllowedPattern = RegExp(r'^[a-zA-Z0-9_-]*$');

bool isValidCustomIdFormat(String value) {
  final id = value.trim();
  return id.length >= customIdMinLength &&
      id.length <= customIdMaxLength &&
      customIdStartPattern.hasMatch(id) &&
      customIdAllowedPattern.hasMatch(id);
}

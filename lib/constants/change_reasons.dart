/// Default options for event change/cancellation reasons
class ChangeReasons {
  // Private constructor to prevent instantiation
  ChangeReasons._();

  /// The option that requires additional text input
  static const String otherOption = '17 其他：備註請寫明';

  /// Prefix used when storing "other" reasons
  static const String otherPrefix = '其他：';

  /// List of all predefined change/cancel reasons
  static const List<String> allReasons = [
    '1先取消',
    '2忘記',
    '3記錯時間',
    '4 改當日其他時間',
    '5 重複約診/已提前看診',
    '6 臨時加班 /臨時有事',
    '7 趕不過來',
    '8人不在台北',
    '9天氣因素 /颱風假',
    '10身體不適',
    '11 症狀減緩',
    '12 忙碌暫緩治療',
    '13 費用考量',
    '14想順延',
    '15 醫師建議順延',
    '16 醫師請假',
    otherOption,
  ];

  /// Check if a reason requires additional text input
  static bool requiresAdditionalInput(String? reason) {
    return reason == otherOption;
  }

  /// Format the final reason string for storage
  /// If it's the "other" option, combines with the additional text
  static String formatReason(String selectedReason, String? additionalText) {
    if (selectedReason == otherOption) {
      return '$otherPrefix${additionalText ?? ''}';
    }
    return selectedReason;
  }
}

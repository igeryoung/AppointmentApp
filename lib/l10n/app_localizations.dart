import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// The title of the application
  ///
  /// In zh_TW, this message translates to:
  /// **'預約登記應用程式'**
  String get appTitle;

  /// Title for appointment books screen
  ///
  /// In zh_TW, this message translates to:
  /// **'預約簿'**
  String get appointmentBooks;

  /// Error message when loading books fails
  ///
  /// In zh_TW, this message translates to:
  /// **'載入簿冊時發生錯誤：{error}'**
  String errorLoadingBooks(String error);

  /// Title for archive book dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'封存簿冊'**
  String get archiveBook;

  /// Confirmation message for archiving a book
  ///
  /// In zh_TW, this message translates to:
  /// **'您確定要封存「{bookName}」嗎？'**
  String archiveBookConfirmation(String bookName);

  /// Cancel button text
  ///
  /// In zh_TW, this message translates to:
  /// **'取消'**
  String get cancel;

  /// Archive button text
  ///
  /// In zh_TW, this message translates to:
  /// **'封存'**
  String get archive;

  /// Title for delete book dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除簿冊'**
  String get deleteBook;

  /// Confirmation message for deleting a book
  ///
  /// In zh_TW, this message translates to:
  /// **'您確定要永久刪除「{bookName}」及其所有活動嗎？'**
  String deleteBookConfirmation(String bookName);

  /// Delete button text
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get delete;

  /// Message shown when there are no books
  ///
  /// In zh_TW, this message translates to:
  /// **'沒有預約簿'**
  String get noAppointmentBooks;

  /// Hint message to create first book
  ///
  /// In zh_TW, this message translates to:
  /// **'點擊 + 按鈕以建立您的第一本簿冊'**
  String get tapToCreateFirstBook;

  /// Title for create new book dialog and tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'建立新簿冊'**
  String get createNewBook;

  /// Label for book name field
  ///
  /// In zh_TW, this message translates to:
  /// **'簿冊名稱'**
  String get bookName;

  /// Hint text for book name field
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入簿冊名稱'**
  String get enterBookName;

  /// Validation error for empty book name
  ///
  /// In zh_TW, this message translates to:
  /// **'簿冊名稱為必填項目'**
  String get bookNameRequired;

  /// Validation error for book name too long
  ///
  /// In zh_TW, this message translates to:
  /// **'簿冊名稱不能超過 50 個字元'**
  String get bookNameTooLong;

  /// Create button text
  ///
  /// In zh_TW, this message translates to:
  /// **'建立'**
  String get create;

  /// Title for rename book dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'重新命名簿冊'**
  String get renameBook;

  /// Rename menu item text
  ///
  /// In zh_TW, this message translates to:
  /// **'重新命名'**
  String get rename;

  /// Save button text
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存'**
  String get save;

  /// Label for created date
  ///
  /// In zh_TW, this message translates to:
  /// **'建立時間：'**
  String get created;

  /// Label for archived date
  ///
  /// In zh_TW, this message translates to:
  /// **'封存時間：'**
  String get archived;

  /// Error message when creating book fails
  ///
  /// In zh_TW, this message translates to:
  /// **'建立簿冊時發生錯誤：{error}'**
  String errorCreatingBook(String error);

  /// Error message when updating book fails
  ///
  /// In zh_TW, this message translates to:
  /// **'更新簿冊時發生錯誤：{error}'**
  String errorUpdatingBook(String error);

  /// Error message when archiving book fails
  ///
  /// In zh_TW, this message translates to:
  /// **'封存簿冊時發生錯誤：{error}'**
  String errorArchivingBook(String error);

  /// Error message when deleting book fails
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除簿冊時發生錯誤：{error}'**
  String errorDeletingBook(String error);

  /// Schedule text
  ///
  /// In zh_TW, this message translates to:
  /// **'日程表'**
  String get schedule;

  /// Title for schedule screen
  ///
  /// In zh_TW, this message translates to:
  /// **'{bookName} - 日程表'**
  String bookSchedule(String bookName);

  /// Day view tab
  ///
  /// In zh_TW, this message translates to:
  /// **'日'**
  String get day;

  /// 3-day view tab
  ///
  /// In zh_TW, this message translates to:
  /// **'三日'**
  String get threeDays;

  /// Week view tab
  ///
  /// In zh_TW, this message translates to:
  /// **'週'**
  String get week;

  /// Tooltip for go to today button
  ///
  /// In zh_TW, this message translates to:
  /// **'前往今天'**
  String get goToToday;

  /// Tooltip for create event button
  ///
  /// In zh_TW, this message translates to:
  /// **'建立活動'**
  String get createEvent;

  /// Error message when loading events fails
  ///
  /// In zh_TW, this message translates to:
  /// **'載入活動時發生錯誤：{error}'**
  String errorLoadingEvents(String error);

  /// Label for record number in event tile
  ///
  /// In zh_TW, this message translates to:
  /// **'紀錄：'**
  String get record;

  /// Label for moved event
  ///
  /// In zh_TW, this message translates to:
  /// **'已移動'**
  String get moved;

  /// Label for time changed event
  ///
  /// In zh_TW, this message translates to:
  /// **'時間已變更：{reason}'**
  String timeChanged(String reason);

  /// Label for removed event
  ///
  /// In zh_TW, this message translates to:
  /// **'已移除：{reason}'**
  String removedReason(String reason);

  /// Title for new event screen
  ///
  /// In zh_TW, this message translates to:
  /// **'新活動'**
  String get newEvent;

  /// Title for edit event screen
  ///
  /// In zh_TW, this message translates to:
  /// **'編輯活動'**
  String get editEvent;

  /// Label for event name field
  ///
  /// In zh_TW, this message translates to:
  /// **'活動名稱 *'**
  String get eventName;

  /// Validation error for empty event name
  ///
  /// In zh_TW, this message translates to:
  /// **'活動名稱為必填項目'**
  String get eventNameRequired;

  /// Label for record number field
  ///
  /// In zh_TW, this message translates to:
  /// **'紀錄編號 *'**
  String get recordNumber;

  /// Validation error for empty record number
  ///
  /// In zh_TW, this message translates to:
  /// **'紀錄編號為必填項目'**
  String get recordNumberRequired;

  /// Label for event type field
  ///
  /// In zh_TW, this message translates to:
  /// **'活動類型 *'**
  String get eventType;

  /// Validation error for empty event type
  ///
  /// In zh_TW, this message translates to:
  /// **'活動類型為必填項目'**
  String get eventTypeRequired;

  /// Simple label for start time (no parameters)
  ///
  /// In zh_TW, this message translates to:
  /// **'開始時間'**
  String get startTime;

  /// Simple label for end time (no parameters)
  ///
  /// In zh_TW, this message translates to:
  /// **'結束時間'**
  String get endTime;

  /// Label for open-ended event
  ///
  /// In zh_TW, this message translates to:
  /// **'不設結束時間'**
  String get openEnded;

  /// Title for delete event dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除活動'**
  String get deleteEvent;

  /// Confirmation message for deleting event
  ///
  /// In zh_TW, this message translates to:
  /// **'您確定要刪除此活動及其筆記嗎？'**
  String get deleteEventConfirmation;

  /// Title for remove event dialog and menu item
  ///
  /// In zh_TW, this message translates to:
  /// **'移除活動'**
  String get removeEvent;

  /// Description for remove event action
  ///
  /// In zh_TW, this message translates to:
  /// **'此活動將被標記為已移除，但仍會以刪除線顯示。'**
  String get removeEventDescription;

  /// Label for removal reason field
  ///
  /// In zh_TW, this message translates to:
  /// **'移除原因：'**
  String get reasonForRemoval;

  /// Hint text for removal reason input field
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入移除原因'**
  String get enterReasonForRemoval;

  /// Remove button text
  ///
  /// In zh_TW, this message translates to:
  /// **'移除'**
  String get remove;

  /// Title for change event time dialog and menu item
  ///
  /// In zh_TW, this message translates to:
  /// **'變更活動時間'**
  String get changeEventTime;

  /// Title for change event type dialog and menu item
  ///
  /// In zh_TW, this message translates to:
  /// **'變更活動類型'**
  String get changeEventType;

  /// Success message after changing event type
  ///
  /// In zh_TW, this message translates to:
  /// **'活動類型已更新'**
  String get eventTypeChanged;

  /// Error message when updating event fails
  ///
  /// In zh_TW, this message translates to:
  /// **'更新活動時發生錯誤：{error}'**
  String errorUpdatingEvent(String error);

  /// Success message after deleting event
  ///
  /// In zh_TW, this message translates to:
  /// **'活動已刪除'**
  String get eventDeleted;

  /// Confirmation message for deleting event with name
  ///
  /// In zh_TW, this message translates to:
  /// **'您確定要刪除「{eventName}」及其筆記嗎？'**
  String confirmDeleteEvent(String eventName);

  /// Description for change time action
  ///
  /// In zh_TW, this message translates to:
  /// **'這將建立一個新活動並使用更新的時間，並將原活動標記為已移除。'**
  String get changeTimeDescription;

  /// Label for start time in change time dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'開始：{time}'**
  String startTimeLabel(String time);

  /// Label for end time in change time dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'結束：{time}'**
  String endTimeLabel(String time);

  /// Label for optional end time button
  ///
  /// In zh_TW, this message translates to:
  /// **'設定結束時間（選填）'**
  String get setEndTimeOptional;

  /// Label for time change reason field
  ///
  /// In zh_TW, this message translates to:
  /// **'時間變更原因： *'**
  String get reasonForTimeChange;

  /// Hint text for time change reason input field
  ///
  /// In zh_TW, this message translates to:
  /// **'請輸入時間變更原因'**
  String get enterReasonForTimeChange;

  /// Error text when reason is required but not provided
  ///
  /// In zh_TW, this message translates to:
  /// **'必須填寫原因'**
  String get reasonRequired;

  /// Detailed message that reason is required
  ///
  /// In zh_TW, this message translates to:
  /// **'必須提供變更活動時間的原因。'**
  String get reasonRequiredMessage;

  /// Change time button text
  ///
  /// In zh_TW, this message translates to:
  /// **'變更時間'**
  String get changeTime;

  /// Success message for time change
  ///
  /// In zh_TW, this message translates to:
  /// **'活動時間變更成功'**
  String get eventTimeChangedSuccess;

  /// Error message when changing time fails
  ///
  /// In zh_TW, this message translates to:
  /// **'變更活動時間時發生錯誤：{error}'**
  String errorChangingEventTime(String error);

  /// Retry button label
  ///
  /// In zh_TW, this message translates to:
  /// **'重試'**
  String get retry;

  /// Delete permanently menu item
  ///
  /// In zh_TW, this message translates to:
  /// **'永久刪除'**
  String get deletePermanently;

  /// Processing message
  ///
  /// In zh_TW, this message translates to:
  /// **'處理中...'**
  String get processing;

  /// Label for event time changed status
  ///
  /// In zh_TW, this message translates to:
  /// **'活動時間已變更'**
  String get eventTimeChanged;

  /// Label for event removed status
  ///
  /// In zh_TW, this message translates to:
  /// **'活動已移除'**
  String get eventRemoved;

  /// Label for reason
  ///
  /// In zh_TW, this message translates to:
  /// **'原因：{reason}'**
  String reason(String reason);

  /// Label for moved to time
  ///
  /// In zh_TW, this message translates to:
  /// **'移至：{time}'**
  String movedTo(String time);

  /// Label for handwriting notes section
  ///
  /// In zh_TW, this message translates to:
  /// **'手寫筆記'**
  String get handwritingNotes;

  /// Pen tool label
  ///
  /// In zh_TW, this message translates to:
  /// **'筆'**
  String get pen;

  /// Eraser tool label
  ///
  /// In zh_TW, this message translates to:
  /// **'橡皮擦'**
  String get eraser;

  /// Controls label
  ///
  /// In zh_TW, this message translates to:
  /// **'控制項'**
  String get controls;

  /// Undo action label
  ///
  /// In zh_TW, this message translates to:
  /// **'復原'**
  String get undo;

  /// Redo action label
  ///
  /// In zh_TW, this message translates to:
  /// **'重做'**
  String get redo;

  /// Clear all tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'全部清除'**
  String get clearAll;

  /// Label for eraser size
  ///
  /// In zh_TW, this message translates to:
  /// **'橡皮擦大小：'**
  String get eraserSize;

  /// Label for pen width
  ///
  /// In zh_TW, this message translates to:
  /// **'筆寬：'**
  String get penWidth;

  /// Label for color
  ///
  /// In zh_TW, this message translates to:
  /// **'顏色：'**
  String get color;

  /// Error message when loading note fails
  ///
  /// In zh_TW, this message translates to:
  /// **'載入筆記時發生錯誤：{error}'**
  String errorLoadingNote(String error);

  /// Error message when saving event fails
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存活動時發生錯誤：{error}'**
  String errorSavingEvent(String error);

  /// Message when event saves but note save fails
  ///
  /// In zh_TW, this message translates to:
  /// **'活動已儲存，但筆記儲存失敗'**
  String get eventSavedNoteFailure;

  /// Error message when deleting event fails
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除活動時發生錯誤：{error}'**
  String errorDeletingEvent(String error);

  /// Error message when removing event fails
  ///
  /// In zh_TW, this message translates to:
  /// **'移除活動時發生錯誤：{error}'**
  String errorRemovingEvent(String error);

  /// Consultation event type
  ///
  /// In zh_TW, this message translates to:
  /// **'諮詢'**
  String get consultation;

  /// Surgery event type
  ///
  /// In zh_TW, this message translates to:
  /// **'手術'**
  String get surgery;

  /// Follow-up event type
  ///
  /// In zh_TW, this message translates to:
  /// **'追蹤'**
  String get followUp;

  /// Emergency event type
  ///
  /// In zh_TW, this message translates to:
  /// **'緊急'**
  String get emergency;

  /// Check-up event type
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查'**
  String get checkUp;

  /// Treatment event type
  ///
  /// In zh_TW, this message translates to:
  /// **'治療'**
  String get treatment;

  /// Message when date changes and app updates to today
  ///
  /// In zh_TW, this message translates to:
  /// **'日期已變更 - 已更新至今天'**
  String get dateChangedToToday;

  /// Default reason when event time is changed via drag
  ///
  /// In zh_TW, this message translates to:
  /// **'透過拖曳變更時間'**
  String get timeChangedViaDrag;

  /// Label for time change reason field
  ///
  /// In zh_TW, this message translates to:
  /// **'時間變更原因'**
  String get reasonForTimeChangeLabel;

  /// Hint text for reason input field
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入原因...'**
  String get enterReasonHint;

  /// OK button text
  ///
  /// In zh_TW, this message translates to:
  /// **'確定'**
  String get ok;

  /// Success message after changing event time
  ///
  /// In zh_TW, this message translates to:
  /// **'活動時間變更成功'**
  String get eventTimeChangedSuccessfully;

  /// Error message when changing time fails
  ///
  /// In zh_TW, this message translates to:
  /// **'變更時間時發生錯誤：{error}'**
  String errorChangingTime(String error);

  /// Error message when saving drawing fails
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存繪圖時發生錯誤：{error}'**
  String errorSavingDrawing(String error);

  /// Label for removal reason field
  ///
  /// In zh_TW, this message translates to:
  /// **'移除原因'**
  String get reasonForRemovalLabel;

  /// Success message after removing event
  ///
  /// In zh_TW, this message translates to:
  /// **'活動已成功移除'**
  String get eventRemovedSuccessfully;

  /// Error message when removing event fails
  ///
  /// In zh_TW, this message translates to:
  /// **'移除活動時發生錯誤：{error}'**
  String errorRemovingEventMessage(String error);

  /// Title for generate random events dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'產生隨機活動'**
  String get generateRandomEvents;

  /// Label for number of events field
  ///
  /// In zh_TW, this message translates to:
  /// **'活動數量'**
  String get numberOfEvents;

  /// Hint text for number input
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入數字（1-50）'**
  String get enterNumber;

  /// Checkbox label to clear existing events
  ///
  /// In zh_TW, this message translates to:
  /// **'先清除所有現有活動'**
  String get clearAllExistingEventsFirst;

  /// Checkbox label for open-ended events
  ///
  /// In zh_TW, this message translates to:
  /// **'僅產生不設結束時間的活動'**
  String get generateOpenEndedEventsOnly;

  /// Subtitle for open-ended events option
  ///
  /// In zh_TW, this message translates to:
  /// **'無結束時間'**
  String get noEndTime;

  /// Generate button text
  ///
  /// In zh_TW, this message translates to:
  /// **'產生'**
  String get generate;

  /// Title for test time active dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'測試時間已啟用'**
  String get testTimeActive;

  /// Label showing current test time
  ///
  /// In zh_TW, this message translates to:
  /// **'目前測試時間：\n{time}'**
  String currentTestTime(String time);

  /// Button to reset test time
  ///
  /// In zh_TW, this message translates to:
  /// **'重設為實際時間'**
  String get resetToRealTime;

  /// Message when test time is set
  ///
  /// In zh_TW, this message translates to:
  /// **'測試時間已設定為：{time}'**
  String testTimeSetTo(String time);

  /// Message after clearing and generating events
  ///
  /// In zh_TW, this message translates to:
  /// **'已清除所有活動並產生 {count} 個活動'**
  String clearedAndGeneratedEvents(int count);

  /// Message when some slots were full
  ///
  /// In zh_TW, this message translates to:
  /// **'已清除所有活動並產生 {count} 個活動（部分時段已滿）'**
  String clearedAndGeneratedEventsSomeFull(int count);

  /// Message for open-ended events
  ///
  /// In zh_TW, this message translates to:
  /// **'已清除所有活動並產生 {count} 個不設結束時間的活動'**
  String clearedAndGeneratedOpenEndedEvents(int count);

  /// Message for open-ended events with full slots
  ///
  /// In zh_TW, this message translates to:
  /// **'已清除所有活動並產生 {count} 個不設結束時間的活動（部分時段已滿）'**
  String clearedAndGeneratedOpenEndedEventsSomeFull(int count);

  /// Message after generating events
  ///
  /// In zh_TW, this message translates to:
  /// **'已產生 {count} 個隨機活動'**
  String generatedEvents(int count);

  /// Message when some slots were full
  ///
  /// In zh_TW, this message translates to:
  /// **'已產生 {count} 個活動（部分時段已滿）'**
  String generatedEventsSomeFull(int count);

  /// Message for generated open-ended events
  ///
  /// In zh_TW, this message translates to:
  /// **'已產生 {count} 個不設結束時間的活動'**
  String generatedOpenEndedEvents(int count);

  /// Message for open-ended events with full slots
  ///
  /// In zh_TW, this message translates to:
  /// **'已產生 {count} 個不設結束時間的活動（部分時段已滿）'**
  String generatedOpenEndedEventsSomeFull(int count);

  /// Tooltip for go to today button
  ///
  /// In zh_TW, this message translates to:
  /// **'前往今天'**
  String get goToTodayTooltip;

  /// Title for event options menu
  ///
  /// In zh_TW, this message translates to:
  /// **'活動選項'**
  String get eventOptions;

  /// Clear action label
  ///
  /// In zh_TW, this message translates to:
  /// **'清除'**
  String get clear;

  /// Label for creation date
  ///
  /// In zh_TW, this message translates to:
  /// **'建立時間：'**
  String get createdLabel;

  /// Label for archive date
  ///
  /// In zh_TW, this message translates to:
  /// **'封存時間：'**
  String get archivedLabel;

  /// Error message when loading note fails
  ///
  /// In zh_TW, this message translates to:
  /// **'載入筆記時發生錯誤：{error}'**
  String errorLoadingNoteMessage(String error);

  /// Message when event saves but note fails
  ///
  /// In zh_TW, this message translates to:
  /// **'活動已儲存，但筆記儲存失敗'**
  String get eventSavedButNoteFailed;

  /// Error message when saving event fails
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存活動時發生錯誤：{error}'**
  String errorSavingEventMessage(String error);

  /// Title for delete event dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除活動'**
  String get deleteEventTitle;

  /// Confirmation message for deleting event
  ///
  /// In zh_TW, this message translates to:
  /// **'您確定要刪除此活動及其筆記嗎？'**
  String get deleteEventConfirmMessage;

  /// Delete button text
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get deleteButton;

  /// Error message when deleting event fails
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除活動時發生錯誤：{error}'**
  String errorDeletingEventMessage(String error);

  /// Title for remove event dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'移除活動'**
  String get removeEventTitle;

  /// Message explaining remove action
  ///
  /// In zh_TW, this message translates to:
  /// **'此活動將被標記為已移除，但仍會以刪除線顯示。'**
  String get removeEventMessage;

  /// Label for removal reason field
  ///
  /// In zh_TW, this message translates to:
  /// **'移除原因：'**
  String get reasonForRemovalField;

  /// Remove button text
  ///
  /// In zh_TW, this message translates to:
  /// **'移除'**
  String get removeButton;

  /// Title for change event time dialog
  ///
  /// In zh_TW, this message translates to:
  /// **'變更活動時間'**
  String get changeEventTimeTitle;

  /// Message explaining time change action
  ///
  /// In zh_TW, this message translates to:
  /// **'這將建立一個新活動並使用更新的時間，並將原活動標記為已移除。'**
  String get changeTimeMessage;

  /// Label for time change reason field (required)
  ///
  /// In zh_TW, this message translates to:
  /// **'時間變更原因： *'**
  String get reasonForTimeChangeField;

  /// Change time button text
  ///
  /// In zh_TW, this message translates to:
  /// **'變更時間'**
  String get changeTimeButton;

  /// Error message when changing event time fails
  ///
  /// In zh_TW, this message translates to:
  /// **'變更活動時間時發生錯誤：{error}'**
  String errorChangingEventTimeMessage(String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

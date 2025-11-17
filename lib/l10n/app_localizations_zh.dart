// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '預約登記應用程式';

  @override
  String get appointmentBooks => '預約簿';

  @override
  String errorLoadingBooks(String error) {
    return '載入簿冊時發生錯誤：$error';
  }

  @override
  String get archiveBook => '封存簿冊';

  @override
  String archiveBookConfirmation(String bookName) {
    return '您確定要封存「$bookName」嗎？';
  }

  @override
  String get cancel => '取消';

  @override
  String get archive => '封存';

  @override
  String get deleteBook => '刪除簿冊';

  @override
  String deleteBookConfirmation(String bookName) {
    return '您確定要永久刪除「$bookName」及其所有活動嗎？';
  }

  @override
  String get delete => '刪除';

  @override
  String get noAppointmentBooks => '沒有預約簿';

  @override
  String get tapToCreateFirstBook => '點擊 + 按鈕以建立您的第一本簿冊';

  @override
  String get createNewBook => '建立新簿冊';

  @override
  String get bookName => '簿冊名稱';

  @override
  String get enterBookName => '輸入簿冊名稱';

  @override
  String get bookNameRequired => '簿冊名稱為必填項目';

  @override
  String get bookNameTooLong => '簿冊名稱不能超過 50 個字元';

  @override
  String get create => '建立';

  @override
  String get renameBook => '重新命名簿冊';

  @override
  String get rename => '重新命名';

  @override
  String get save => '儲存';

  @override
  String get created => '建立時間：';

  @override
  String get archived => '封存時間：';

  @override
  String errorCreatingBook(String error) {
    return '建立簿冊時發生錯誤：$error';
  }

  @override
  String errorUpdatingBook(String error) {
    return '更新簿冊時發生錯誤：$error';
  }

  @override
  String errorArchivingBook(String error) {
    return '封存簿冊時發生錯誤：$error';
  }

  @override
  String errorDeletingBook(String error) {
    return '刪除簿冊時發生錯誤：$error';
  }

  @override
  String get schedule => '日程表';

  @override
  String bookSchedule(String bookName) {
    return '$bookName - 日程表';
  }

  @override
  String get day => '日';

  @override
  String get threeDays => '三日';

  @override
  String get week => '週';

  @override
  String get goToToday => '前往今天';

  @override
  String get toggleOldEvents => '切換舊事件顯示';

  @override
  String get showOldEvents => '顯示舊事件';

  @override
  String get hideOldEvents => '隱藏舊事件';

  @override
  String get showDrawing => '顯示繪圖';

  @override
  String get hideDrawing => '隱藏繪圖';

  @override
  String get createEvent => '建立活動';

  @override
  String errorLoadingEvents(String error) {
    return '載入活動時發生錯誤：$error';
  }

  @override
  String get record => '紀錄：';

  @override
  String get moved => '已移動';

  @override
  String timeChanged(String reason) {
    return '時間已變更：$reason';
  }

  @override
  String removedReason(String reason) {
    return '已移除：$reason';
  }

  @override
  String get newEvent => '新活動';

  @override
  String get editEvent => '編輯活動';

  @override
  String get eventName => '活動名稱 *';

  @override
  String get eventNameRequired => '活動名稱為必填項目';

  @override
  String get recordNumber => '紀錄編號';

  @override
  String get recordNumberRequired => '紀錄編號為必填項目';

  @override
  String get phone => '電話';

  @override
  String get chargeItems => '收費項目';

  @override
  String get chargeItemName => '項目名稱';

  @override
  String get chargeItemCost => '費用';

  @override
  String get addChargeItem => '新增收費項目';

  @override
  String get addChargeItemTitle => '新增收費項目';

  @override
  String get editChargeItemTitle => '編輯收費項目';

  @override
  String get paid => '已付';

  @override
  String get total => '總額';

  @override
  String get chargeItemNameRequired => '項目名稱為必填項目';

  @override
  String get chargeItemCostInvalid => '費用必須為正整數';

  @override
  String get eventType => '活動類型 *';

  @override
  String get eventTypeRequired => '活動類型為必填項目';

  @override
  String get startTime => '開始時間';

  @override
  String get endTime => '結束時間';

  @override
  String get openEnded => '不設結束時間';

  @override
  String get deleteEvent => '刪除約診';

  @override
  String get deleteEventConfirmation => '您確定要刪除此活動及其筆記嗎？';

  @override
  String get removeEvent => '取消約診';

  @override
  String get removeEventDescription => '此活動將被標記為已移除，但仍會以刪除線顯示。';

  @override
  String get reasonForRemoval => '移除原因：';

  @override
  String get enterReasonForRemoval => '輸入移除原因';

  @override
  String get remove => '移除';

  @override
  String get changeEventTime => '變更約診時間';

  @override
  String get changeEventType => '變更約診類型';

  @override
  String get eventTypeChanged => '活動類型已更新';

  @override
  String errorUpdatingEvent(String error) {
    return '更新活動時發生錯誤：$error';
  }

  @override
  String get eventDeleted => '活動已刪除';

  @override
  String confirmDeleteEvent(String eventName) {
    return '您確定要刪除「$eventName」及其筆記嗎？';
  }

  @override
  String get changeTimeDescription => '這將建立一個新活動並使用更新的時間，並將原活動標記為已移除。';

  @override
  String startTimeLabel(String time) {
    return '開始：$time';
  }

  @override
  String endTimeLabel(String time) {
    return '結束：$time';
  }

  @override
  String get setEndTimeOptional => '設定結束時間（選填）';

  @override
  String get reasonForTimeChange => '時間變更原因： *';

  @override
  String get enterReasonForTimeChange => '請輸入時間變更原因';

  @override
  String get reasonRequired => '原因為必填項目';

  @override
  String get reasonRequiredMessage => '必須提供原因才能變更活動時間。';

  @override
  String get changeTime => '變更時間';

  @override
  String get eventTimeChangedSuccess => '活動時間變更成功';

  @override
  String errorChangingEventTime(String error) {
    return '變更活動時間時發生錯誤：$error';
  }

  @override
  String get retry => '重試';

  @override
  String get deletePermanently => '永久刪除';

  @override
  String get processing => '處理中...';

  @override
  String get eventTimeChanged => '活動時間已變更';

  @override
  String get eventRemoved => '活動已移除';

  @override
  String reason(String reason) {
    return '原因：$reason';
  }

  @override
  String movedTo(String time) {
    return '移至：$time';
  }

  @override
  String get handwritingNotes => '手寫筆記';

  @override
  String get pen => '筆';

  @override
  String get eraser => '橡皮擦';

  @override
  String get controls => '控制項';

  @override
  String get undo => '復原';

  @override
  String get redo => '重做';

  @override
  String get clearAll => '全部清除';

  @override
  String get eraserSize => '橡皮擦大小：';

  @override
  String get penWidth => '筆寬：';

  @override
  String get color => '顏色：';

  @override
  String errorLoadingNote(String error) {
    return '載入筆記時發生錯誤：$error';
  }

  @override
  String errorSavingEvent(String error) {
    return '儲存活動時發生錯誤：$error';
  }

  @override
  String get eventSavedNoteFailure => '活動已儲存，但筆記儲存失敗';

  @override
  String errorDeletingEvent(String error) {
    return '刪除活動時發生錯誤：$error';
  }

  @override
  String errorRemovingEvent(String error) {
    return '移除活動時發生錯誤：$error';
  }

  @override
  String get consultation => '諮詢';

  @override
  String get surgery => '手術';

  @override
  String get followUp => '追蹤';

  @override
  String get emergency => '緊急';

  @override
  String get checkUp => '檢查';

  @override
  String get treatment => '治療';

  @override
  String get dateChangedToToday => '日期已變更 - 已更新至今天';

  @override
  String get timeChangedViaDrag => '透過拖曳變更時間';

  @override
  String get reasonForTimeChangeLabel => '時間變更原因';

  @override
  String get enterReasonHint => '輸入原因...';

  @override
  String get ok => '確定';

  @override
  String get eventTimeChangedSuccessfully => '活動時間變更成功';

  @override
  String errorChangingTime(String error) {
    return '變更時間時發生錯誤：$error';
  }

  @override
  String errorSavingDrawing(String error) {
    return '儲存繪圖時發生錯誤：$error';
  }

  @override
  String get reasonForRemovalLabel => '移除原因';

  @override
  String get eventRemovedSuccessfully => '活動已成功移除';

  @override
  String errorRemovingEventMessage(String error) {
    return '移除活動時發生錯誤：$error';
  }

  @override
  String get generateRandomEvents => '產生隨機活動';

  @override
  String get numberOfEvents => '活動數量';

  @override
  String get enterNumber => '輸入數字（1-50）';

  @override
  String get clearAllExistingEventsFirst => '先清除所有現有活動';

  @override
  String get generateOpenEndedEventsOnly => '僅產生不設結束時間的活動';

  @override
  String get noEndTime => '無結束時間';

  @override
  String get generate => '產生';

  @override
  String get testTimeActive => '測試時間已啟用';

  @override
  String currentTestTime(String time) {
    return '目前測試時間：\n$time';
  }

  @override
  String get resetToRealTime => '重設為實際時間';

  @override
  String testTimeSetTo(String time) {
    return '測試時間已設定為：$time';
  }

  @override
  String clearedAndGeneratedEvents(int count) {
    return '已清除所有活動並產生 $count 個活動';
  }

  @override
  String clearedAndGeneratedEventsSomeFull(int count) {
    return '已清除所有活動並產生 $count 個活動（部分時段已滿）';
  }

  @override
  String clearedAndGeneratedOpenEndedEvents(int count) {
    return '已清除所有活動並產生 $count 個不設結束時間的活動';
  }

  @override
  String clearedAndGeneratedOpenEndedEventsSomeFull(int count) {
    return '已清除所有活動並產生 $count 個不設結束時間的活動（部分時段已滿）';
  }

  @override
  String generatedEvents(int count) {
    return '已產生 $count 個隨機活動';
  }

  @override
  String generatedEventsSomeFull(int count) {
    return '已產生 $count 個活動（部分時段已滿）';
  }

  @override
  String generatedOpenEndedEvents(int count) {
    return '已產生 $count 個不設結束時間的活動';
  }

  @override
  String generatedOpenEndedEventsSomeFull(int count) {
    return '已產生 $count 個不設結束時間的活動（部分時段已滿）';
  }

  @override
  String get goToTodayTooltip => '前往今天';

  @override
  String get eventOptions => '活動選項';

  @override
  String get scheduleNextAppointment => '預約下次約診';

  @override
  String get daysFromOriginal => '距離原約診天數';

  @override
  String get appointmentType => '約診類型';

  @override
  String targetDatePreview(String date) {
    return '目標日期：$date';
  }

  @override
  String get confirm => '確認';

  @override
  String get daysRequired => '天數為必填項目';

  @override
  String get daysInvalid => '天數必須為正整數';

  @override
  String get clear => '清除';

  @override
  String get createdLabel => '建立時間：';

  @override
  String get archivedLabel => '封存時間：';

  @override
  String errorLoadingNoteMessage(String error) {
    return '載入筆記時發生錯誤：$error';
  }

  @override
  String get eventSavedButNoteFailed => '活動已儲存，但筆記儲存失敗';

  @override
  String errorSavingEventMessage(String error) {
    return '儲存活動時發生錯誤：$error';
  }

  @override
  String get deleteEventTitle => '刪除約診';

  @override
  String get deleteEventConfirmMessage => '您確定要刪除此活動及其筆記嗎？';

  @override
  String get deleteButton => '刪除';

  @override
  String errorDeletingEventMessage(String error) {
    return '刪除活動時發生錯誤：$error';
  }

  @override
  String get removeEventTitle => '取消約診';

  @override
  String get removeEventMessage => '此活動將被標記為已移除，但仍會以刪除線顯示。';

  @override
  String get reasonForRemovalField => '移除原因：';

  @override
  String get removeButton => '移除';

  @override
  String get changeEventTimeTitle => '變更約診時間';

  @override
  String get changeTimeMessage => '這將建立一個新活動並使用更新的時間，並將原活動標記為已移除。';

  @override
  String get reasonForTimeChangeField => '時間變更原因： *';

  @override
  String get changeTimeButton => '變更時間';

  @override
  String errorChangingEventTimeMessage(String error) {
    return '變更活動時間時發生錯誤：$error';
  }

  @override
  String get heavyLoadTest => '重量测试';

  @override
  String get heavyLoadTestWarning =>
      '此测试将产生 2,928 个活动与约 8,800 万个数据点，可能需要数分钟时间。';

  @override
  String get heavyLoadTestConfirm => '开始重量测试';

  @override
  String heavyLoadTestProgress(int count, int total, int percent) {
    return '产生中：$count/$total ($percent%)';
  }

  @override
  String heavyLoadTestComplete(int events, int strokes, String time) {
    return '已产生 $events 个活动，共 $strokes 个笔画，耗时 $time';
  }

  @override
  String get clearExistingEvents => '清除现有活动';

  @override
  String get generatingEvents => '产生活动中...';

  @override
  String get stage1Creating => '阶段 1/2：建立活动';

  @override
  String get stage2AddingStrokes => '阶段 2/2：加入笔画';

  @override
  String get heavyLoadStage1Only => '重量测试 - 阶段1';

  @override
  String get heavyLoadStage2Only => '重量测试 - 阶段2';

  @override
  String get stage1OnlyWarning => '建立 11,712 个空白活动（不含笔画）\n每个格子4个活动';

  @override
  String get stage2OnlyWarning => '为现有 HEAVY- 活动加入笔画（750笔画/活动）';

  @override
  String stage1Complete(int events) {
    return '阶段1完成：已建立 $events 个活动';
  }

  @override
  String stage2Complete(int events, int strokes, String time) {
    return '阶段2完成：已加入 $strokes 个笔画到 $events 个活动，耗时 $time';
  }

  @override
  String get offlineMode => '离线模式';

  @override
  String get showingCachedData => '显示已缓存的数据';

  @override
  String get syncingToServer => '正在同步到服务器...';

  @override
  String get noteSaved => '笔记已保存';

  @override
  String errorSavingNote(String error) {
    return '保存笔记时出错：$error';
  }

  @override
  String get unsavedChanges => '未保存的更改';

  @override
  String get unsavedChangesMessage => '您有未保存的更改。确定要离开吗？';

  @override
  String get discard => '舍弃';

  @override
  String get keepEditing => '继续编辑';

  @override
  String get queryAppointments => '查詢預約記錄';

  @override
  String get search => '搜尋';

  @override
  String get errorLoadingData => '載入資料時發生錯誤';

  @override
  String get nameRequired => '名稱為必填項目';

  @override
  String get errorSearching => '搜尋時發生錯誤';

  @override
  String get noRecordNumbers => '沒有紀錄編號';

  @override
  String get selectRecordNumber => '選擇紀錄編號';

  @override
  String get enterSearchCriteria => '輸入搜尋條件以查詢預約記錄';

  @override
  String get noAppointmentsFound => '找不到符合條件的預約記錄';

  @override
  String get enterNameFirst => '請先輸入姓名';

  @override
  String get noMatchingRecordNumbers => '沒有符合的病例號';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => '預約登記應用程式';

  @override
  String get appointmentBooks => '預約簿';

  @override
  String errorLoadingBooks(String error) {
    return '載入簿冊時發生錯誤：$error';
  }

  @override
  String get archiveBook => '封存簿冊';

  @override
  String archiveBookConfirmation(String bookName) {
    return '您確定要封存「$bookName」嗎？';
  }

  @override
  String get cancel => '取消';

  @override
  String get archive => '封存';

  @override
  String get deleteBook => '刪除簿冊';

  @override
  String deleteBookConfirmation(String bookName) {
    return '您確定要永久刪除「$bookName」及其所有活動嗎？';
  }

  @override
  String get delete => '刪除';

  @override
  String get noAppointmentBooks => '沒有預約簿';

  @override
  String get tapToCreateFirstBook => '點擊 + 按鈕以建立您的第一本簿冊';

  @override
  String get createNewBook => '建立新簿冊';

  @override
  String get bookName => '簿冊名稱';

  @override
  String get enterBookName => '輸入簿冊名稱';

  @override
  String get bookNameRequired => '簿冊名稱為必填項目';

  @override
  String get bookNameTooLong => '簿冊名稱不能超過 50 個字元';

  @override
  String get create => '建立';

  @override
  String get renameBook => '重新命名簿冊';

  @override
  String get rename => '重新命名';

  @override
  String get save => '儲存';

  @override
  String get created => '建立時間：';

  @override
  String get archived => '封存時間：';

  @override
  String errorCreatingBook(String error) {
    return '建立簿冊時發生錯誤：$error';
  }

  @override
  String errorUpdatingBook(String error) {
    return '更新簿冊時發生錯誤：$error';
  }

  @override
  String errorArchivingBook(String error) {
    return '封存簿冊時發生錯誤：$error';
  }

  @override
  String errorDeletingBook(String error) {
    return '刪除簿冊時發生錯誤：$error';
  }

  @override
  String get schedule => '日程表';

  @override
  String bookSchedule(String bookName) {
    return '$bookName - 日程表';
  }

  @override
  String get day => '日';

  @override
  String get threeDays => '三日';

  @override
  String get week => '週';

  @override
  String get goToToday => '前往今天';

  @override
  String get toggleOldEvents => '切換舊事件顯示';

  @override
  String get showOldEvents => '顯示舊事件';

  @override
  String get hideOldEvents => '隱藏舊事件';

  @override
  String get showDrawing => '顯示繪圖';

  @override
  String get hideDrawing => '隱藏繪圖';

  @override
  String get createEvent => '建立活動';

  @override
  String errorLoadingEvents(String error) {
    return '載入活動時發生錯誤：$error';
  }

  @override
  String get record => '紀錄：';

  @override
  String get moved => '已移動';

  @override
  String timeChanged(String reason) {
    return '時間已變更：$reason';
  }

  @override
  String removedReason(String reason) {
    return '已移除：$reason';
  }

  @override
  String get newEvent => '新約診';

  @override
  String get editEvent => '編輯活動';

  @override
  String get eventName => '姓名 *';

  @override
  String get eventNameRequired => '姓名為必填項目';

  @override
  String get recordNumber => '病例號';

  @override
  String get recordNumberRequired => '病例號為必填項目';

  @override
  String get phone => '電話';

  @override
  String get chargeItems => '收費項目';

  @override
  String get chargeItemName => '項目名稱';

  @override
  String get chargeItemCost => '費用';

  @override
  String get addChargeItem => '新增收費項目';

  @override
  String get addChargeItemTitle => '新增收費項目';

  @override
  String get editChargeItemTitle => '編輯收費項目';

  @override
  String get paid => '已付';

  @override
  String get total => '總額';

  @override
  String get chargeItemNameRequired => '項目名稱為必填項目';

  @override
  String get chargeItemCostInvalid => '費用必須為正整數';

  @override
  String get eventType => '約診類型 *';

  @override
  String get eventTypeRequired => '約診類型為必填項目';

  @override
  String get startTime => '開始時間';

  @override
  String get endTime => '結束時間';

  @override
  String get openEnded => '不設結束時間';

  @override
  String get deleteEvent => '刪除約診';

  @override
  String get deleteEventConfirmation => '您確定要刪除此活動及其筆記嗎？';

  @override
  String get removeEvent => '取消約診';

  @override
  String get removeEventDescription => '此活動將被標記為已移除，但仍會以刪除線顯示。';

  @override
  String get reasonForRemoval => '移除原因：';

  @override
  String get enterReasonForRemoval => '輸入移除原因';

  @override
  String get remove => '移除';

  @override
  String get changeEventTime => '變更約診時間';

  @override
  String get changeEventType => '變更約診類型';

  @override
  String get eventTypeChanged => '活動類型已更新';

  @override
  String errorUpdatingEvent(String error) {
    return '更新活動時發生錯誤：$error';
  }

  @override
  String get eventDeleted => '活動已刪除';

  @override
  String confirmDeleteEvent(String eventName) {
    return '您確定要刪除「$eventName」及其筆記嗎？';
  }

  @override
  String get changeTimeDescription => '這將建立一個新活動並使用更新的時間，並將原活動標記為已移除。';

  @override
  String startTimeLabel(String time) {
    return '開始：$time';
  }

  @override
  String endTimeLabel(String time) {
    return '結束：$time';
  }

  @override
  String get setEndTimeOptional => '設定結束時間（選填）';

  @override
  String get reasonForTimeChange => '時間變更原因： *';

  @override
  String get enterReasonForTimeChange => '請輸入時間變更原因';

  @override
  String get reasonRequired => '必須填寫原因';

  @override
  String get reasonRequiredMessage => '必須提供變更活動時間的原因。';

  @override
  String get changeTime => '變更時間';

  @override
  String get eventTimeChangedSuccess => '活動時間變更成功';

  @override
  String errorChangingEventTime(String error) {
    return '變更活動時間時發生錯誤：$error';
  }

  @override
  String get retry => '重試';

  @override
  String get deletePermanently => '永久刪除';

  @override
  String get processing => '處理中...';

  @override
  String get eventTimeChanged => '活動時間已變更';

  @override
  String get eventRemoved => '活動已移除';

  @override
  String reason(String reason) {
    return '原因：$reason';
  }

  @override
  String movedTo(String time) {
    return '移至：$time';
  }

  @override
  String get handwritingNotes => '手寫筆記';

  @override
  String get pen => '筆';

  @override
  String get eraser => '橡皮擦';

  @override
  String get controls => '控制項';

  @override
  String get undo => '復原';

  @override
  String get redo => '重做';

  @override
  String get clearAll => '全部清除';

  @override
  String get eraserSize => '橡皮擦大小：';

  @override
  String get penWidth => '筆寬：';

  @override
  String get color => '顏色：';

  @override
  String errorLoadingNote(String error) {
    return '載入筆記時發生錯誤：$error';
  }

  @override
  String errorSavingEvent(String error) {
    return '儲存活動時發生錯誤：$error';
  }

  @override
  String get eventSavedNoteFailure => '活動已儲存，但筆記儲存失敗';

  @override
  String errorDeletingEvent(String error) {
    return '刪除活動時發生錯誤：$error';
  }

  @override
  String errorRemovingEvent(String error) {
    return '移除活動時發生錯誤：$error';
  }

  @override
  String get consultation => '諮詢';

  @override
  String get surgery => '手術';

  @override
  String get followUp => '追蹤';

  @override
  String get emergency => '緊急';

  @override
  String get checkUp => '檢查';

  @override
  String get treatment => '治療';

  @override
  String get dateChangedToToday => '日期已變更 - 已更新至今天';

  @override
  String get timeChangedViaDrag => '透過拖曳變更時間';

  @override
  String get reasonForTimeChangeLabel => '時間變更原因';

  @override
  String get enterReasonHint => '輸入原因...';

  @override
  String get ok => '確定';

  @override
  String get eventTimeChangedSuccessfully => '活動時間變更成功';

  @override
  String errorChangingTime(String error) {
    return '變更時間時發生錯誤：$error';
  }

  @override
  String errorSavingDrawing(String error) {
    return '儲存繪圖時發生錯誤：$error';
  }

  @override
  String get reasonForRemovalLabel => '移除原因';

  @override
  String get eventRemovedSuccessfully => '活動已成功移除';

  @override
  String errorRemovingEventMessage(String error) {
    return '移除活動時發生錯誤：$error';
  }

  @override
  String get generateRandomEvents => '產生隨機活動';

  @override
  String get numberOfEvents => '活動數量';

  @override
  String get enterNumber => '輸入數字（1-50）';

  @override
  String get clearAllExistingEventsFirst => '先清除所有現有活動';

  @override
  String get generateOpenEndedEventsOnly => '僅產生不設結束時間的活動';

  @override
  String get noEndTime => '無結束時間';

  @override
  String get generate => '產生';

  @override
  String get testTimeActive => '測試時間已啟用';

  @override
  String currentTestTime(String time) {
    return '目前測試時間：\n$time';
  }

  @override
  String get resetToRealTime => '重設為實際時間';

  @override
  String testTimeSetTo(String time) {
    return '測試時間已設定為：$time';
  }

  @override
  String clearedAndGeneratedEvents(int count) {
    return '已清除所有活動並產生 $count 個活動';
  }

  @override
  String clearedAndGeneratedEventsSomeFull(int count) {
    return '已清除所有活動並產生 $count 個活動（部分時段已滿）';
  }

  @override
  String clearedAndGeneratedOpenEndedEvents(int count) {
    return '已清除所有活動並產生 $count 個不設結束時間的活動';
  }

  @override
  String clearedAndGeneratedOpenEndedEventsSomeFull(int count) {
    return '已清除所有活動並產生 $count 個不設結束時間的活動（部分時段已滿）';
  }

  @override
  String generatedEvents(int count) {
    return '已產生 $count 個隨機活動';
  }

  @override
  String generatedEventsSomeFull(int count) {
    return '已產生 $count 個活動（部分時段已滿）';
  }

  @override
  String generatedOpenEndedEvents(int count) {
    return '已產生 $count 個不設結束時間的活動';
  }

  @override
  String generatedOpenEndedEventsSomeFull(int count) {
    return '已產生 $count 個不設結束時間的活動（部分時段已滿）';
  }

  @override
  String get goToTodayTooltip => '前往今天';

  @override
  String get eventOptions => '活動選項';

  @override
  String get scheduleNextAppointment => '預約下次約診';

  @override
  String get daysFromOriginal => '距離原約診天數';

  @override
  String get appointmentType => '約診類型';

  @override
  String targetDatePreview(String date) {
    return '目標日期：$date';
  }

  @override
  String get confirm => '確認';

  @override
  String get daysRequired => '天數為必填項目';

  @override
  String get daysInvalid => '天數必須為正整數';

  @override
  String get clear => '清除';

  @override
  String get createdLabel => '建立時間：';

  @override
  String get archivedLabel => '封存時間：';

  @override
  String errorLoadingNoteMessage(String error) {
    return '載入筆記時發生錯誤：$error';
  }

  @override
  String get eventSavedButNoteFailed => '活動已儲存，但筆記儲存失敗';

  @override
  String errorSavingEventMessage(String error) {
    return '儲存活動時發生錯誤：$error';
  }

  @override
  String get deleteEventTitle => '刪除約診';

  @override
  String get deleteEventConfirmMessage => '您確定要刪除此活動及其筆記嗎？';

  @override
  String get deleteButton => '刪除';

  @override
  String errorDeletingEventMessage(String error) {
    return '刪除活動時發生錯誤：$error';
  }

  @override
  String get removeEventTitle => '取消約診';

  @override
  String get removeEventMessage => '此活動將被標記為已移除，但仍會以刪除線顯示。';

  @override
  String get reasonForRemovalField => '移除原因：';

  @override
  String get removeButton => '移除';

  @override
  String get changeEventTimeTitle => '變更約診時間';

  @override
  String get changeTimeMessage => '這將建立一個新活動並使用更新的時間，並將原活動標記為已移除。';

  @override
  String get reasonForTimeChangeField => '時間變更原因： *';

  @override
  String get changeTimeButton => '變更時間';

  @override
  String errorChangingEventTimeMessage(String error) {
    return '變更活動時間時發生錯誤：$error';
  }

  @override
  String get heavyLoadTest => '重量測試';

  @override
  String get heavyLoadTestWarning =>
      '此測試將產生 2,928 個活動與約 8,800 萬個資料點，可能需要數分鐘時間。';

  @override
  String get heavyLoadTestConfirm => '開始重量測試';

  @override
  String heavyLoadTestProgress(int count, int total, int percent) {
    return '產生中：$count/$total ($percent%)';
  }

  @override
  String heavyLoadTestComplete(int events, int strokes, String time) {
    return '已產生 $events 個活動，共 $strokes 個筆畫，耗時 $time';
  }

  @override
  String get clearExistingEvents => '清除現有活動';

  @override
  String get generatingEvents => '產生活動中...';

  @override
  String get stage1Creating => '階段 1/2：建立活動';

  @override
  String get stage2AddingStrokes => '階段 2/2：加入筆畫';

  @override
  String get heavyLoadStage1Only => '重量測試 - 階段1';

  @override
  String get heavyLoadStage2Only => '重量測試 - 階段2';

  @override
  String get stage1OnlyWarning => '建立 11,712 個空白活動（不含筆畫）\n每個格子4個活動';

  @override
  String get stage2OnlyWarning => '為現有 HEAVY- 活動加入筆畫（750筆畫/活動）';

  @override
  String stage1Complete(int events) {
    return '階段1完成：已建立 $events 個活動';
  }

  @override
  String stage2Complete(int events, int strokes, String time) {
    return '階段2完成：已加入 $strokes 個筆畫到 $events 個活動，耗時 $time';
  }

  @override
  String get offlineMode => '離線模式';

  @override
  String get showingCachedData => '顯示已快取的資料';

  @override
  String get syncingToServer => '正在同步到伺服器...';

  @override
  String get noteSaved => '筆記已儲存';

  @override
  String errorSavingNote(String error) {
    return '儲存筆記時發生錯誤：$error';
  }

  @override
  String get unsavedChanges => '未儲存的變更';

  @override
  String get unsavedChangesMessage => '您有未儲存的變更。確定要離開嗎？';

  @override
  String get discard => '捨棄';

  @override
  String get keepEditing => '繼續編輯';

  @override
  String get queryAppointments => '查詢預約記錄';

  @override
  String get search => '搜尋';

  @override
  String get errorLoadingData => '載入資料時發生錯誤';

  @override
  String get nameRequired => '名稱為必填項目';

  @override
  String get errorSearching => '搜尋時發生錯誤';

  @override
  String get noRecordNumbers => '沒有病例號';

  @override
  String get selectRecordNumber => '選擇病例號';

  @override
  String get enterSearchCriteria => '輸入搜尋條件以查詢預約記錄';

  @override
  String get noAppointmentsFound => '找不到符合條件的預約記錄';

  @override
  String get enterNameFirst => '請先輸入姓名';

  @override
  String get noMatchingRecordNumbers => '沒有符合的病例號';
}

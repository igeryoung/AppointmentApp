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
    return '您確定要永久刪除「$bookName」及其所有約診嗎？';
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
  String get twoDays => '两日';

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
  String get createEvent => '建立約診';

  @override
  String errorLoadingEvents(String error) {
    return '載入約診時發生錯誤：$error';
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
  String get editEvent => '編輯約診';

  @override
  String get eventName => '約診名稱 *';

  @override
  String get eventNameRequired => '約診名稱為必填項目';

  @override
  String get recordNumber => '紀錄編號';

  @override
  String get recordNumberRequired => '紀錄編號為必填項目';

  @override
  String get phone => '電話';

  @override
  String get chargeItems => '待收款項';

  @override
  String get chargeItemName => '項目名稱';

  @override
  String get chargeItemCost => '費用';

  @override
  String get addChargeItem => '新增待收款項';

  @override
  String get addChargeItemTitle => '新增待收款項';

  @override
  String get editChargeItemTitle => '編輯待收款項';

  @override
  String get paid => '已付';

  @override
  String get chargeItemPaidAmount => '已付金額';

  @override
  String get addChargeItemPayment => '新增已付項目';

  @override
  String get chargeItemPaymentAmount => '已付項目金額';

  @override
  String get chargeItemPaymentDate => '付款日期';

  @override
  String get total => '總額';

  @override
  String get chargeItemNameRequired => '項目名稱為必填項目';

  @override
  String get chargeItemCostInvalid => '費用必須為正整數';

  @override
  String get chargeItemCostBelowPaidAmount => '費用不可低於已付總額';

  @override
  String get chargeItemPaidAmountInvalid => '已付金額必須為 0 或正整數';

  @override
  String get chargeItemPaidAmountExceedsCost => '已付金額不可超過費用';

  @override
  String get chargeItemPaymentAmountExceedsRemaining => '已付項目金額不可超過剩餘金額';

  @override
  String get chargeItemPaymentDateInvalid => '請選擇有效的付款日期';

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
  String get deleteEventConfirmation => '您確定要刪除此約診及其筆記嗎？';

  @override
  String get removeEvent => '取消約診';

  @override
  String get removeEventDescription => '此約診將被標記為已移除，但仍會以刪除線顯示。';

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
  String get eventTypeChanged => '約診類型已更新';

  @override
  String errorUpdatingEvent(String error) {
    return '更新約診時發生錯誤：$error';
  }

  @override
  String get eventDeleted => '約診已刪除';

  @override
  String confirmDeleteEvent(String eventName) {
    return '您確定要刪除「$eventName」及其筆記嗎？';
  }

  @override
  String get changeTimeDescription => '這將建立一個新約診並使用更新的時間，並將原約診標記為已移除。';

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
  String get reasonRequiredMessage => '必須提供原因才能變更約診時間。';

  @override
  String get changeTime => '變更時間';

  @override
  String get eventTimeChangedSuccess => '約診時間變更成功';

  @override
  String errorChangingEventTime(String error) {
    return '變更約診時間時發生錯誤：$error';
  }

  @override
  String get retry => '重試';

  @override
  String get deletePermanently => '永久刪除';

  @override
  String get processing => '處理中...';

  @override
  String get eventTimeChanged => '約診時間已變更';

  @override
  String get eventRemoved => '約診已移除';

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
    return '儲存約診時發生錯誤：$error';
  }

  @override
  String get eventSavedNoteFailure => '約診已儲存，但筆記儲存失敗';

  @override
  String errorDeletingEvent(String error) {
    return '刪除約診時發生錯誤：$error';
  }

  @override
  String errorRemovingEvent(String error) {
    return '移除約診時發生錯誤：$error';
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
  String get eventTimeChangedSuccessfully => '約診時間變更成功';

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
  String get eventRemovedSuccessfully => '約診已成功移除';

  @override
  String errorRemovingEventMessage(String error) {
    return '移除約診時發生錯誤：$error';
  }

  @override
  String get generateRandomEvents => '產生隨機約診';

  @override
  String get numberOfEvents => '約診數量';

  @override
  String get enterNumber => '輸入數字（1-50）';

  @override
  String get clearAllExistingEventsFirst => '先清除所有現有約診';

  @override
  String get generateOpenEndedEventsOnly => '僅產生不設結束時間的約診';

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
    return '已清除所有約診並產生 $count 個約診';
  }

  @override
  String clearedAndGeneratedEventsSomeFull(int count) {
    return '已清除所有約診並產生 $count 個約診（部分時段已滿）';
  }

  @override
  String clearedAndGeneratedOpenEndedEvents(int count) {
    return '已清除所有約診並產生 $count 個不設結束時間的約診';
  }

  @override
  String clearedAndGeneratedOpenEndedEventsSomeFull(int count) {
    return '已清除所有約診並產生 $count 個不設結束時間的約診（部分時段已滿）';
  }

  @override
  String generatedEvents(int count) {
    return '已產生 $count 個隨機約診';
  }

  @override
  String generatedEventsSomeFull(int count) {
    return '已產生 $count 個約診（部分時段已滿）';
  }

  @override
  String generatedOpenEndedEvents(int count) {
    return '已產生 $count 個不設結束時間的約診';
  }

  @override
  String generatedOpenEndedEventsSomeFull(int count) {
    return '已產生 $count 個不設結束時間的約診（部分時段已滿）';
  }

  @override
  String get goToTodayTooltip => '前往今天';

  @override
  String get eventOptions => '約診選項';

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
  String get eventSavedButNoteFailed => '約診已儲存，但筆記儲存失敗';

  @override
  String errorSavingEventMessage(String error) {
    return '儲存約診時發生錯誤：$error';
  }

  @override
  String get deleteEventTitle => '刪除約診';

  @override
  String get deleteEventConfirmMessage => '您確定要刪除此約診及其筆記嗎？';

  @override
  String get deleteButton => '刪除';

  @override
  String errorDeletingEventMessage(String error) {
    return '刪除約診時發生錯誤：$error';
  }

  @override
  String get removeEventTitle => '取消約診';

  @override
  String get removeEventMessage => '此約診將被標記為已移除，但仍會以刪除線顯示。';

  @override
  String get reasonForRemovalField => '移除原因：';

  @override
  String get removeButton => '移除';

  @override
  String get changeEventTimeTitle => '變更約診時間';

  @override
  String get changeTimeMessage => '這將建立一個新約診並使用更新的時間，並將原約診標記為已移除。';

  @override
  String get reasonForTimeChangeField => '時間變更原因： *';

  @override
  String get changeTimeButton => '變更時間';

  @override
  String errorChangingEventTimeMessage(String error) {
    return '變更約診時間時發生錯誤：$error';
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

  @override
  String get chargeItemsRequireRecordNumber => '请添加记录编号以追踪收费项目';

  @override
  String get serverSetupTitle => '服务器设置';

  @override
  String get serverSetupSubtitle => '请输入服务器网址以开始使用';

  @override
  String get deviceRegistrationTitle => '设备注册';

  @override
  String get deviceRegistrationSubtitle => '此设备尚未注册，请输入注册密码';

  @override
  String get serverUrlLabel => '服务器网址';

  @override
  String get serverUrlRequired => '服务器网址为必填项目';

  @override
  String get serverUrlInvalid => '网址格式无效（需以 http:// 或 https:// 开头）';

  @override
  String get registrationPasswordLabel => '注册密码';

  @override
  String get passwordRequired => '密码为必填项目';

  @override
  String get nextButton => '下一步';

  @override
  String get registerButton => '注册';

  @override
  String get backButton => '返回';

  @override
  String get showMenu => '显示菜单';

  @override
  String get hideMenu => '隐藏菜单';

  @override
  String get enterDrawingMode => '进入绘图模式';

  @override
  String get exitDrawingMode => '退出绘图模式';

  @override
  String get duration => '时长';

  @override
  String get hoursUnit => '小时';

  @override
  String get minutesUnit => '分';

  @override
  String get selectReason => '请选择原因';

  @override
  String get enterOtherReasonHint => '请输入其他原因...';

  @override
  String get enterOtherReasonRequired => '请输入其他原因';

  @override
  String get today => '今天';

  @override
  String get dayEventSummaryTooltip => '显示当天活动汇总';

  @override
  String get dayEventSummaryTitle => '当天活动汇总';

  @override
  String dayEventSummaryTotalEvents(int count) {
    return '活动总数：$count';
  }

  @override
  String get dayEventSummaryTypeBreakdown => '类型统计';

  @override
  String get dayEventSummaryNoEvents => '这一天没有活动。';

  @override
  String dayEventSummaryTypeCount(String type, int count) {
    return '$type：$count';
  }

  @override
  String selectedTypesCount(Object count) {
    return '已选择：$count 种';
  }

  @override
  String eventTypesOverflowSummary(
    Object firstType,
    Object remainingCount,
    Object secondType,
  ) {
    return '$firstType、$secondType，另外 $remainingCount 种';
  }

  @override
  String errorInitializingServices(Object error) {
    return '初始化服务失败，部分功能可能无法使用：$error';
  }

  @override
  String endTimeCleared(Object error) {
    return '已清除结束时间：$error';
  }

  @override
  String get syncingEvent => '正在同步活动...';

  @override
  String get loadingEvent => '正在加载活动...';

  @override
  String get viewEvent => '查看活动';

  @override
  String get unsyncedChangesLabel => '未同步变更';

  @override
  String get offlineLabel => '离线';

  @override
  String get readOnlyModeTooltip => '只读模式：已停用数据编辑与手写功能。';

  @override
  String get readOnlyModeLabel => '只读模式';

  @override
  String daysBackwardTooltip(Object days) {
    return '向前 $days 天';
  }

  @override
  String daysForwardTooltip(Object days) {
    return '向后 $days 天';
  }

  @override
  String errorMessage(Object message) {
    return '错误：$message';
  }

  @override
  String get dismiss => '关闭';

  @override
  String get readOnlyBookModeActive => '已启用只读模式：仅可查看，编辑功能已停用。';

  @override
  String get importFromServer => '从服务器导入';

  @override
  String get serverSettings => '服务器设置';

  @override
  String get importBookFromServer => '从服务器导入簿册';

  @override
  String get noServerBooksAvailable => '服务器上没有可导入的簿册';

  @override
  String bookUuidShort(Object id) {
    return '簿册 UUID：$id...';
  }

  @override
  String ownerDeviceShort(Object id) {
    return '拥有者设备：$id...';
  }

  @override
  String get serverUrlHint => 'http://192.168.1.100:8080';

  @override
  String get cannotConnectToServerCheckUrl => '无法连接到服务器，请检查网址。';

  @override
  String get configureServerUrlDescription => '配置服务器网址以进行服务器数据操作。';

  @override
  String get serverUrlExample => '示例：http://your-mac-ip:8080';

  @override
  String get enterPasswordHint => '请输入密码';

  @override
  String get contactServerAdminForPassword => '请向服务器管理员获取密码';

  @override
  String errorCheckingDeviceRegistration(Object error) {
    return '检查设备注册状态时发生错误：$error';
  }

  @override
  String get invalidPasswordTryAgain => '密码错误，请重试。';

  @override
  String registrationFailed(Object error) {
    return '注册失败：$error';
  }

  @override
  String get bookPassword => '簿册密码';

  @override
  String get details => '详情';

  @override
  String get success => '成功';

  @override
  String get errorLabel => '错误';

  @override
  String get warning => '警告';

  @override
  String get info => '信息';

  @override
  String get messageCopiedToClipboard => '消息已复制到剪贴板';

  @override
  String get copy => '复制';

  @override
  String get readOnlyCreateBookDisabled => '只读模式：无法创建簿册';

  @override
  String get readOnlyRenameDisabled => '只读模式：无法重命名簿册';

  @override
  String get readOnlyArchiveDisabled => '只读模式：无法封存簿册';

  @override
  String get readOnlyDeleteDisabled => '只读模式：无法删除簿册';

  @override
  String get enterBookPassword => '输入簿册密码';

  @override
  String get importBookPasswordRequiredDescription => '导入此簿册需要密码。';

  @override
  String get bookImportedSuccessfully => '簿册导入成功';

  @override
  String get importFailedBookAlreadyExists => '导入失败：此设备已存在该簿册。';

  @override
  String get importFailedInvalidBookPassword => '导入失败：簿册密码错误。';

  @override
  String get importFailedApiBooksNotFound =>
      '导入失败：服务器找不到 /api/books。请更新或重启服务器，并确认服务器设置中的网址。';

  @override
  String get importFailedInvalidDeviceCredentials =>
      '导入失败：设备凭证无效。请在服务器设置中重新注册此设备。';

  @override
  String failedToLoadServerBooks(Object error) {
    return '加载服务器簿册失败：$error';
  }

  @override
  String serverUrlUpdated(Object url) {
    return '服务器网址已更新为：$url';
  }

  @override
  String failedToUpdateServerUrl(Object error) {
    return '更新服务器网址失败：$error';
  }

  @override
  String cannotMoveEndTimeExceedsLimit(Object hour, Object minute) {
    return '无法移动：结束时间将为 $hour:$minute（超过 21:00）';
  }

  @override
  String get eventsCannotSpanAcrossDates => '活动不可跨日期';

  @override
  String get testTimeDialogPlaceholder => '测试时间对话框（功能已拆分）';

  @override
  String get otherEventType => '其他';

  @override
  String chargeAmountSummary(Object received, Object total) {
    return 'NT\$$received / NT\$$total';
  }

  @override
  String get thisEventTime => '此次活动时间';

  @override
  String get thisEventFocus => '聚焦此次活动（其他淡化）';

  @override
  String get allItems => '全部项目';

  @override
  String get highlighterWidth => '荧光笔宽度';

  @override
  String syncedOfflineNotes(Object total) {
    return '已同步 $total 条离线笔记';
  }

  @override
  String syncPartialNotesFailed(Object failed, Object success, Object total) {
    return '已同步 $success/$total 条笔记，$failed 条失败，请确认服务器上已有该簿册';
  }

  @override
  String get syncFailedTitle => '同步失败';

  @override
  String get syncFailedDetail =>
      '部分笔记同步失败，可能因为服务器尚未有此簿册。\\n\\n解决方式：请先在服务器创建或导入该簿册。';
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
    return '您確定要永久刪除「$bookName」及其所有約診嗎？';
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
  String get twoDays => '兩日';

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
  String get createEvent => '建立約診';

  @override
  String errorLoadingEvents(String error) {
    return '載入約診時發生錯誤：$error';
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
  String get editEvent => '編輯約診';

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
  String get chargeItems => '待收款項';

  @override
  String get chargeItemName => '項目名稱';

  @override
  String get chargeItemCost => '費用';

  @override
  String get addChargeItem => '新增待收款項';

  @override
  String get addChargeItemTitle => '新增待收款項';

  @override
  String get editChargeItemTitle => '編輯待收款項';

  @override
  String get paid => '已付';

  @override
  String get chargeItemPaidAmount => '已付金額';

  @override
  String get addChargeItemPayment => '新增已付項目';

  @override
  String get chargeItemPaymentAmount => '已付項目金額';

  @override
  String get chargeItemPaymentDate => '付款日期';

  @override
  String get total => '總額';

  @override
  String get chargeItemNameRequired => '項目名稱為必填項目';

  @override
  String get chargeItemCostInvalid => '費用必須為正整數';

  @override
  String get chargeItemCostBelowPaidAmount => '費用不可低於已付總額';

  @override
  String get chargeItemPaidAmountInvalid => '已付金額必須為 0 或正整數';

  @override
  String get chargeItemPaidAmountExceedsCost => '已付金額不可超過費用';

  @override
  String get chargeItemPaymentAmountExceedsRemaining => '已付項目金額不可超過剩餘金額';

  @override
  String get chargeItemPaymentDateInvalid => '請選擇有效的付款日期';

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
  String get deleteEventConfirmation => '您確定要刪除此約診及其筆記嗎？';

  @override
  String get removeEvent => '取消約診';

  @override
  String get removeEventDescription => '此約診將被標記為已移除，但仍會以刪除線顯示。';

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
  String get eventTypeChanged => '約診類型已更新';

  @override
  String errorUpdatingEvent(String error) {
    return '更新約診時發生錯誤：$error';
  }

  @override
  String get eventDeleted => '約診已刪除';

  @override
  String confirmDeleteEvent(String eventName) {
    return '您確定要刪除「$eventName」及其筆記嗎？';
  }

  @override
  String get changeTimeDescription => '這將建立一個新約診並使用更新的時間，並將原約診標記為已移除。';

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
  String get reasonRequiredMessage => '必須提供變更約診時間的原因。';

  @override
  String get changeTime => '變更時間';

  @override
  String get eventTimeChangedSuccess => '約診時間變更成功';

  @override
  String errorChangingEventTime(String error) {
    return '變更約診時間時發生錯誤：$error';
  }

  @override
  String get retry => '重試';

  @override
  String get deletePermanently => '永久刪除';

  @override
  String get processing => '處理中...';

  @override
  String get eventTimeChanged => '約診時間已變更';

  @override
  String get eventRemoved => '約診已移除';

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
    return '儲存約診時發生錯誤：$error';
  }

  @override
  String get eventSavedNoteFailure => '約診已儲存，但筆記儲存失敗';

  @override
  String errorDeletingEvent(String error) {
    return '刪除約診時發生錯誤：$error';
  }

  @override
  String errorRemovingEvent(String error) {
    return '移除約診時發生錯誤：$error';
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
  String get eventTimeChangedSuccessfully => '約診時間變更成功';

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
  String get eventRemovedSuccessfully => '約診已成功移除';

  @override
  String errorRemovingEventMessage(String error) {
    return '移除約診時發生錯誤：$error';
  }

  @override
  String get generateRandomEvents => '產生隨機約診';

  @override
  String get numberOfEvents => '約診數量';

  @override
  String get enterNumber => '輸入數字（1-50）';

  @override
  String get clearAllExistingEventsFirst => '先清除所有現有約診';

  @override
  String get generateOpenEndedEventsOnly => '僅產生不設結束時間的約診';

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
    return '已清除所有約診並產生 $count 個約診';
  }

  @override
  String clearedAndGeneratedEventsSomeFull(int count) {
    return '已清除所有約診並產生 $count 個約診（部分時段已滿）';
  }

  @override
  String clearedAndGeneratedOpenEndedEvents(int count) {
    return '已清除所有約診並產生 $count 個不設結束時間的約診';
  }

  @override
  String clearedAndGeneratedOpenEndedEventsSomeFull(int count) {
    return '已清除所有約診並產生 $count 個不設結束時間的約診（部分時段已滿）';
  }

  @override
  String generatedEvents(int count) {
    return '已產生 $count 個隨機約診';
  }

  @override
  String generatedEventsSomeFull(int count) {
    return '已產生 $count 個約診（部分時段已滿）';
  }

  @override
  String generatedOpenEndedEvents(int count) {
    return '已產生 $count 個不設結束時間的約診';
  }

  @override
  String generatedOpenEndedEventsSomeFull(int count) {
    return '已產生 $count 個不設結束時間的約診（部分時段已滿）';
  }

  @override
  String get goToTodayTooltip => '前往今天';

  @override
  String get eventOptions => '約診選項';

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
  String get eventSavedButNoteFailed => '約診已儲存，但筆記儲存失敗';

  @override
  String errorSavingEventMessage(String error) {
    return '儲存約診時發生錯誤：$error';
  }

  @override
  String get deleteEventTitle => '刪除約診';

  @override
  String get deleteEventConfirmMessage => '您確定要刪除此約診及其筆記嗎？';

  @override
  String get deleteButton => '刪除';

  @override
  String errorDeletingEventMessage(String error) {
    return '刪除約診時發生錯誤：$error';
  }

  @override
  String get removeEventTitle => '取消約診';

  @override
  String get removeEventMessage => '此約診將被標記為已移除，但仍會以刪除線顯示。';

  @override
  String get reasonForRemovalField => '移除原因：';

  @override
  String get removeButton => '移除';

  @override
  String get changeEventTimeTitle => '變更約診時間';

  @override
  String get changeTimeMessage => '這將建立一個新約診並使用更新的時間，並將原約診標記為已移除。';

  @override
  String get reasonForTimeChangeField => '時間變更原因： *';

  @override
  String get changeTimeButton => '變更時間';

  @override
  String errorChangingEventTimeMessage(String error) {
    return '變更約診時間時發生錯誤：$error';
  }

  @override
  String get heavyLoadTest => '重量測試';

  @override
  String get heavyLoadTestWarning =>
      '此測試將產生 2,928 個約診與約 8,800 萬個資料點，可能需要數分鐘時間。';

  @override
  String get heavyLoadTestConfirm => '開始重量測試';

  @override
  String heavyLoadTestProgress(int count, int total, int percent) {
    return '產生中：$count/$total ($percent%)';
  }

  @override
  String heavyLoadTestComplete(int events, int strokes, String time) {
    return '已產生 $events 個約診，共 $strokes 個筆畫，耗時 $time';
  }

  @override
  String get clearExistingEvents => '清除現有約診';

  @override
  String get generatingEvents => '產生約診中...';

  @override
  String get stage1Creating => '階段 1/2：建立約診';

  @override
  String get stage2AddingStrokes => '階段 2/2：加入筆畫';

  @override
  String get heavyLoadStage1Only => '重量測試 - 階段1';

  @override
  String get heavyLoadStage2Only => '重量測試 - 階段2';

  @override
  String get stage1OnlyWarning => '建立 11,712 個空白約診（不含筆畫）\n每個格子4個約診';

  @override
  String get stage2OnlyWarning => '為現有 HEAVY- 約診加入筆畫（750筆畫/約診）';

  @override
  String stage1Complete(int events) {
    return '階段1完成：已建立 $events 個約診';
  }

  @override
  String stage2Complete(int events, int strokes, String time) {
    return '階段2完成：已加入 $strokes 個筆畫到 $events 個約診，耗時 $time';
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

  @override
  String get chargeItemsRequireRecordNumber => '請新增病例號以追蹤待收款項';

  @override
  String get serverSetupTitle => '伺服器設定';

  @override
  String get serverSetupSubtitle => '請輸入伺服器網址以開始使用';

  @override
  String get deviceRegistrationTitle => '裝置註冊';

  @override
  String get deviceRegistrationSubtitle => '此裝置尚未註冊，請輸入註冊密碼';

  @override
  String get serverUrlLabel => '伺服器網址';

  @override
  String get serverUrlRequired => '伺服器網址為必填項目';

  @override
  String get serverUrlInvalid => '網址格式無效（需以 http:// 或 https:// 開頭）';

  @override
  String get registrationPasswordLabel => '註冊密碼';

  @override
  String get passwordRequired => '密碼為必填項目';

  @override
  String get nextButton => '下一步';

  @override
  String get registerButton => '註冊';

  @override
  String get backButton => '返回';

  @override
  String get showMenu => '顯示選單';

  @override
  String get hideMenu => '隱藏選單';

  @override
  String get enterDrawingMode => '進入繪圖模式';

  @override
  String get exitDrawingMode => '離開繪圖模式';

  @override
  String get duration => '時長';

  @override
  String get hoursUnit => '小時';

  @override
  String get minutesUnit => '分';

  @override
  String get selectReason => '請選擇原因';

  @override
  String get enterOtherReasonHint => '請輸入其他原因...';

  @override
  String get enterOtherReasonRequired => '請輸入其他原因';

  @override
  String get today => '今天';

  @override
  String get dayEventSummaryTooltip => '顯示當天約診摘要';

  @override
  String get dayEventSummaryTitle => '當天約診摘要';

  @override
  String dayEventSummaryTotalEvents(int count) {
    return '約診總數：$count';
  }

  @override
  String get dayEventSummaryTypeBreakdown => '類型統計';

  @override
  String get dayEventSummaryNoEvents => '這一天沒有約診。';

  @override
  String dayEventSummaryTypeCount(String type, int count) {
    return '$type：$count';
  }

  @override
  String selectedTypesCount(Object count) {
    return '已選擇：$count 種';
  }

  @override
  String eventTypesOverflowSummary(
    Object firstType,
    Object remainingCount,
    Object secondType,
  ) {
    return '$firstType、$secondType，另外 $remainingCount 種';
  }

  @override
  String errorInitializingServices(Object error) {
    return '初始化服務失敗，部分功能可能無法使用：$error';
  }

  @override
  String endTimeCleared(Object error) {
    return '已清除結束時間：$error';
  }

  @override
  String get syncingEvent => '正在同步約診...';

  @override
  String get loadingEvent => '正在載入約診...';

  @override
  String get viewEvent => '檢視約診';

  @override
  String get unsyncedChangesLabel => '未同步變更';

  @override
  String get offlineLabel => '離線';

  @override
  String get readOnlyModeTooltip => '唯讀模式：已停用資料編輯與手寫功能。';

  @override
  String get readOnlyModeLabel => '唯讀模式';

  @override
  String daysBackwardTooltip(Object days) {
    return '往前 $days 天';
  }

  @override
  String daysForwardTooltip(Object days) {
    return '往後 $days 天';
  }

  @override
  String errorMessage(Object message) {
    return '錯誤：$message';
  }

  @override
  String get dismiss => '關閉';

  @override
  String get readOnlyBookModeActive => '已啟用唯讀模式：僅可檢視，編輯功能已停用。';

  @override
  String get importFromServer => '從伺服器匯入';

  @override
  String get serverSettings => '伺服器設定';

  @override
  String get importBookFromServer => '從伺服器匯入簿冊';

  @override
  String get noServerBooksAvailable => '伺服器上沒有可匯入的簿冊';

  @override
  String bookUuidShort(Object id) {
    return '簿冊 UUID：$id...';
  }

  @override
  String ownerDeviceShort(Object id) {
    return '擁有者裝置：$id...';
  }

  @override
  String get serverUrlHint => 'http://192.168.1.100:8080';

  @override
  String get cannotConnectToServerCheckUrl => '無法連線到伺服器，請檢查網址。';

  @override
  String get configureServerUrlDescription => '設定伺服器網址以進行伺服器資料操作。';

  @override
  String get serverUrlExample => '範例：http://your-mac-ip:8080';

  @override
  String get enterPasswordHint => '請輸入密碼';

  @override
  String get contactServerAdminForPassword => '請向伺服器管理員取得密碼';

  @override
  String errorCheckingDeviceRegistration(Object error) {
    return '檢查裝置註冊狀態時發生錯誤：$error';
  }

  @override
  String get invalidPasswordTryAgain => '密碼錯誤，請再試一次。';

  @override
  String registrationFailed(Object error) {
    return '註冊失敗：$error';
  }

  @override
  String get bookPassword => '簿冊密碼';

  @override
  String get details => '詳情';

  @override
  String get success => '成功';

  @override
  String get errorLabel => '錯誤';

  @override
  String get warning => '警告';

  @override
  String get info => '資訊';

  @override
  String get messageCopiedToClipboard => '訊息已複製到剪貼簿';

  @override
  String get copy => '複製';

  @override
  String get readOnlyCreateBookDisabled => '唯讀模式：無法建立簿冊';

  @override
  String get readOnlyRenameDisabled => '唯讀模式：無法重新命名簿冊';

  @override
  String get readOnlyArchiveDisabled => '唯讀模式：無法封存簿冊';

  @override
  String get readOnlyDeleteDisabled => '唯讀模式：無法刪除簿冊';

  @override
  String get enterBookPassword => '輸入簿冊密碼';

  @override
  String get importBookPasswordRequiredDescription => '匯入此簿冊需要密碼。';

  @override
  String get bookImportedSuccessfully => '簿冊匯入成功';

  @override
  String get importFailedBookAlreadyExists => '匯入失敗：此裝置已存在該簿冊。';

  @override
  String get importFailedInvalidBookPassword => '匯入失敗：簿冊密碼錯誤。';

  @override
  String get importFailedApiBooksNotFound =>
      '匯入失敗：伺服器找不到 /api/books。請更新或重啟伺服器，並確認伺服器設定中的網址。';

  @override
  String get importFailedInvalidDeviceCredentials =>
      '匯入失敗：裝置憑證無效。請在伺服器設定中重新註冊此裝置。';

  @override
  String failedToLoadServerBooks(Object error) {
    return '載入伺服器簿冊失敗：$error';
  }

  @override
  String serverUrlUpdated(Object url) {
    return '伺服器網址已更新為：$url';
  }

  @override
  String failedToUpdateServerUrl(Object error) {
    return '更新伺服器網址失敗：$error';
  }

  @override
  String cannotMoveEndTimeExceedsLimit(Object hour, Object minute) {
    return '無法移動：結束時間將為 $hour:$minute（超過 21:00）';
  }

  @override
  String get eventsCannotSpanAcrossDates => '約診不可跨日期';

  @override
  String get testTimeDialogPlaceholder => '測試時間對話框（功能已拆分）';

  @override
  String get otherEventType => '其他';

  @override
  String chargeAmountSummary(Object received, Object total) {
    return 'NT\$$received / NT\$$total';
  }

  @override
  String get thisEventTime => '此次約診時間';

  @override
  String get thisEventFocus => '聚焦此次約診（其他淡化）';

  @override
  String get allItems => '全部項目';

  @override
  String get highlighterWidth => '螢光筆寬度';

  @override
  String syncedOfflineNotes(Object total) {
    return '已同步 $total 筆離線筆記';
  }

  @override
  String syncPartialNotesFailed(Object failed, Object success, Object total) {
    return '已同步 $success/$total 筆筆記，$failed 筆失敗，請確認伺服器上已有該簿冊';
  }

  @override
  String get syncFailedTitle => '同步失敗';

  @override
  String get syncFailedDetail =>
      '部分筆記同步失敗，可能因為伺服器尚未有此簿冊。\\n\\n解決方式：請先在伺服器建立或匯入該簿冊。';
}

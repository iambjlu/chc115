# chc115 專案架構文件

## 專案簡介

`chc115` 是一個 Flutter 行動應用，實作「騎乘後方雷達 HUD」（Ride HUD）：
畫面上半部顯示即時車速與 Google 地圖（夜間樣式、依裝置目前位置置中），
下半部則以自訂雷達視圖呈現左右後方來車的威脅程度（安全／注意／危險）與
前方坑洞路況預警。左下角浮動按鈕可開啟「模擬控制面板」，用來手動調整
車速、左右後方車距／是否逼近、前方坑洞開關等數值，方便在沒有真實感測
硬體的情況下展示與測試 HUD 的各種狀態。

- 平台：Flutter App（Android、iOS）
- 語言：Dart（SDK `^3.7.2`）
- 主要套件：`google_maps_flutter`、`geolocator`

## 目錄結構

```
chc115/
├── lib/                        # 應用程式原始碼
│   ├── main.dart                # App 進入點（MaterialApp 設定）
│   ├── models/                  # 純資料模型（不含 Widget）
│   │   ├── simulation_values.dart
│   │   └── vehicle_threat.dart
│   ├── screens/                 # 頁面層（組合各個 widget）
│   │   └── ride_hud_screen.dart
│   ├── widgets/                 # 可重用/局部 UI 元件
│   │   ├── map_card.dart
│   │   ├── live_google_map.dart
│   │   ├── radar_view.dart
│   │   └── simulation_sheet.dart
│   ├── services/                # 與 UI 無關的服務層
│   │   └── alert_notification_service.dart
│   └── theme/                   # 視覺樣式
│       └── hud_colors.dart
├── assets/                      # 靜態資源（如 bike.png）
├── test/                        # Widget/單元測試
├── android/ , ios/               # 平台專案（原生殼層、金鑰設定）
└── pubspec.yaml                  # 套件與資源設定
```

## 分層架構

專案採用簡單的四層結構，資料單向由上層流向下層 UI：

```
main.dart
   │  建立 MaterialApp，套用 HudColors 主題
   ▼
screens/ride_hud_screen.dart      ← 狀態持有者（StatefulWidget）
   │  持有 SimulationValues 狀態；衍生出 List<VehicleThreat>
   ├──> widgets/map_card.dart → widgets/live_google_map.dart
   ├──> widgets/radar_view.dart（純顯示，依 threats/坑洞旗標繪製）
   └──> widgets/simulation_sheet.dart（modal bottom sheet，回傳新的 SimulationValues）
```

### models（資料模型）

- **`SimulationValues`**：不可變（`@immutable`）的模擬面板狀態，包含
  自身車速、左右後方距離與是否逼近、前方三個方向的坑洞開關。提供
  `copyWith` 供局部更新，並附帶 `demo` 常數作為初始展示資料。
- **`VehicleThreat`**：依「距離＋是否逼近」推導出的後方車輛威脅資訊。
  - `ThreatThresholds`：安全／注意／危險的距離門檻常數。
  - `level`（`ThreatLevel`：safe/caution/danger）：由距離換算。
  - `arcCount`：依威脅等級決定雷達要畫幾層弧線。
  - `label`：中文方位文字（「左後方」／「右後方」）。

### screens（頁面／狀態管理）

- **`RideHudScreen`**：唯一的頁面，也是狀態持有者。
  - 內部持有 `SimulationValues _sim`（初始為 `demo`）。
  - 由 `_sim` 衍生 `_threats`（`List<VehicleThreat>`）與 `_activeAlert`
    （何時該顯示逼近警示文字、顯示哪一側或雙側）。
  - `_openSimulationSheet()` 開啟 `SimulationSheet`，透過 `onChanged`
    回呼以 `setState` 更新 `_sim`，形成單向資料流：
    `SimulationSheet 使用者輸入 → RideHudScreen.setState → 重新計算 threats/alert → 往下傳給 RadarView`。
  - `_applySimulationValues()`：在 `setState` 更新前後比較新舊
    `SimulationValues`，觸發 `services/alert_notification_service.dart`
    的 `AlertNotificationService.notifyHazard()`（系統通知＋一次震動），
    分成三個類別各自呼叫，同類別新通知會覆蓋舊通知（見 services 章節
    的 `HazardCategory`），因此每個類別畫面上永遠只保留最新一則：
    - 距離縮短（`HazardCategory.distanceShortening`）：左右後方只要
      新距離比前一次更近（`leftDistance`／`rightDistance` 變小）就
      觸發一次，不論 `leftApproaching`／`rightApproaching` 開關是否
      開啟；標題為「左（右）後方車輛逐漸接近」。
    - 逼近車輛（`HazardCategory.approaching`）：`leftApproaching`／
      `rightApproaching` 由假變真才觸發一次，避免開關持續開啟時反覆
      通知；標題為「左（右）後方車輛逼近」，內文為「左（右）後方車輛
      正在逼近中」，只敘述目前狀態、不含變換車道等行動建議。
      畫面上的 `_AlertLines` 警示文字則只顯示
      「{左／右／左右}後方車輛快速逼近」單行狀態敘述，與通知內容分開。
    - 坑洞（`HazardCategory.pothole`）：左前/正前/右前皆由假變真才
      觸發一次，避免同一坑洞持續開啟時反覆通知；三個方向共用同一個
      通知 id，因此只會保留最新觸發的那一個方向。
  - 畫面內含三個私有元件：`_StatusBar`（車速讀數）、`_AlertLines`
    （後方車輛逼近警示，一行 `Icon(Icons.warning_rounded)` + 粗體文字）
    與 `_PotholeAlertLine`（坑洞提示文字，依左前/正前/右前順序列出
    目前亮起的方向，多個方向以「、」分隔，格式如「請注意左前、正前
    坑洞」；與系統通知並行顯示，樣式比照 `_AlertLines`）。這兩個提示
    元件皆固定保留一行高度、以 `AnimatedOpacity` 做淡入淡出（沒有提示
    時文字改為單一空白字元、opacity 降為 0），而非用 `AnimatedSize`
    整塊展開/收合，避免提示出現/消失時造成下方 `MapCard`／雷達視圖
    上下位移。

### services（服務層）

- **`HazardCategory`**（`enum`）：`pothole` / `approaching` /
  `distanceShortening` 三個危險事件類別，其 `index` 直接作為
  `flutter_local_notifications`（僅 Android 使用）的通知 id。
- **`AlertNotificationService`**：坑洞、車輛逼近等危險事件的提示單例
  （`instance`），Android 與 iOS 走完全不同路徑：
  - **Android**：`main.dart` 於 `runApp` 前呼叫 `init()` 建立通知頻道
    （`Importance.max` + 有聲音）並請求通知權限；`notifyHazard(
    {category, title, body})` 用 `flutter_local_notifications` 以
    `id: category.index` 顯示高優先權通知（heads-up）並搭配一次
    `HapticFeedback.heavyImpact()` 震動。由於同一 `category` 固定使用
    同一個通知 id，新通知會直接覆蓋舊通知，因此每個類別（坑洞／逼近
    車輛／距離縮短）在系統通知列表中永遠只會保留最新一則。
  - **iOS**：完全不使用 `UNUserNotificationCenter`、不申請通知權限
    （`init()` 對 iOS 直接 no-op，僅設定 `AudioPlayer`（`audioplayers`
    套件）的 `AudioContext` 為 `AVAudioSessionCategory.playback`，讓警示音
    忽略手機的靜音切換鍵）。原因是實測發現即使通知權限已授權，App 在
    前景時系統通知橫幅仍經常不會顯示（`interruptionLevel: timeSensitive`
    需要額外的時效性通知 entitlement，一般權限也無法保證前景橫幅一定
    跳出），因此改為 `notifyHazard()` 在 iOS 上直接用 `AudioPlayer`
    播放內建的 `assets/sounds/alert.wav`（取代原本會被靜音鍵靜音的
    `SystemSound.play()`），不再顯示任何系統通知橫幅；畫面提示改由
    `RideHudScreen._notifyHazard()` 在 iOS 上額外用 `ScaffoldMessenger`
    顯示浮動 `SnackBar`（`HudColors.danger` 背景、標題+內文兩行文字，
    顯示 3 秒，新警示會先 `hideCurrentSnackBar()` 再顯示），Android 則
    維持只靠系統通知呈現、不疊加 SnackBar。
  - 兩平台改為呼叫 `_longVibration()`：連續 3 次 `HapticFeedback
    .heavyImpact()`、中間間隔 150ms，模擬出比單次震動更明顯的長震動感。
  - 兩平台的 `notifyHazard()` 呼叫端（`RideHudScreen`）內容一律只
    敘述目前狀態（如「左後方車輛逐漸接近」），不包含變換車道等行動
    建議。

### widgets（UI 元件）

- **`MapCard`**：純包裝層，將 `LiveGoogleMap` 裁切為圓角卡片（固定高度 240）。
- **`LiveGoogleMap`**：
  - 用 `geolocator` 取得裝置目前位置；若定位失敗（權限被拒/服務關閉）
    或 8 秒內未能取得定位（`Geolocator.getCurrentPosition()` 加上
    `.timeout()`，避免 iOS 在收不到定位訊號時無限期卡在轉圈圈），
    回退到硬編碼的備援座標（南台科技大學一帶）。
  - 用 `google_maps_flutter` 顯示地圖，開啟原生「目前位置」藍點
    （`myLocationEnabled`），並提供右下角「回到目前位置」按鈕重新置中鏡頭。
  - Android/iOS 的 Google Maps API 金鑰分別位於
    `android/local.properties` 與 `ios/Flutter/ApiKeys.xcconfig`（不進版控）。
    版控中附上對應範本 `android/local.properties.example` 與
    `ios/Flutter/ApiKeys.xcconfig.example`（皆為 `MAPS_API_KEY=` 佔位字串），
    換機器/重新取回專案時複製成正式檔名（去掉 `.example`）並貼回真實
    金鑰即可，`android/local.properties` 的 `sdk.dir`／`flutter.sdk` 兩行則
    由本機 IDE／`flutter` 工具在開啟專案或執行指令時自動覆寫為正確路徑。
- **`RadarView`**：整個 HUD 的視覺核心，`StatefulWidget` + `LayoutBuilder`
  依容器寬高做響應式排版與縮放：
  - 中央置放車輛圖示（`assets/bike.png`）。
  - 用 `CustomPainter`（`_RadarArcsPainter`）依 `VehicleThreat.level` 畫出
    左／右後方的弧線（安全側多層綠色弧線、危險側單層貼近的紅色弧線，
    類似 Wi-Fi 訊號的視覺隱喻）。
  - 當某側標記為「逼近中」時，該側外緣顯示黃色警示三角形；用單一
    `Timer.periodic` 驅動 `_blinkVisible`，確保左右三角形硬切閃爍且節奏同步
    （刻意不做透明度補間）。
  - 車輛前方可疊加三個方向（左前／正前／右前）的鋸齒波形坑洞標記
    （`_PotholeMarker` + `_PotholeZigzagPainter`），純路況提示、不閃爍，
    與後方威脅的圓弧視覺明確做出區隔。
- **`SimulationSheet`**：`StatefulWidget`，以 modal bottom sheet 形式提供：
  - 車速滑桿（`_SliderField`）。
  - 左／右後方車輛的距離下拉選單（近/中/遠三檔）與逼近開關
    （`_ThreatGroup`，兩側各一組，分別用 `HudColors.safe` / `HudColors.danger`
    作為色標區分）。
  - 前方三個方向的坑洞開關（`SwitchListTile`）。
  - 每次變更都會即時呼叫 `onChanged` 回傳新的 `SimulationValues`，
    由 `RideHudScreen` 接手更新畫面，無内部暫存的「送出」流程。

### theme（樣式）

- **`HudColors`**：集中定義的色彩常數，整體介面採白底黑字高對比 HUD
  風格，只有地圖卡片使用深色（夜間地圖樣式）：
  - `surface` / `ink` 系列：主畫面底色與文字色階。
  - `brand` / `brandDim`：僅用於浮動按鈕、模擬面板等互動元件的品牌色。
  - `safe` / `warn` / `danger`（各附一組 `Dim` 淡色版本）：語意色，
    對應威脅等級與坑洞警示。

## 核心資料流

```
使用者操作 SimulationSheet
        │  onChanged(SimulationValues)
        ▼
RideHudScreen._sim  (setState)
        │
        ├─► _threats: List<VehicleThreat>  ──► RadarView（弧線＋警示三角形）
        ├─► _activeAlert                   ──► _AlertLines（頂部警示文字）
        └─► _sim.bikeSpeed                 ──► _StatusBar（車速讀數）
```

所有威脅判斷邏輯（安全/注意/危險門檻、弧線層數、方位標籤）都
集中在 `VehicleThreat`，UI 層（`RadarView`、`RideHudScreen`）只負責讀取
衍生後的結果進行繪製，不重複業務邏輯。

## 平台與設定重點

- **地圖金鑰**：`google_maps_flutter` 需要在 Android/iOS 專案內設定
  API 金鑰（見 `LiveGoogleMap` 檔案頂部註解所指路徑），這些檔案通常
  不納入版控，需另外設定。
- **定位權限**：`geolocator` 需要在 `android/app/src/main/AndroidManifest.xml`
  與 `ios/Runner/Info.plist` 中宣告對應的定位權限描述文字。
- **資源**：`assets/bike.png` 已在 `pubspec.yaml` 的 `assets:` 區塊註冊
  （整個 `assets/` 目錄）。

## 測試

- `test/widget_test.dart`：驗證初始畫面顯示車速 `25 km/h`，以及點擊
  浮動按鈕後能正確開啟「模擬控制」bottom sheet。

## 延伸開發建議

- 目前威脅來源（車速、車距、逼近狀態、坑洞）皆由 `SimulationSheet`
  手動模擬；若要串接真實感測資料（藍牙雷達模組、感測器等），建議在
  `RideHudScreen` 與資料來源之間新增一個 Repository/Service 層，
  以 Stream 方式推送 `SimulationValues`（或改為更貼近真實感測器的模型），
  取代目前由 UI 直接呼叫 `setState` 的模式。
- `RadarView` 的版面計算（弧線半徑、車輛與三角形位置）目前集中在單一
  `build` 方法內，邏輯較密集；後續若要支援更多威脅來源或不同雷達造型，
  可考慮拆出獨立的排版計算類別以利測試。

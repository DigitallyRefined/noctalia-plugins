import QtQuick
import QtMultimedia
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  property var pluginApi: null

  // Prayer data
  property var prayerTimings: null
  property string hijriDateStr: ""
  property string gregorianDateStr: ""
  property int hijriDayRaw: 0
  property int hijriDay: 0
  property int hijriMonth: 0
  property int hijriYear: 0
  property string hijriMonthNameEn: ""
  property string hijriMonthNameAr: ""
  property bool isRamadan: hijriMonth === 9

  // Fetch state
  property bool isLoading: false
  property bool hasError: false
  property string errorMessage: ""
  property string lastFetchDate: ""

  // Countdown state
  property int secondsToNext: -1
  property string nextPrayerName: ""

  // Azan state
  property bool azanPlaying: false

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string city:              cfg.city              ?? defaults.city              ?? "London"
  readonly property string country:           cfg.country           ?? defaults.country           ?? "UK"
  readonly property int    method:            cfg.method            ?? defaults.method            ?? 3
  readonly property int    school:            cfg.school            ?? defaults.school            ?? 0
  readonly property bool   showNotifications: cfg.showNotifications ?? defaults.showNotifications ?? true
  readonly property bool   playAzan:          cfg.playAzan          ?? defaults.playAzan          ?? false
  readonly property string azanFile:          cfg.azanFile          ?? defaults.azanFile          ?? "azan1.mp3"
  readonly property int    hijriDayOffset:    cfg.hijriDayOffset    ?? defaults.hijriDayOffset    ?? 0

  onHijriDayOffsetChanged: {
    if (hijriDayRaw > 0) {
      hijriDay = Math.max(1, Math.min(30, hijriDayRaw + hijriDayOffset))
      Logger.d("Mawaqit", "Hijri offset changed, day:", hijriDay)
    }
  }

  onSchoolChanged:        if (lastFetchDate) Qt.callLater(fetchPrayerTimes)

  readonly property var prayerKeys: {
    const base = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    return isRamadan ? ["Imsak"].concat(base) : base
  }

  readonly property var notificationKeys: ["Imsak", "Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

  // ── Audio ─────────────────────────────────────────────────────────────────

  MediaPlayer {
    id: azanPlayer
    audioOutput: AudioOutput { volume: 1.0 }
    onPlaybackStateChanged: {
      if (playbackState === MediaPlayer.StoppedState) {
        azanPlaying = false
        Logger.d("Mawaqit", "Azan finished")
      }
    }
    onErrorOccurred: (error, errorString) => {
      azanPlaying = false
      Logger.w("Mawaqit", "Azan error:", errorString)
    }
  }

  // Pre-load azan file so playback is instant at prayer time
  function preloadAzan() {
    if (!pluginApi?.pluginDir) return
    const filePath = `file://${pluginApi.pluginDir}/assets/${azanFile}`
    azanPlayer.source = filePath
    Logger.d("Mawaqit", "Azan preloaded:", filePath)
  }

  // Re-preload when user changes the azan file in settings
  onAzanFileChanged: Qt.callLater(preloadAzan)

  function playAzanFile(fileName) {
    const filePath = `file://${pluginApi.pluginDir}/assets/${fileName}`
    if (azanPlayer.source != filePath) {
      azanPlayer.stop()
      azanPlayer.source = filePath
    }
    azanPlayer.play()
    azanPlaying = true
    Logger.d("Mawaqit", "Playing azan:", filePath)
  }

  function stopAzanFile() {
    azanPlayer.stop()
    azanPlaying = false
    Logger.d("Mawaqit", "Azan stopped")
  }

  // ── Clock-synced timers ───────────────────────────────────────────────────
  //
  // Instead of a dumb 60s interval that drifts relative to the clock,
  // we first wait exactly until the next HH:MM:00 boundary (syncTimer),
  // then start a 60s repeat (updateTimer) that always fires on the minute.
  //
  // Example: plugin starts at 15:28:47
  //   syncTimer fires in (60-47)s = 13s → at 15:29:00 exactly
  //   updateTimer starts → fires at 15:30:00, 15:31:00, 15:32:00 ...
  //   checkPrayerTimes() always runs at :00 seconds — perfectly synced

  Timer {
    id: syncTimer
    repeat: false
    running: false
    onTriggered: {
      onClockTick()
      updateTimer.start()
    }
  }

  property string lastTickMinute: ""

  Timer {
    id: updateTimer
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      const now = new Date()
      const hhmm = `${now.getHours().toString().padStart(2,"0")}:${now.getMinutes().toString().padStart(2,"0")}`
      if (hhmm !== lastTickMinute) {
        lastTickMinute = hhmm
        onClockTick()
      }
    }
  }

    function onClockTick() {
    const today = new Date().toISOString().substring(0, 10)
    if (today !== lastFetchDate) {
      fetchPrayerTimes()
    } else {
      checkPrayerTimes()
      updateCountdown()
    }
  }

  function startSyncedTimer() {
    syncTimer.stop()
    updateTimer.stop()
    // Check immediately in case we loaded during a prayer minute
    checkPrayerTimes()
    updateCountdown()
    const now = new Date()
    const secsLeft = now.getSeconds() === 0 ? 0 : (60 - now.getSeconds())
    const msUntilNextMinute = Math.max(0, secsLeft * 1000 - now.getMilliseconds())
    if (msUntilNextMinute === 0) {
      onClockTick()
      updateTimer.start()
    } else {
      syncTimer.interval = msUntilNextMinute
      syncTimer.start()
    }
    Logger.d("Mawaqit", "Timer synced — next tick in", Math.round(msUntilNextMinute / 1000), "s")
  }

  // ── Prayer time check ─────────────────────────────────────────────────────

  property string lastNotifiedMinute: ""

  readonly property var prayerNamesAr: ({
    "Fajr":    "الفجر",
    "Dhuhr":   "الظهر",
    "Asr":     "العصر",
    "Maghrib": "المغرب",
    "Isha":    "العشاء",
    "Imsak":   "الإمساك"
  })

  function checkPrayerTimes() {
    if (!prayerTimings) return
    const now = new Date()
    const hhmm = `${now.getHours().toString().padStart(2,"0")}:${now.getMinutes().toString().padStart(2,"0")}`
    if (hhmm === lastNotifiedMinute) return  // already fired this minute
    for (const key of notificationKeys) {
      if (prayerTimings[key] === hhmm) {
        lastNotifiedMinute = hhmm
        onPrayerTime(key)
      }
    }
  }

  // notify-send for proper desktop notifications
  Process {
    id: notifProcess
    running: false
    onExited: notifProcess.running = false
  }

  function sendNotification(title, body) {
    notifProcess.command = ["notify-send", "-a", "Mawaqit", "-u", "critical", "-t", "10000", title, body]
    notifProcess.running = true
  }

  function onPrayerTime(prayerKey) {
    const timeStr = prayerTimings?.[prayerKey] || ""
    const isImsak = prayerKey === "Imsak"

    // Imsak — no azan, different message
    if (isImsak) {
      if (showNotifications) sendNotification("🌙 Imsak — " + timeStr, "حان وقت الإمساك")
      Logger.d("Mawaqit", "Imsak time:", timeStr)
      return
    }

    // Regular prayer — always Arabic prayer name, no Iftar label
    const arName = prayerNamesAr[prayerKey] || prayerKey
    if (showNotifications) sendNotification("🕌 " + prayerKey + " — " + timeStr, "حان الآن موعد صلاة " + arName)
    if (playAzan) playAzanFile(azanFile)
    Logger.d("Mawaqit", "Prayer time:", prayerKey, timeStr)
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Process {
    id: fetchProcess
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: exitCode => {
      isLoading = false
      if (stderr.text.trim()) Logger.w("Mawaqit", "curl stderr:", stderr.text.trim())
      if (exitCode === 0 && stdout.text.trim()) {
        parseResponse(stdout.text)
      } else {
        hasError = true
        errorMessage = pluginApi?.tr("error.network") || "Network request failed"
        Logger.w("Mawaqit", "Fetch failed, exit:", exitCode)
      }
    }
  }

  onCityChanged:    if (lastFetchDate) Qt.callLater(fetchPrayerTimes)
  onCountryChanged: if (lastFetchDate) Qt.callLater(fetchPrayerTimes)
  onMethodChanged:  if (lastFetchDate) Qt.callLater(fetchPrayerTimes)

  function fetchPrayerTimes() {
    if (fetchProcess.running) return
    isLoading = true
    hasError = false
    Logger.d("Mawaqit", "Fetching for", city, country, "method", method, "school", school)
    const url = `https://api.aladhan.com/v1/timingsByCity?city=${city.replace(/ /g,"%20")}&country=${country.replace(/ /g,"%20")}&method=${method}&school=${school}`
    fetchProcess.command = ["curl", "-s", "-L", "--max-time", "15", "-H", "User-Agent: Mozilla/5.0", url]
    fetchProcess.running = true
  }

  function parseResponse(text) {
    try {
      const json = JSON.parse(text)
      if (json.code === 200 && json.data) {
        const cleaned = {}
        for (const key in json.data.timings)
          cleaned[key] = json.data.timings[key].replace(/\s*\(.*\)/, "").trim()
        prayerTimings = cleaned

        const hijri = json.data.date.hijri
        hijriDayRaw      = parseInt(hijri.day)
        hijriDay         = Math.max(1, Math.min(30, hijriDayRaw + hijriDayOffset))
        hijriMonth       = hijri.month.number
        hijriYear        = parseInt(hijri.year)
        hijriMonthNameEn = hijri.month.en
        hijriMonthNameAr = hijri.month.ar
        hijriDateStr     = hijri.date
        gregorianDateStr = json.data.date.readable
        lastFetchDate    = new Date().toISOString().substring(0, 10)
        hasError = false

        updateCountdown()
        preloadAzan()
        startSyncedTimer()
        Logger.d("Mawaqit", "Loaded. Ramadan:", isRamadan, "hijriDay:", hijriDay)
      } else {
        hasError = true
        errorMessage = json.status || "API error"
        Logger.w("Mawaqit", "API error:", errorMessage)
      }
    } catch (e) {
      hasError = true
      errorMessage = "Parse error: " + e.message
      Logger.e("Mawaqit", "Parse error:", e.message)
    }
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  function updateCountdown() {
    if (!prayerTimings) { secondsToNext = -1; return }

    const now = new Date()
    const gracePeriodMs = 5 * 60 * 1000  // show "now" for 5 minutes after prayer starts

    function timeToday(timeStr) {
      if (!timeStr) return null
      const parts = timeStr.split(":")
      const d = new Date()
      d.setHours(parseInt(parts[0]), parseInt(parts[1]), 0, 0)
      return d
    }

    const prayers = []
    for (const key of prayerKeys) {
      const t = prayerTimings[key]
      if (!t) continue
      const d = timeToday(t)
      if (d) prayers.push({ name: key, time: d })
    }

    if (prayers.length === 0) { secondsToNext = -1; return }

    // Grace period — if a prayer just started within the last 5 min, show it as "now"
    for (let i = 0; i < prayers.length; i++) {
      const msSincePrayer = now - prayers[i].time
      if (msSincePrayer >= 0 && msSincePrayer < gracePeriodMs) {
        nextPrayerName = prayers[i].name
        secondsToNext = 0
        Logger.d("Mawaqit", "Grace period:", nextPrayerName, "now")
        return
      }
    }

    // Find next upcoming prayer
    let nextIdx = -1
    for (let i = 0; i < prayers.length; i++) {
      if (prayers[i].time > now) { nextIdx = i; break }
    }

    let next
    if (nextIdx === -1) {
      next = { name: prayers[0].name, time: new Date(prayers[0].time) }
      next.time.setDate(next.time.getDate() + 1)
    } else {
      next = prayers[nextIdx]
    }

    const diff = Math.floor((next.time - now) / 1000)
    nextPrayerName = next.name
    secondsToNext = diff > 0 ? diff : 0
    Logger.d("Mawaqit", "Next:", nextPrayerName, "in", diff, "s")
  }

  Component.onCompleted: {
    Qt.callLater(fetchPrayerTimes)
  }
}

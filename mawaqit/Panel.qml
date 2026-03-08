import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 360 * Style.uiScaleRatio
  readonly property real maxHeight: 580 * Style.uiScaleRatio
  property real contentPreferredHeight: Math.min(contentColumn.implicitHeight + Style.marginL * 2, maxHeight)
  readonly property bool allowAttach: true

  anchors.fill: parent

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  readonly property bool use12h: Settings.data.location.use12hourFormat

  // Shared state from Main.qml
  readonly property var    mainInstance:     pluginApi?.mainInstance
  readonly property var    prayerTimings:    mainInstance?.prayerTimings    ?? null
  readonly property bool   isRamadan:        mainInstance?.isRamadan        ?? false
  readonly property bool   isLoading:        mainInstance?.isLoading        ?? false
  readonly property bool   hasError:         mainInstance?.hasError         ?? false
  readonly property string errorMessage:     mainInstance?.errorMessage     ?? ""
  readonly property int    secondsToNext:   mainInstance?.secondsToNext   ?? -1
  readonly property string nextPrayerName:   mainInstance?.nextPrayerName   ?? ""
  readonly property int    hijriDay:         mainInstance?.hijriDay         ?? 0
  readonly property int    hijriMonth:       mainInstance?.hijriMonth       ?? 0
  readonly property int    hijriYear:        mainInstance?.hijriYear        ?? 0
  readonly property string hijriMonthNameAr: mainInstance?.hijriMonthNameAr ?? ""
  readonly property string hijriMonthNameEn: mainInstance?.hijriMonthNameEn ?? ""
  readonly property string gregorianDateStr: mainInstance?.gregorianDateStr ?? ""

  readonly property color countdownColor: {
    if (nextPrayerName === "Imsak" && isRamadan)  return Color.mSecondary
    if (nextPrayerName === "Maghrib" && isRamadan) return Color.mTertiary
    return Color.mPrimary
  }

  // DecoType font — always loaded
  FontLoader {
    id: decoFont
    source: pluginApi?.pluginDir ? (pluginApi.pluginDir + "/DecoType.ttf") : ""
  }
  readonly property bool decoFontReady: decoFont.status === FontLoader.Ready

  // Convert Western digits to Arabic-Indic numerals
  function toArabicNumerals(n) {
    return String(n).replace(/[0-9]/g, d => "٠١٢٣٤٥٦٧٨٩"[d])
  }

  // Full hijri date in Arabic: "١٥ شعبان ١٤٤٦"
  readonly property string hijriDateAr: {
    if (!hijriDay || !hijriMonthNameAr || !hijriYear) return ""
    return `${toArabicNumerals(hijriDay)} ${hijriMonthNameAr.trim()} ${toArabicNumerals(hijriYear)}`
  }

  // Fallback English date
  readonly property string hijriDateEn: {
    if (!hijriDay || !hijriMonthNameEn || !hijriYear) return ""
    return `${hijriDay} ${hijriMonthNameEn} ${hijriYear} AH`
  }

  Timer {
    interval: 1000
    running: secondsToNext > 0
    repeat: true
    onTriggered: mainInstance?.updateCountdown()
  }

  function formatTime(rawTime) {
    if (!rawTime) return "--:--"
    if (!use12h) return rawTime
    const parts = rawTime.split(":")
    let h = parseInt(parts[0])
    const m = parts[1]
    const ampm = h >= 12 ? "PM" : "AM"
    h = h % 12 || 12
    return `${h}:${m} ${ampm}`
  }

  function formatCountdown(secs) {
    if (secs <= 0) return ""
    const h = Math.floor(secs / 3600)
    const m = Math.floor((secs % 3600) / 60)
    const s = secs % 60
    if (h > 0) return `${h}h ${m.toString().padStart(2,"0")}m ${s.toString().padStart(2,"0")}s`
    if (m > 0) return `${m}m ${s.toString().padStart(2,"0")}s`
    return `${s}s`
  }

  readonly property var prayerOrder: [
    { key: "Imsak",   labelKey: "panel.imsak",   icon: "moon"       },
    { key: "Fajr",    labelKey: "panel.fajr",    icon: "sunrise"    },
    { key: "Sunrise", labelKey: "panel.sunrise", icon: "sun"        },
    { key: "Dhuhr",   labelKey: "panel.dhuhr",   icon: "sun-high"   },
    { key: "Asr",     labelKey: "panel.asr",     icon: "sun-low"    },
    { key: "Maghrib", labelKey: "panel.maghrib", icon: "sunset"     },
    { key: "Isha",    labelKey: "panel.isha",    icon: "moon-stars" }
  ]

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      id: contentColumn
      anchors {
        fill: parent
        margins: Style.marginL
      }
      spacing: Style.marginM

      // ── Row 1: icon + title + buttons ─────────────────────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NIcon {
          icon: "building-mosque"
          pointSize: Style.fontSizeXL
          color: Color.mPrimary
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          text: pluginApi?.tr("panel.title") || "Prayer Times"
          pointSize: Style.fontSizeL
          font.weight: Font.Bold
          color: Color.mOnSurface
          Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        NIconButton {
          icon: "refresh"
          tooltipText: pluginApi?.tr("panel.refresh") || "Refresh"
          enabled: !isLoading
          onClicked: mainInstance?.fetchPrayerTimes()
          Layout.alignment: Qt.AlignVCenter
        }

        NIconButton {
          icon: "settings"
          tooltipText: pluginApi?.tr("menu.settings") || "Settings"
          onClicked: {
            const screen = pluginApi?.panelOpenScreen
            if (screen) {
              pluginApi.closePanel(screen)
              Qt.callLater(() => BarService.openPluginSettings(screen, pluginApi.manifest))
            }
          }
          Layout.alignment: Qt.AlignVCenter
        }

        NIconButton {
          icon: "x"
          tooltipText: pluginApi?.tr("panel.close") || "Close"
          onClicked: {
            const screen = pluginApi?.panelOpenScreen
            if (screen) pluginApi.closePanel(screen)
          }
          Layout.alignment: Qt.AlignVCenter
        }
      }

      // ── Row 2: Gregorian date left — Hijri date right ──────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: gregorianDateStr !== ""

        NText {
          text: gregorianDateStr
          pointSize: Style.fontSizeS
          color: Color.mSecondary
          Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        // DecoType Arabic hijri date — always shown when font ready
        Text {
          visible: decoFontReady && hijriDateAr !== ""
          text: hijriDateAr
          font.family: decoFont.name
          font.pointSize: Style.fontSizeXL
          color: isRamadan ? Color.mPrimary : Color.mSecondary
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignRight
        }

        // Fallback if font not loaded yet
        NText {
          visible: !decoFontReady && hijriDateEn !== ""
          text: hijriDateEn
          pointSize: Style.fontSizeS
          color: isRamadan ? Color.mPrimary : Color.mSecondary
          Layout.alignment: Qt.AlignVCenter
        }
      }

      NDivider {
        Layout.fillWidth: true
        visible: prayerTimings === null
      }

      // ── Countdown box ──────────────────────────────────────────────────
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: countdownColumn.implicitHeight + Style.marginM * 2
        color: Qt.alpha(countdownColor, 0.12)
        radius: Style.radiusL
        visible: prayerTimings !== null && nextPrayerName !== "" && secondsToNext > 0

        ColumnLayout {
          id: countdownColumn
          anchors.centerIn: parent
          spacing: Style.marginXS

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: {
              if (!nextPrayerName) return ""
              return `${nextPrayerName} in`
            }
            pointSize: Style.fontSizeS
            color: countdownColor
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: formatCountdown(secondsToNext)
            pointSize: Style.fontSizeXXL
            font.weight: Font.Bold
            color: countdownColor
          }
        }
      }

      // ── Loading / error ────────────────────────────────────────────────
      Item {
        Layout.fillWidth: true
        implicitHeight: Style.baseWidgetSize
        visible: isLoading || hasError

        NBusyIndicator {
          anchors.centerIn: parent
          visible: isLoading
          running: isLoading
        }

        NText {
          anchors.centerIn: parent
          visible: hasError && !isLoading
          text: errorMessage || (pluginApi?.tr("error.generic") || "Failed to load prayer times.")
          color: Color.mError
          pointSize: Style.fontSizeS
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
        }
      }

      // ── Prayer list ────────────────────────────────────────────────────
      NScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(prayerListColumn.implicitHeight, root.maxHeight * 0.6)
        horizontalPolicy: ScrollBar.AlwaysOff
        reserveScrollbarSpace: false
        visible: prayerTimings !== null

        ColumnLayout {
          id: prayerListColumn
          width: parent.width
          spacing: Style.marginS

          Repeater {
            model: root.prayerOrder

            delegate: Rectangle {
              required property var modelData

              readonly property string rawTime:          prayerTimings?.[modelData.key] || ""
              readonly property bool   isNext:           modelData.key === nextPrayerName
              readonly property bool   isImsak:          isRamadan && modelData.key === "Imsak"
              readonly property bool   isMaghribRamadan: isRamadan && modelData.key === "Maghrib"

              readonly property color rowColor: {
                if (isNext)           return Qt.alpha(countdownColor, 0.15)
                if (isImsak)          return Qt.alpha(Color.mSecondary, 0.08)
                if (isMaghribRamadan) return Qt.alpha(Color.mTertiary, 0.08)
                return Color.mSurfaceVariant
              }

              readonly property color itemColor: {
                if (isNext)           return countdownColor
                if (isImsak)          return Color.mSecondary
                if (isMaghribRamadan) return Color.mTertiary
                return Color.mOnSurface
              }

              readonly property bool isBold: isNext || isImsak || isMaghribRamadan

              Layout.fillWidth: true
              implicitWidth: parent.width
              implicitHeight: rowLayout.implicitHeight + Style.marginS * 2
              radius: Style.radiusM
              color: rowColor

              Behavior on color { ColorAnimation { duration: 300 } }

              RowLayout {
                id: rowLayout
                anchors {
                  fill: parent
                  leftMargin: Style.marginM
                  rightMargin: Style.marginM
                  topMargin: Style.marginS
                  bottomMargin: Style.marginS
                }
                spacing: Style.marginM

                NIcon {
                  icon: modelData.icon
                  pointSize: Style.fontSizeM
                  color: itemColor
                  Layout.alignment: Qt.AlignVCenter
                }

                NText {
                  // Maghrib stays "Maghrib" in list always
                  text: pluginApi?.tr(modelData.labelKey) || modelData.key
                  pointSize: Style.fontSizeM
                  font.weight: isBold ? Style.fontWeightSemiBold : Style.fontWeightRegular
                  color: itemColor
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                }

                NText {
                  text: rawTime ? formatTime(rawTime) : "—"
                  pointSize: Style.fontSizeM
                  font.weight: isBold ? Style.fontWeightBold : Style.fontWeightRegular
                  color: itemColor
                  Layout.alignment: Qt.AlignVCenter
                }
              }
            }
          }
        }
      }

      // ── Empty state ────────────────────────────────────────────────────
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: prayerTimings === null && !isLoading && !hasError

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginM

          NIcon {
            icon: "building-mosque"
            pointSize: Style.fontSizeXXXL
            color: Color.mSecondary
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: pluginApi?.tr("panel.configure") || "Configure your city in settings"
            color: Color.mSecondary
            pointSize: Style.fontSizeM
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }
    }
  }
}

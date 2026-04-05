import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root
  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  property real contentPreferredWidth: 320 * Style.uiScaleRatio
  property real contentPreferredHeight: 400 * Style.uiScaleRatio

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property int activeCount: mainInstance?.activeCount ?? 0

  // Rebuild the ListModel whenever mainInstance.sortedHosts changes
  ListModel { id: hostModel }

  Connections {
    target: root.mainInstance
    function onSortedHostsChanged() { root.rebuildModel() }
  }

  onMainInstanceChanged: rebuildModel()

  function rebuildModel() {
    var hosts = root.mainInstance?.sortedHosts ?? []

    // Update existing rows, add new ones
    for (var i = 0; i < hosts.length; i++) {
      var h = hosts[i]
      var entry = {
        hostName: h.host.name,
        hostname: h.host.hostname ?? "",
        user: h.host.user ?? "",
        port: h.host.port ?? "",
        isActive: h.isActive
      }
      if (i < hostModel.count) {
        hostModel.set(i, entry)
      } else {
        hostModel.append(entry)
      }
    }

    // Remove extra rows
    while (hostModel.count > hosts.length) {
      hostModel.remove(hostModel.count - 1)
    }
  }

  anchors.fill: parent

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors {
        fill: parent
        margins: Style.marginXL
      }
      spacing: Style.marginL

      // ======== Header ========
      NText {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Style.marginM
        text: {
          if (root.activeCount === 0) return pluginApi?.tr("panel.noActive")
          if (root.activeCount === 1) return pluginApi?.tr("bar.oneSession")
          return root.activeCount + " " + pluginApi?.tr("bar.multipleSessions")
        }
        pointSize: Style.fontSizeL
        font.weight: Font.DemiBold
        color: root.activeCount > 0 ? Color.mPrimary : Color.mOnSurfaceVariant
      }

      // ======== Scrollable host list ========
      NScrollView {
        id: hostScrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth

        ColumnLayout {
          id: hostColumn
          width: hostScrollView.availableWidth
          spacing: Style.marginS

          Repeater {
            model: hostModel

            delegate: NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: hostRow.implicitHeight + Style.marginM * 2

              RowLayout {
                id: hostRow
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                // Status dot
                Rectangle {
                  width: 8 * Style.uiScaleRatio
                  height: width
                  radius: width / 2
                  color: model.isActive ? Color.mPrimary : "transparent"
                  border.width: model.isActive ? 0 : 1.5 * Style.uiScaleRatio
                  border.color: Color.mOnSurfaceVariant
                  opacity: model.isActive ? 1.0 : 0.5
                  Layout.alignment: Qt.AlignVCenter
                }

                // Host info
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

                  NText {
                    text: model.hostName
                    pointSize: Style.fontSizeM
                    font.weight: model.isActive ? Font.DemiBold : Font.Normal
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                  }

                  NText {
                    text: (model.user ? model.user + "@" : "") + (model.hostname || model.hostName)
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                  }
                }

                // Connect button
                NIcon {
                  icon: "terminal"
                  pointSize: Style.fontSizeM
                  color: connectArea.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignVCenter

                  MouseArea {
                    id: connectArea
                    anchors.fill: parent
                    anchors.margins: -Style.marginS
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.mainInstance?.connectToHost(model.hostName)
                  }
                }
              }
            }
          }

          // No hosts message
          NText {
            visible: (root.mainInstance?.hostList ?? []).length === 0 && root.mainInstance?.configLoaded
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Style.marginXL
            Layout.bottomMargin: Style.marginXL
            text: pluginApi?.tr("panel.noHosts")
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
          }
        }
      }

      // ======== Footer ========
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NButton {
          Layout.fillWidth: true
          text: pluginApi?.tr("panel.refresh")
          onClicked: root.mainInstance?.fullRefresh()
        }

        NIconButton {
          icon: "settings"
          onClicked: {
            if (!pluginApi) return
            BarService.openPluginSettings(pluginApi.panelOpenScreen, pluginApi.manifest)
            pluginApi.closePanel(pluginApi.panelOpenScreen)
          }
        }
      }
    }
  }
}

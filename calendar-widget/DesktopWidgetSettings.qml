import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: root
    implicitWidth: 400
    implicitHeight: 200

    property var pluginApi: null

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        NText {
            text: pluginApi?.tr("menu.title")
            font.bold: true
            font.pointSize: Style.fontSizeM
            color: Color.mPrimary
        }

        RowLayout {
            Layout.fillWidth: true
            
            NText { 
                text: pluginApi?.tr("menu.settings")
                Layout.fillWidth: true
                color: Color.mOnSurface
            }
            
            // Using a Button as a Toggle (Uncrashable alternative to NToggle)
            NButton {
                property bool isMonday: pluginApi?.pluginSettings?.startOnMonday ?? true
                text: isMonday ? "Monday" : "Sunday"
                
                onClicked: {
                    isMonday = !isMonday;
                    if (pluginApi && pluginApi.pluginSettings) {
                        pluginApi.pluginSettings.startOnMonday = isMonday;
                        Logger.i("CalendarPlugin", "Manual Switch to: " + (isMonday ? "Mon" : "Sun"));
                    }
                }
            }
        }
        
        Item { Layout.fillHeight: true }
    }

    function saveSettings() {
        if (pluginApi) {
            pluginApi.saveSettings();
        }
    }
}

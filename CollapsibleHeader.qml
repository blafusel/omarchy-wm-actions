import QtQuick
import qs.Ui
import qs.Commons

// PanelSectionHeader with a chevron. A plain click emits toggled(); a press
// that moves more than a few pixels is a drag instead: dragMoved(y) streams
// the pointer's y in this header's own coordinates, dragFinished() fires on
// release. The caller owns collapsed state and ordering (both persisted in
// Panel.qml).
Item {
  id: root

  property string text: ""
  property bool collapsed: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal toggled()
  signal dragMoved(real y)
  signal dragFinished()

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight
  height: implicitHeight

  Row {
    id: row
    spacing: Style.space(6)

    PanelSectionHeader {
      text: root.collapsed ? "▸" : "▾"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    PanelSectionHeader {
      text: root.text
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    cursorShape: moved ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    // Stops the surrounding ScrollView from stealing the drag as a flick.
    preventStealing: true

    property bool moved: false
    property real pressY: 0

    onPressed: function(mouse) {
      moved = false
      pressY = mouse.y
    }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      if (!moved && Math.abs(mouse.y - pressY) > 6) moved = true
      if (moved) root.dragMoved(mouse.y)
    }
    onReleased: {
      if (moved) root.dragFinished()
      else root.toggled()
      moved = false
    }
  }
}

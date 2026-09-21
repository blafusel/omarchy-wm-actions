import QtQuick
import qs.Ui
import qs.Commons

// Button + an independent star badge in the corner. The star has its own
// hit area (bigger than the glyph, stacked above the Button's own
// full-size MouseArea via z) so toggling a favorite never also fires the
// button's action.
Item {
  id: root

  property string iconText: ""
  property string text: ""
  property string tooltipText: ""
  property bool active: false
  property bool iconSpinning: false
  property bool leftAlign: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool isFavorite: false

  // Press-and-hold repeat, for actions like Backspace where holding down a
  // real key auto-repeats. Off by default (every other button keeps plain
  // Button click behavior untouched). When on, repeatInterval must stay
  // comfortably longer than the caller's own dispatch cycle (e.g. sendKey's
  // ~110ms explicit-refocus + down/up settle chain) -- firing clicked()
  // faster than that just keeps restarting the caller's own timers before
  // they ever get to dispatch anything, so backspace would silently never
  // fire. 150ms default clears that with margin.
  property bool repeatOnHold: false
  property int repeatInitialDelay: 450
  property int repeatInterval: 150

  signal clicked()
  signal favoriteToggled()

  implicitWidth: btn.implicitWidth
  implicitHeight: btn.implicitHeight

  Button {
    id: btn
    anchors.fill: parent
    iconText: root.iconText
    text: root.text
    tooltipText: root.tooltipText
    active: root.active || repeatArea.pressed
    iconSpinning: root.iconSpinning
    leftAlign: root.leftAlign
    fontSize: Style.font.bodySmall
    iconSize: Style.font.title
    foreground: root.foreground
    fontFamily: root.fontFamily
    bordered: true
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
    onClicked: if (!root.repeatOnHold) root.clicked()
  }

  // Sits above btn's own MouseArea (so it owns every click) but below the
  // star (z: 10), and is a complete no-op -- disabled, so events pass
  // through to btn underneath -- unless repeatOnHold is on.
  MouseArea {
    id: repeatArea
    anchors.fill: btn
    z: 5
    enabled: root.repeatOnHold
    cursorShape: Qt.PointingHandCursor
    onPressed: {
      root.clicked()
      repeatStartTimer.restart()
    }
    onReleased: {
      repeatStartTimer.stop()
      repeatIntervalTimer.stop()
    }
    onCanceled: {
      repeatStartTimer.stop()
      repeatIntervalTimer.stop()
    }
  }

  Timer {
    id: repeatStartTimer
    interval: root.repeatInitialDelay
    repeat: false
    onTriggered: repeatIntervalTimer.restart()
  }

  Timer {
    id: repeatIntervalTimer
    interval: root.repeatInterval
    repeat: true
    onTriggered: root.clicked()
  }

  Text {
    id: star
    textFormat: Text.PlainText
    text: root.isFavorite ? "★" : "☆"
    color: root.isFavorite ? "#f5c518" : root.foreground
    opacity: root.isFavorite ? 1.0 : 0.5
    font.pixelSize: Style.font.caption
    font.family: root.fontFamily
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(3)
    z: 10

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      cursorShape: Qt.PointingHandCursor
      onClicked: root.favoriteToggled()
    }
  }
}

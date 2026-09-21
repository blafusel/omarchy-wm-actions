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
  // Button click behavior untouched). The first press always emits
  // clicked() -- same as a normal click, full-weight dispatch. Every
  // auto-repeat tick after that emits the separate repeated() signal
  // instead, so the caller can use a cheaper/faster path for it: repeated
  // presses don't need e.g. sendKey's explicit refocus + settle delay,
  // since focus is already correct by the time you're holding a button
  // down. That's what lets repeatInterval go fast (75ms) without the
  // starvation problem a single shared dispatch path would hit -- see
  // Panel.qml's sendKeyFast().
  property bool repeatOnHold: false
  property int repeatInitialDelay: 450
  property int repeatInterval: 75

  signal clicked()
  signal repeated()
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
    onTriggered: root.repeated()
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

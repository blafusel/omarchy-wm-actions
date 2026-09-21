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
    active: root.active
    iconSpinning: root.iconSpinning
    leftAlign: root.leftAlign
    fontSize: Style.font.bodySmall
    iconSize: Style.font.title
    foreground: root.foreground
    fontFamily: root.fontFamily
    bordered: true
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
    onClicked: root.clicked()
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

import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

// Button's own built-in tooltip never wraps (single unbounded line), which
// overflows past the card's edge for any long tooltipText -- worse the
// narrower the card gets (single-column mode). This wraps at a fixed max
// width instead. Usage: place as a sibling of the hovered item and bind
// hoverSource to its hover/cursor state (e.g. someButton.hot).
ToolTip {
  id: root

  property bool hoverSource: false
  property string fontFamily: Style.font.family

  visible: text !== "" && hoverSource
  delay: 400
  padding: 0

  background: BorderSurface {
    color: Color.tooltip.background
    borderSpec: Border.localOrSurfaceSpec("tooltip", "border", Color.tooltip.border, Color.tooltip.border, Style.normalBorderWidth)
    radius: Style.cornerRadius
  }

  contentItem: Text {
    textFormat: Text.PlainText
    text: root.text
    wrapMode: Text.WordWrap
    width: Math.min(implicitWidth, Style.space(200))
    color: Color.tooltip.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    leftPadding: Style.spacing.controlPaddingX
    rightPadding: Style.spacing.controlPaddingX
    topPadding: Style.spacing.controlPaddingY
    bottomPadding: Style.spacing.controlPaddingY
  }
}

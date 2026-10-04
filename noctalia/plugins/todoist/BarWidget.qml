import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Custom capsule (vs. BarPill) because we need per-bucket colored count
// chips next to the icon — BarPill renders a single-colored text run.
// Matches BarPill's chrome (capsule color/border/radius/hover) so it sits
// natively on the bar.
Item {
  id: root
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property int overdueCount: mainInstance?.overdueCount ?? 0
  readonly property int todayCount: mainInstance?.todayCount ?? 0
  readonly property int upcomingCount: mainInstance?.upcomingCount ?? 0
  readonly property int totalCount: mainInstance?.totalCount ?? 0
  readonly property color colorOverdue: mainInstance?.colorOverdue ?? "#de4c4a"
  readonly property color colorToday: mainInstance?.colorToday ?? "#f49c18"
  readonly property color colorUpcoming: mainInstance?.colorUpcoming ?? "#4073d6"
  readonly property color urgencyColor: mainInstance?.urgencyColor ?? Color.mOnSurface
  readonly property bool showIcon: mainInstance?.pillShowIcon ?? true
  readonly property bool showDots: mainInstance?.pillShowDots ?? true

  readonly property int pillHeight: Style.getCapsuleHeightForScreen(screen?.name)
  readonly property real iconSize: Style.toOdd(pillHeight * 0.48)
  readonly property real fontPx: Style.getBarFontSizeForScreen(screen?.name)
  readonly property int hPad: Math.round(pillHeight * 0.45)
  readonly property int chipGap: Math.round(pillHeight * 0.18)

  property bool hovered: false

  implicitWidth: capsule.implicitWidth
  implicitHeight: pillHeight

  function buildTooltip() {
    if (!mainInstance) return pluginApi?.tr("tooltip.header");
    if (mainInstance.lastError && mainInstance.lastError.length > 0) {
      return pluginApi?.tr("tooltip.error") + " — " + mainInstance.lastError;
    }
    if (totalCount === 0) return pluginApi?.tr("tooltip.clear");
    const parts = [];
    if (overdueCount > 0) parts.push(pluginApi?.tr("tooltip.line-overdue", { n: overdueCount }));
    if (todayCount > 0)   parts.push(pluginApi?.tr("tooltip.line-today",   { n: todayCount }));
    if (upcomingCount > 0)parts.push(pluginApi?.tr("tooltip.line-upcoming",{ n: upcomingCount }));
    return pluginApi?.tr("tooltip.header") + " · " + parts.join(" · ");
  }

  Rectangle {
    id: capsule
    anchors.verticalCenter: parent.verticalCenter
    height: pillHeight
    radius: Style.radiusM
    color: root.hovered ? Color.mHover : Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth
    implicitWidth: contentRow.implicitWidth + hPad * 2

    Behavior on color {
      enabled: !Color.isTransitioning
      ColorAnimation { duration: Style.animationFast; easing.type: Easing.InOutQuad }
    }

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: chipGap

      NIcon {
        visible: root.showIcon
        icon: "checklist"
        pointSize: iconSize
        applyUiScale: false
        color: root.hovered ? Color.mOnHover : root.urgencyColor
      }

      // Per-bucket count chips, only rendered when non-zero so the widget
      // stays calm on quiet days and lights up when something slips.
      Repeater {
        model: [
          { n: root.overdueCount,  c: root.colorOverdue  },
          { n: root.todayCount,    c: root.colorToday    },
          { n: root.upcomingCount, c: root.colorUpcoming }
        ]
        delegate: RowLayout {
          visible: root.showDots && modelData.n > 0
          spacing: Math.round(chipGap * 0.5)

          Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width:  Math.max(4, Math.round(iconSize * 0.45))
            height: width
            radius: width / 2
            color: root.hovered ? Color.mOnHover : modelData.c
          }

          NText {
            Layout.alignment: Qt.AlignVCenter
            text: modelData.n
            family: Settings.data.ui.fontFixed
            pointSize: root.fontPx
            applyUiScale: false
            color: root.hovered ? Color.mOnHover : Color.mOnSurface
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      root.hovered = true;
      TooltipService.show(root, root.buildTooltip(),
                          BarService.getTooltipDirection(root.screen?.name),
                          Style.tooltipDelayLong);
    }
    onExited: {
      root.hovered = false;
      TooltipService.hide();
    }
    onClicked: mouse => {
      TooltipService.hide();
      if (mouse.button === Qt.LeftButton) {
        if (pluginApi) pluginApi.openPanel(root.screen, root);
      } else if (mouse.button === Qt.RightButton) {
        if (mainInstance) mainInstance.openInBrowser("");
      } else if (mouse.button === Qt.MiddleButton) {
        if (mainInstance) mainInstance.refresh();
      }
    }
  }
}

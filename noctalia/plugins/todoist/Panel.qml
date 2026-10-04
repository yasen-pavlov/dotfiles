import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root
  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true
  property real contentPreferredWidth: 440 * Style.uiScaleRatio
  property real contentPreferredHeight: contentCol.implicitHeight + Style.marginM * 2

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property int maxPerSection: mainInstance?.maxPerSection ?? 10

  // P1 (priority=4 in API) → red, descending to P4 (priority=1) → muted.
  function priorityColor(p) {
    if (p === 4) return mainInstance?.colorOverdue ?? "#de4c4a";
    if (p === 3) return mainInstance?.colorToday ?? "#f49c18";
    if (p === 2) return mainInstance?.colorUpcoming ?? "#4073d6";
    return Color.mOnSurfaceVariant;
  }

  function formatDueShort(task, bucket) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    if (!task.due_date) return "";

    const due = new Date(task.due_date + "T00:00:00");
    const diffDays = Math.round((due - today) / 86400000);

    if (bucket === "overdue") {
      const n = Math.abs(diffDays);
      return n === 1 ? "yesterday" : (n + "d ago");
    }
    if (bucket === "today") {
      if (task.due_datetime) {
        const t = new Date(task.due_datetime);
        return Qt.formatDateTime(t, "h:mmap").toLowerCase();
      }
      return "today";
    }
    // upcoming
    if (diffDays === 1) return "tomorrow";
    if (diffDays < 7) return Qt.formatDateTime(due, "ddd");
    return Qt.formatDateTime(due, "MMM d");
  }

  function formatSyncAgo() {
    if (!mainInstance || !mainInstance.lastSync) return pluginApi?.tr("panel.last-sync-never");
    const t = new Date(mainInstance.lastSync);
    if (isNaN(t.getTime())) return pluginApi?.tr("panel.last-sync-never");
    const ago = Math.max(1, Math.round((Date.now() - t.getTime()) / 1000));
    let s;
    if (ago < 60) s = ago + "s ago";
    else if (ago < 3600) s = Math.round(ago / 60) + "m ago";
    else s = Math.round(ago / 3600) + "h ago";
    return pluginApi?.tr("panel.last-sync", { time: s });
  }

  Item {
    id: panelContainer
    anchors.fill: parent

    ColumnLayout {
      id: contentCol
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      // ───────────── Header ─────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
          icon: "checklist"
          pointSize: Style.fontSizeXL
          color: mainInstance?.urgencyColor ?? Color.mOnSurface
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          NText {
            text: pluginApi?.tr("panel.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: {
              if (!mainInstance) return pluginApi?.tr("panel.loading");
              if (mainInstance.lastError && mainInstance.lastError.length > 0) {
                return pluginApi?.tr("panel.error-prefix") + mainInstance.lastError;
              }
              if (mainInstance.totalCount === 0) return pluginApi?.tr("panel.summary-clear");
              return pluginApi?.tr("panel.summary", {
                overdue: mainInstance.overdueCount,
                today: mainInstance.todayCount,
                upcoming: mainInstance.upcomingCount
              });
            }
            pointSize: Style.fontSizeS
            color: (mainInstance && mainInstance.lastError && mainInstance.lastError.length > 0)
                   ? (mainInstance?.colorOverdue ?? Color.mError)
                   : Color.mOnSurfaceVariant
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        NIconButton {
          icon: "refresh"
          tooltipText: pluginApi?.tr("panel.footer-refresh")
          onClicked: { if (mainInstance) mainInstance.refresh(); }
        }
        NIconButton {
          icon: "external-link"
          tooltipText: pluginApi?.tr("panel.footer-open")
          onClicked: { if (mainInstance) mainInstance.openInBrowser(""); }
        }
      }

      // Last-sync line (subtle, below header)
      NText {
        Layout.fillWidth: true
        Layout.topMargin: -Style.marginXS
        text: root.formatSyncAgo()
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        opacity: 0.7
        horizontalAlignment: Text.AlignRight
      }

      // ───────────── Sections ─────────────
      ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        spacing: Style.marginM

        Repeater {
          model: [
            { key: "overdue",  items: mainInstance?.overdue  ?? [], color: mainInstance?.colorOverdue,  show: mainInstance?.showOverdue  ?? true, emptyKey: "panel.empty-overdue",  titleKey: "panel.section-overdue"  },
            { key: "today",    items: mainInstance?.today    ?? [], color: mainInstance?.colorToday,    show: mainInstance?.showToday    ?? true, emptyKey: "panel.empty-today",    titleKey: "panel.section-today"    },
            { key: "upcoming", items: mainInstance?.upcoming ?? [], color: mainInstance?.colorUpcoming, show: mainInstance?.showUpcoming ?? true, emptyKey: "panel.empty-upcoming", titleKey: "panel.section-upcoming" }
          ]
          delegate: ColumnLayout {
            id: sectionCol
            Layout.fillWidth: true
            visible: modelData.show
            spacing: Style.marginXS

            // Capture the section data on the outer delegate so the inner
            // task Repeater can reference it without relying on QML's
            // visual parent chain (which `parent.parent` doesn't traverse
            // through Repeater, since Repeater isn't a visual parent).
            readonly property var sectionData: modelData
            readonly property string bucketKey: modelData.key
            readonly property color accentColor: modelData.color

            // Section header: colored accent + name + count
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 4
                height: Style.fontSizeM * 1.2
                radius: 2
                color: modelData.color
              }

              NText {
                text: pluginApi?.tr(modelData.titleKey)
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
              }

              NText {
                text: modelData.items.length > 0 ? ("· " + modelData.items.length) : ""
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
              }

              Item { Layout.fillWidth: true }
            }

            // Empty-state line
            NText {
              visible: modelData.items.length === 0
              Layout.fillWidth: true
              Layout.leftMargin: Style.marginS + 4
              text: pluginApi?.tr(modelData.emptyKey)
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              opacity: 0.7
              font.italic: true
            }

            // Task rows (clipped to maxPerSection)
            Repeater {
              model: modelData.items.slice(0, root.maxPerSection)
              delegate: Rectangle {
                id: rowItem
                Layout.fillWidth: true
                Layout.leftMargin: Style.marginS
                implicitHeight: rowLayout.implicitHeight + Style.marginXS * 2
                color: rowHover.hovered ? Color.mSurfaceVariant : "transparent"
                radius: Style.radiusS

                readonly property var task: modelData
                readonly property string bucket: sectionCol.bucketKey

                HoverHandler { id: rowHover }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (mainInstance) mainInstance.openInBrowser(rowItem.task.url);
                  }
                }

                RowLayout {
                  id: rowLayout
                  anchors.fill: parent
                  anchors.margins: Style.marginXS
                  anchors.leftMargin: Style.marginS
                  anchors.rightMargin: Style.marginXS
                  spacing: Style.marginS

                  // Priority pip
                  Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 6; height: 6; radius: 3
                    color: root.priorityColor(rowItem.task.priority)
                  }

                  // Content + (optional) project subtext
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    NText {
                      Layout.fillWidth: true
                      text: rowItem.task.content
                      pointSize: Style.fontSizeS
                      color: Color.mOnSurface
                      elide: Text.ElideRight
                    }

                    NText {
                      visible: (rowItem.task.project || "").length > 0
                      Layout.fillWidth: true
                      text: "# " + (rowItem.task.project || "")
                      pointSize: Style.fontSizeXS
                      color: Color.mOnSurfaceVariant
                      opacity: 0.65
                      elide: Text.ElideRight
                    }
                  }

                  // Due chip — replaced by action buttons on hover
                  NText {
                    visible: !rowHover.hovered
                    Layout.alignment: Qt.AlignVCenter
                    text: root.formatDueShort(rowItem.task, rowItem.bucket)
                    pointSize: Style.fontSizeXS
                    color: rowItem.bucket === "overdue"
                           ? (mainInstance?.colorOverdue ?? Color.mError)
                           : Color.mOnSurfaceVariant
                  }

                  // Hover actions
                  RowLayout {
                    visible: rowHover.hovered
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Style.marginXXS

                    NIconButton {
                      visible: rowItem.bucket !== "upcoming"
                      icon: "calendar-plus"
                      tooltipText: pluginApi?.tr("panel.row-push-tomorrow")
                      onClicked: { if (mainInstance) mainInstance.pushTomorrow(rowItem.task.id); }
                    }
                    NIconButton {
                      icon: "check"
                      tooltipText: pluginApi?.tr("panel.row-complete")
                      onClicked: { if (mainInstance) mainInstance.complete(rowItem.task.id); }
                    }
                  }
                }
              }
            }

            // Overflow indicator
            NText {
              visible: modelData.items.length > root.maxPerSection
              Layout.fillWidth: true
              Layout.leftMargin: Style.marginS + 4
              text: "+ " + (modelData.items.length - root.maxPerSection) + " more"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              opacity: 0.7
            }
          }
        }
      }
    }
  }
}

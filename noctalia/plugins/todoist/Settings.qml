import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  property var pluginApi: null
  readonly property var cfg: pluginApi?.pluginSettings ?? ({})

  property int pollSeconds: cfg.pollSeconds ?? 90
  property string filterText: cfg.filter ?? ""
  property int maxPerSection: cfg.maxPerSection ?? 10
  property bool showOverdue: cfg.showOverdue ?? true
  property bool showToday: cfg.showToday ?? true
  property bool showUpcoming: cfg.showUpcoming ?? true
  property bool pillShowIcon: cfg.pillShowIcon ?? true
  property bool pillShowDots: cfg.pillShowDots ?? true
  property string colorOverdue: cfg.colorOverdue ?? "#de4c4a"
  property string colorToday: cfg.colorToday ?? "#f49c18"
  property string colorUpcoming: cfg.colorUpcoming ?? "#4073d6"
  property string openUrl: cfg.openUrl ?? "https://todoist.com/app/today"

  spacing: Style.marginL

  NSpinBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.poll-seconds.label")
    description: pluginApi?.tr("settings.poll-seconds.desc")
    from: 15; to: 3600; stepSize: 15
    value: root.pollSeconds
    onValueChanged: root.pollSeconds = value
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.filter.label")
    description: pluginApi?.tr("settings.filter.desc")
    text: root.filterText
    onEditingFinished: root.filterText = text
  }

  NSpinBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.max-per-section.label")
    from: 1; to: 50; stepSize: 1
    value: root.maxPerSection
    onValueChanged: root.maxPerSection = value
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-overdue.label")
    checked: root.showOverdue
    onToggled: checked => root.showOverdue = checked
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-today.label")
    checked: root.showToday
    onToggled: checked => root.showToday = checked
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-upcoming.label")
    checked: root.showUpcoming
    onToggled: checked => root.showUpcoming = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.pill-show-icon.label")
    checked: root.pillShowIcon
    onToggled: checked => root.pillShowIcon = checked
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.pill-show-dots.label")
    description: pluginApi?.tr("settings.pill-show-dots.desc")
    checked: root.pillShowDots
    onToggled: checked => root.pillShowDots = checked
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.color-overdue.label")
    text: root.colorOverdue
    onEditingFinished: root.colorOverdue = text
  }
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.color-today.label")
    text: root.colorToday
    onEditingFinished: root.colorToday = text
  }
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.color-upcoming.label")
    text: root.colorUpcoming
    onEditingFinished: root.colorUpcoming = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.open-url.label")
    description: pluginApi?.tr("settings.open-url.desc")
    text: root.openUrl
    onEditingFinished: root.openUrl = text
  }

  function saveSettings() {
    if (!pluginApi) return;
    pluginApi.pluginSettings.pollSeconds = root.pollSeconds;
    pluginApi.pluginSettings.filter = root.filterText;
    pluginApi.pluginSettings.maxPerSection = root.maxPerSection;
    pluginApi.pluginSettings.showOverdue = root.showOverdue;
    pluginApi.pluginSettings.showToday = root.showToday;
    pluginApi.pluginSettings.showUpcoming = root.showUpcoming;
    pluginApi.pluginSettings.pillShowIcon = root.pillShowIcon;
    pluginApi.pluginSettings.pillShowDots = root.pillShowDots;
    pluginApi.pluginSettings.colorOverdue = root.colorOverdue;
    pluginApi.pluginSettings.colorToday = root.colorToday;
    pluginApi.pluginSettings.colorUpcoming = root.colorUpcoming;
    pluginApi.pluginSettings.openUrl = root.openUrl;
    pluginApi.saveSettings();
  }
}

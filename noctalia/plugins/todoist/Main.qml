import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root
  property var pluginApi: null

  // --- State mirrored from the fetch script -------------------------------
  property var overdue: []
  property var today: []
  property var upcoming: []
  property string lastSync: ""
  property string lastError: ""
  property bool loading: true
  property bool _everApplied: false

  // Optimistic-action suppression: tasks completed/pushed locally are hidden from
  // fetch results until the server reflects the change (the task drops out of the
  // fetch) or a grace timeout. Without this, a poll that races ahead of the
  // detached complete/reschedule re-fetches the still-active task and it pops back.
  property var _suppress: ({})   // id -> { until: epochMs, untilGone: bool }

  // --- Settings (defaults from manifest are merged in by PluginService) ----
  readonly property var cfg: pluginApi?.pluginSettings ?? ({})
  readonly property int pollSeconds: cfg.pollSeconds ?? 90
  readonly property string filterExpr: cfg.filter ?? ""
  readonly property int maxPerSection: cfg.maxPerSection ?? 10
  readonly property bool showOverdue: cfg.showOverdue ?? true
  readonly property bool showToday: cfg.showToday ?? true
  readonly property bool showUpcoming: cfg.showUpcoming ?? true
  readonly property bool pillShowDots: cfg.pillShowDots ?? true
  readonly property bool pillShowIcon: cfg.pillShowIcon ?? true
  readonly property color colorOverdue: cfg.colorOverdue || "#de4c4a"
  readonly property color colorToday: cfg.colorToday || "#f49c18"
  readonly property color colorUpcoming: cfg.colorUpcoming || "#4073d6"
  readonly property string openUrl: cfg.openUrl || "https://todoist.com/app/today"

  readonly property string scriptPath: (pluginApi?.pluginDir ?? "") + "/scripts/todoist-fetch.py"

  // --- Derived ------------------------------------------------------------
  readonly property int overdueCount: overdue.length
  readonly property int todayCount: today.length
  readonly property int upcomingCount: upcoming.length
  readonly property int totalCount: overdueCount + todayCount + upcomingCount
  readonly property bool allClear: totalCount === 0

  // Urgency tint for the bar pill icon.
  readonly property color urgencyColor: {
    if (overdueCount > 0) return colorOverdue;
    if (todayCount > 0) return colorToday;
    return Color.mOnSurface;
  }

  // --- Poll loop ----------------------------------------------------------
  Process {
    id: fetchProc
    running: false
    command: {
      const c = [root.scriptPath, "fetch"];
      if (root.filterExpr && root.filterExpr.length > 0) {
        c.push("--filter");
        c.push(root.filterExpr);
      }
      return c;
    }
    stdout: StdioCollector {
      onStreamFinished: root._applyFetch(this.text)
    }
  }

  Timer {
    id: poller
    interval: Math.max(15, root.pollSeconds) * 1000
    repeat: true
    running: pluginApi !== null
    triggeredOnStart: true
    onTriggered: root._poll()
  }

  function _poll() {
    if (!fetchProc.running) fetchProc.running = true;
  }

  function _applyFetch(text) {
    let payload = null;
    try {
      payload = JSON.parse((text || "").trim() || "{}");
    } catch (e) {
      Logger.w("todoist", "Failed to parse fetch payload:", e);
      root.lastError = String(e);
      root.loading = false;
      return;
    }
    const ov = payload.overdue || [];
    const td = payload.today || [];
    const up = payload.upcoming || [];

    // Hide suppressed (locally completed/pushed) tasks until their grace window
    // passes — purely TIME-BASED. We deliberately do NOT un-hide early just because
    // a fetch shows the task gone: Todoist is eventually consistent and a just-closed
    // task can briefly reappear in get_tasks on a later request, which would resurrect
    // it. A flat grace outlasts that flutter.
    const now = Date.now();
    const sup = root._suppress;
    const stale = [];
    for (const id in sup) { if (now > sup[id].until) stale.push(id); }
    if (stale.length) { for (const id of stale) delete sup[id]; root._suppress = sup; }
    const keep = (t) => sup[t.id] === undefined;

    root.overdue = ov.filter(keep);
    root.today = td.filter(keep);
    root.upcoming = up.filter(keep);
    root.lastSync = payload.last_sync || root.lastSync;
    root.lastError = payload.error || "";
    root.loading = false;
    root._everApplied = true;
  }

  // --- Actions ------------------------------------------------------------
  function refresh() { _poll(); }

  // A few follow-up polls after an action so the suppression set reconciles
  // quickly: completes clear once the server drops the task; pushes resurface in
  // "upcoming" once the grace window passes — without waiting for the 90s poll.
  Timer {
    id: reconcilePoll
    interval: 3000
    repeat: true
    property int left: 0
    onTriggered: { root._poll(); if (--left <= 0) running = false; }
  }
  function _scheduleReconcile() { reconcilePoll.left = 3; reconcilePoll.restart(); }

  function _suppressId(id, graceMs) {
    const s = root._suppress;
    s[id] = { until: Date.now() + graceMs };
    root._suppress = s;
  }

  function complete(id) {
    if (!id) return;
    _suppressId(id, 30000);         // gone for good — hide through the consistency window
    _removeFromAll(id);
    Quickshell.execDetached([root.scriptPath, "complete", id]);
    ToastService.showNotice(pluginApi?.tr("toast.completed-title"), "", "check");
    _scheduleReconcile();
  }

  function pushTomorrow(id) {
    if (!id) return;
    _suppressId(id, 8000);          // hide briefly, then let it surface in "upcoming"
    _removeFromAll(id);
    Quickshell.execDetached([root.scriptPath, "reschedule", id, "tomorrow"]);
    ToastService.showNotice(pluginApi?.tr("toast.rescheduled-title"), "", "clock-plus");
    _scheduleReconcile();
  }

  function openInBrowser(url) {
    const target = (url && url.length > 0) ? url : root.openUrl;
    Quickshell.execDetached(["xdg-open", target]);
  }

  function _removeFromAll(id) {
    root.overdue = root.overdue.filter(t => t.id !== id);
    root.today = root.today.filter(t => t.id !== id);
    root.upcoming = root.upcoming.filter(t => t.id !== id);
  }
}

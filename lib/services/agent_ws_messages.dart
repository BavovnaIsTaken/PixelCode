/// Pure builders for every outbound WebSocket message in `AgentWsService`.
///
/// Each builder returns the exact `Map<String, dynamic>` that the service
/// would JSON-encode and push to the socket. Extracted so the wire shape can
/// be unit-tested without spinning up a WebSocket — and so the service stays
/// a thin transport layer over these builders.
///
/// Conventions:
/// - Optional fields are **omitted** from the map when null/empty (matching
///   the `?value` spread the service used inline). This keeps the server's
///   message-shape contract tight.
/// - Numeric clamps (e.g. dungeon difficulty 1..3) live here, not in the
///   service, so tests cover them directly.
library;

import '../models/facilitator_style.dart';

// ─── Chat ────────────────────────────────────────────────────────────────────

Map<String, dynamic> buildSendMessage(
  String content, {
  String agentId = 'manager',
  List<String>? images,
  String? localId,
  String? projectPath,
}) {
  return {
    'type': 'send_message',
    'content': content,
    'agentId': agentId,
    if (images != null && images.isNotEmpty) 'images': images,
    'localId': ?localId,
    // Project the client believes is active — the server rejects the message
    // with `project_mismatch` when it is running in a different one.
    'projectPath': ?projectPath,
  };
}

Map<String, dynamic> buildNewChat() => {'type': 'new_chat'};

Map<String, dynamic> buildClearSessions() => {'type': 'clear_sessions'};

Map<String, dynamic> buildInterrupt() => {'type': 'interrupt'};

Map<String, dynamic> buildGetStatus() => {'type': 'get_status'};

// ─── Task board ──────────────────────────────────────────────────────────────

Map<String, dynamic> buildBoardGetState() => {'type': 'board_get_state'};

Map<String, dynamic> buildBoardCreateTask({
  required String title,
  String? description,
  String? color,
  String? priority,
  int? difficulty,
  List<String>? allowedRoles,
  String? taskType,
}) {
  return {
    'type': 'board_create_task',
    'title': title,
    'description': ?description,
    'color': ?color,
    'priority': ?priority,
    'difficulty': ?difficulty,
    'allowedRoles': ?allowedRoles,
    'taskType': ?taskType,
  };
}

Map<String, dynamic> buildBoardMoveTask({
  required String taskId,
  required String column,
}) {
  return {'type': 'board_move_task', 'taskId': taskId, 'column': column};
}

Map<String, dynamic> buildBoardUpdateTask({
  required String taskId,
  required Map<String, dynamic> updates,
}) {
  return {'type': 'board_update_task', 'taskId': taskId, 'updates': updates};
}

Map<String, dynamic> buildBoardDeleteTask({required String taskId}) {
  return {'type': 'board_delete_task', 'taskId': taskId};
}

Map<String, dynamic> buildBoardAssignAgent({
  required String taskId,
  required String agentId,
  required bool assign,
}) {
  return {
    'type': 'board_assign_agent',
    'taskId': taskId,
    'agentId': agentId,
    'assign': assign,
  };
}

Map<String, dynamic> buildBoardAddAttachment({
  required String taskId,
  required String name,
  required String mimeType,
  required int sizeBytes,
  required String dataBase64,
}) {
  return {
    'type': 'board_add_attachment',
    'taskId': taskId,
    'name': name,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'dataBase64': dataBase64,
  };
}

Map<String, dynamic> buildBoardRemoveAttachment({
  required String taskId,
  required String attachmentId,
}) {
  return {
    'type': 'board_remove_attachment',
    'taskId': taskId,
    'attachmentId': attachmentId,
  };
}

// ─── Project management ──────────────────────────────────────────────────────

Map<String, dynamic> buildSetProject(String path) =>
    {'type': 'set_project', 'path': path};

Map<String, dynamic> buildSetProjectContext(String memories) =>
    {'type': 'set_project_context', 'memories': memories};

Map<String, dynamic> buildGenerateSummary() => {'type': 'generate_summary'};

// ─── Game economy ────────────────────────────────────────────────────────────

Map<String, dynamic> buildSetGameState({
  required Map<String, Map<String, dynamic>> instances,
  String? fullState,
  int? stateUpdatedAt,
  String? deepseekApiKey,
  String? kimiApiKey,
}) {
  return {
    'type': 'set_game_state',
    'instances': instances,
    'fullState': fullState,
    'stateUpdatedAt': stateUpdatedAt,
    'deepseekApiKey': deepseekApiKey,
    'kimiApiKey': kimiApiKey,
  };
}

// ─── Session presence ────────────────────────────────────────────────────────

Map<String, dynamic> buildClaimSession() => {'type': 'session_claim'};
Map<String, dynamic> buildReleaseSession() => {'type': 'session_release'};

// ─── Agent traits & lessons ──────────────────────────────────────────────────

Map<String, dynamic> buildGetTraits() => {'type': 'get_traits'};

Map<String, dynamic> buildRecordLesson({
  required String agentId,
  required String lessonType,
  required String category,
  required String tag,
  required String lesson,
}) {
  return {
    'type': 'record_lesson',
    'agentId': agentId,
    'lessonType': lessonType,
    'category': category,
    'tag': tag,
    'lesson': lesson,
  };
}

Map<String, dynamic> buildRemoveLesson(String lessonId) =>
    {'type': 'remove_lesson', 'lessonId': lessonId};

// ─── Dungeon training ────────────────────────────────────────────────────────

Map<String, dynamic> buildStartDungeon({
  required String agentId,
  required int skillType,
  required int difficulty,
}) {
  return {
    'type': 'start_dungeon',
    'agentId': agentId,
    'skillType': skillType,
    'difficulty': difficulty.clamp(1, 3),
  };
}

// ─── Facilitator system ──────────────────────────────────────────────────────

Map<String, dynamic> buildFacilitatorStart({
  required FacilitatorStyle style,
  required String projectDescription,
  required Map<String, String> answers,
}) {
  return {
    'type': 'facilitator_start',
    'style': style.toJson(),
    'projectDescription': projectDescription,
    'answers': answers,
  };
}

Map<String, dynamic> buildGetFacilitatorOutput() =>
    {'type': 'get_facilitator_output'};

Map<String, dynamic> buildPushFacilitatorOutput({
  required String outputFormat,
  required String outputJson,
}) {
  return {
    'type': 'push_facilitator_output',
    'outputFormat': outputFormat,
    'outputJson': outputJson,
  };
}

// ─── Character position sync ─────────────────────────────────────────────────

Map<String, dynamic> buildSyncPositions(
  Map<String, Map<String, dynamic>> positions,
) {
  return {'type': 'sync_positions', 'positions': positions};
}

// ─── Live input sync ─────────────────────────────────────────────────────────

Map<String, dynamic> buildInputText(String text) =>
    {'type': 'input_text', 'text': text};

Map<String, dynamic> buildInputImages(List<String> images) =>
    {'type': 'input_images', 'images': images};

// ─── iOS deploy ──────────────────────────────────────────────────────────────

Map<String, dynamic> buildIosDeployCheck() => {'type': 'ios_deploy_check'};
Map<String, dynamic> buildIosDeployStart() => {'type': 'ios_deploy_start'};
Map<String, dynamic> buildIosDeployCancel() => {'type': 'ios_deploy_cancel'};

// ─── Android deploy ──────────────────────────────────────────────────────────

Map<String, dynamic> buildAndroidDeployCheck() =>
    {'type': 'android_deploy_check'};

Map<String, dynamic> buildAndroidDeployListDevices() =>
    {'type': 'android_deploy_list_devices'};

Map<String, dynamic> buildAndroidDeployStart({String? deviceSerial}) {
  return {
    'type': 'android_deploy_start',
    'deviceSerial': ?deviceSerial,
  };
}

Map<String, dynamic> buildAndroidDeployCancel() =>
    {'type': 'android_deploy_cancel'};

// ─── Device screenshot ───────────────────────────────────────────────────────

Map<String, dynamic> buildCaptureScreenshot({
  required String platform,
  String? deviceSerial,
}) {
  return {
    'type': 'screenshot_capture',
    'platform': platform,
    'deviceSerial': ?deviceSerial,
  };
}

// ─── Tailscale setup ─────────────────────────────────────────────────────────

Map<String, dynamic> buildTailscaleConnect() => {'type': 'tailscale_connect'};

// ─── Network diagnostics ─────────────────────────────────────────────────────

Map<String, dynamic> buildHealthCheckRequest() =>
    {'type': 'health_check_request'};

Map<String, dynamic> buildHealthFixRequest(String itemId) =>
    {'type': 'health_fix_request', 'id': itemId};

// ─── Permissions bypass ──────────────────────────────────────────────────────

Map<String, dynamic> buildSetBypassPermissions(bool enabled) =>
    {'type': 'set_bypass_permissions', 'enabled': enabled};

// ─── Client identification ───────────────────────────────────────────────────

Map<String, dynamic> buildClientInfo({
  required String clientId,
  required String deviceName,
  required String platform,
}) {
  return {
    'type': 'client_info',
    'clientId': clientId,
    'deviceName': deviceName,
    'platform': platform,
  };
}

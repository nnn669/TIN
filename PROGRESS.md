TASK: 移除世界书（World Book）功能
STEP: 清理完成，版本 1.1.32+9026，等待合并到 main 后发布
BRANCH: remove-world-book
DONE: 合并 repair/world-book-local-sync（app_control_service.dart / chat_input_bar.dart 已清理）
DONE: 删除 7 个 world_book 专属文件
  lib/core/models/world_book.dart
  lib/core/services/world_book_store.dart
  lib/core/providers/world_book_provider.dart
  lib/features/world_book/pages/world_book_page.dart
  lib/features/home/widgets/world_book_sheet.dart
  lib/desktop/world_book_popover.dart
  lib/desktop/setting/world_book_pane.dart
DONE: lib/desktop/desktop_settings_page.dart 移除菜单项、枚举与 import
DONE: lib/features/settings/pages/settings_page.dart 移除入口与 import
DONE: lib/features/chat/widgets/bottom_tools_sheet.dart 移除 provider/入口
DONE: lib/features/home/pages/home_page.dart 移除 import、初始化、_openWorldBookPopover
DONE: lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart 移除网关能力项
DONE: test/core/services/app_control_service_test.dart 移除世界书测试与 temperature 断言
DONE: McpLifecycleReconnect 在缺少 McpProvider 的轻量 overlay/test 场景下安全跳过重连
SELF_CHECK: CI run 30916909711 已通过 flutter analyze + flutter test（866 tests passed）
SELF_CHECK: 已核对 world_book/WorldBook/worldBook 仅剩 l10n 死资源，生产代码引用已清理
SELF_CHECK: pubspec.yaml 版本已递增至 1.1.32+9026
NEXT: 创建 Release v1.1.32
PENDING: 等待 Android Test Release 构建并上传 APK

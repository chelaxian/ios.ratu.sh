# Shadow rootless — 2026-10-18

Проверяемый пакет: `me.jjolano.shadow`, версия `4.0.0-1`, архитектура `iphoneos-arm64`.

Основа: [jjolano/shadow, 2aee34c](https://github.com/jjolano/shadow/commit/2aee34c7a6553e599a0cb75b2fa58e3b81abc972).
Изменение: [chelaxian/shadow, 2207575](https://github.com/chelaxian/shadow/commit/220757587e0e1dd40ffb278e05e53342994b6d8b).
Исправлено падение при загрузке библиотек на iOS 17: служебные поля Atlas в состоянии dyld сохраняются.

Полный публичный набор проверок и проверка ошибки Atlas: [CI 39143603776](https://github.com/chelaxian/shadow/actions/runs/39143603776).
Сборка rootless на macOS/Xcode: [CI 39143603782](https://github.com/chelaxian/shadow/actions/runs/39143603782).

Заявленный upstream диапазон rootless: iOS 15+. Это диапазон установки, а не свидетельство проверки каждой версии.
Доступное физическое устройство: iPhone 14 Pro Max, iOS 17.0 (21A329), Dopamine 3.0.10, ElleKit 1.2.
iOS 18 и 26.0–26.0.1 на физических устройствах не проверены. Возможность установки Dopamine зависит также от модели устройства.
Совместимость со всеми приложениями не гарантируется.

HookKit Framework 3.0.5-1 распространяется без изменения из [официального релиза](https://github.com/jjolano/HookKit/releases/tag/v3.0.5).
Оба проекта распространяются под BSD 3-Clause; уведомления сохранены в `licenses/shadow/LICENSE` и `licenses/hookkit/LICENSE`.

Физическая проверка: запуск Госуслуг после исправления подтверждён пользователем. Предупреждение приложения о VPN — отдельная проблема и в этот выпуск не входит.
Налоги ФЛ запущены с загруженными Shadow.dylib, ShadowCore.dylib, Shadow.framework и HookKit; в наблюдавшемся интерфейсе предупреждения о jailbreak нет. Работа после авторизации и все операции приложения отдельно не проверялись.
Правила на устройстве: `/var/jb`, Sileo и libellekit restricted; штатная Foundation allowed. Это проверка правил, а не всех способов обнаружения.

SHA-256 Shadow: `6bfb80b751bc61fced4ebf016d486cb72f813701af010fbe5ed7c6915c7ce625`.
SHA-256 HookKit: `cab797601e64be87ba88f93fe536293af2d20750e8da84d32449df97824e435a`.

Пять Mach-O Shadow содержат arm64 и arm64e с PTRAUTH subtype `0x80000002`; проверены схема rootless и связанные библиотеки. Дополнительные RPATH `@loader_path/.jbroot` добавлены Theos наряду с `/var/jb`; прямых зависимостей от RootHide нет.
